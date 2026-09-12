import Foundation

/// Decides what a configured scope list means: which roots Spotlight takes as-is, and what to drop.
struct FileSearchPolicy: Sendable, Equatable {
    let homeDirectory: URL
    /// Home is held apart because `~/Library` can never be a scope, so it is expanded.
    let directRoots: [URL]
    let includesHome: Bool
    let ignore: FileSearchIgnoreList
    let includeContent: Bool
    let resultLimit: Int

    var candidateLimit: Int { max(1_000, min(5_000, resultLimit * 5)) }

    init(
        scopes: [String], ignorePatterns: [String], homeDirectory: URL,
        includeContent: Bool = false, resultLimit: Int = 200
    ) {
        self.homeDirectory = homeDirectory
        let home = homeDirectory.standardizedFileURL.path
        let roots = FileSearchScope.roots(for: scopes, homeDirectory: homeDirectory)
        directRoots = roots.filter { $0.path != home }
        includesHome = roots.count != directRoots.count
        ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + ignorePatterns)
        self.includeContent = includeContent
        self.resultLimit = resultLimit
    }
}
