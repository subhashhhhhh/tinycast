import CoreServices
import Foundation
import UniformTypeIdentifiers

enum FileSearchService {
    enum Failure: Error {
        case couldNotCreateQuery
        case couldNotStartQuery
    }

    nonisolated static func search(
        query rawQuery: String, expression: String, policy: FileSearchPolicy
    ) throws -> [FileSearchResult] {
        try Signposts.interval("FileSearchService.search") {
            let selection = resolveScopes(policy)
            let scopes = selection.directories
            var results = selection.rootItems.compactMap { candidate -> FileSearchResult? in
                guard
                    FileSearchQuery.matches(
                        filename: candidate.url.lastPathComponent, query: rawQuery)
                else { return nil }
                return FileSearchResult(
                    url: candidate.url, isDirectory: candidate.isDirectory,
                    homeDirectory: policy.homeDirectory)
            }
            guard !scopes.isEmpty else {
                return FileSearchQuery.rank(
                    results, for: rawQuery, ignoring: policy.ignore, limit: policy.resultLimit)
            }

            guard let query = MDQueryCreate(nil, expression as CFString, nil, nil) else {
                throw Failure.couldNotCreateQuery
            }
            MDQuerySetSearchScope(query, scopes as CFArray, 0)
            MDQuerySetMaxCount(query, policy.candidateLimit)
            guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
                throw Failure.couldNotStartQuery
            }

            var seen = Set(results.map(\.id))
            let attrs = [kMDItemPath, kMDItemFSInvisible, kMDItemContentType] as CFArray
            for index in 0..<MDQueryGetResultCount(query) {
                guard let rawItem = MDQueryGetResultAtIndex(query, index) else { continue }
                let item = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
                guard let dict = MDItemCopyAttributes(item, attrs) as? [CFString: Any],
                    let path = dict[kMDItemPath] as? String
                else { continue }
                let hidden =
                    (dict[kMDItemFSInvisible] as? NSNumber)?.boolValue
                    ?? (dict[kMDItemFSInvisible] as? Bool ?? false)
                guard !hidden else { continue }

                let contentType = (dict[kMDItemContentType] as? String).flatMap(UTType.init)
                guard contentType?.conforms(to: .application) != true else { continue }

                let result = FileSearchResult(
                    url: URL(fileURLWithPath: path),
                    isDirectory: contentType?.conforms(to: .folder) == true,
                    homeDirectory: policy.homeDirectory)
                guard seen.insert(result.id).inserted else { continue }
                results.append(result)
            }
            return FileSearchQuery.rank(
                results, for: rawQuery, ignoring: policy.ignore, limit: policy.resultLimit)
        }
    }

    private nonisolated static func resolveScopes(
        _ policy: FileSearchPolicy
    ) -> FileSearchScope.Selection {
        var directories = policy.directRoots
        var rootItems: [FileSearchScope.Candidate] = []
        if policy.includesHome {
            let (selection, cloud) = ScopeCache.shared.getSelection(homeDirectory: policy.homeDirectory)
            directories += selection.directories
            directories += cloud
            rootItems = selection.rootItems
        }
        return FileSearchScope.Selection(
            directories: deduplicated(directories), rootItems: rootItems)
    }

    private nonisolated static func discoverScopes(homeDirectory: URL) -> FileSearchScope.Selection {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isPackageKey, .contentTypeKey
        ]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: homeDirectory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles])) ?? []
        let candidates = urls.compactMap { url -> FileSearchScope.Candidate? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileSearchScope.Candidate(
                url: url,
                isDirectory: values.isDirectory == true,
                isHidden: values.isHidden == true,
                isPackage: values.isPackage == true,
                isApplication: values.contentType?.conforms(to: .application) == true)
        }
        return FileSearchScope.select(candidates)
    }

    private nonisolated static func cloudScopes(homeDirectory: URL) -> [URL] {
        let candidates = [
            homeDirectory.appending(path: "Library/CloudStorage", directoryHint: .isDirectory),
            homeDirectory.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        ]
        return candidates.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private nonisolated static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private final class ScopeCache: @unchecked Sendable {
        static let shared = ScopeCache()
        private let lock = NSLock()
        private var cachedHome: URL?
        private var cachedSelection: FileSearchScope.Selection?
        private var cachedCloud: [URL]?
        private var cachedAt: ContinuousClock.Instant?
        private let ttl: Duration = .seconds(10)

        func getSelection(homeDirectory: URL) -> (FileSearchScope.Selection, [URL]) {
            lock.lock()
            defer { lock.unlock() }
            let now = ContinuousClock.now
            if let cachedHome, cachedHome == homeDirectory,
                let cachedSelection, let cachedCloud,
                let cachedAt, now - cachedAt < ttl
            {
                return (cachedSelection, cachedCloud)
            }
            let selection = FileSearchService.discoverScopes(homeDirectory: homeDirectory)
            let cloud = FileSearchService.cloudScopes(homeDirectory: homeDirectory)
            self.cachedHome = homeDirectory
            self.cachedSelection = selection
            self.cachedCloud = cloud
            self.cachedAt = now
            return (selection, cloud)
        }
    }
}
