import AppKit
import SwiftUI

/// The right-side preview and metadata panel for the selected file search result.
struct FileSearchPreview: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let result: FileSearchResult?

    @State private var probe: FileMetadataProbe?
    @State private var thumbnail: NSImage?
    @State private var textLines: [String]?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "tif", "bmp", "ico"
    ]

    private static let textExtensions: Set<String> = [
        "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "swift", "py", "rb", "rs", "go", "java", "kt", "scala",
        "c", "h", "cpp", "hpp", "cc", "m", "mm", "cs",
        "sh", "bash", "zsh", "fish", "bat", "cmd", "ps1",
        "html", "htm", "css", "scss", "sass", "less",
        "json", "json5", "yaml", "yml", "toml", "xml", "plist",
        "md", "markdown", "txt", "log", "csv", "tsv",
        "sql", "env", "conf", "ini", "cfg", "properties",
        "dockerfile", "makefile", "cmake", "gradle"
    ]

    var body: some View {
        if let result {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    previewStage(for: result)
                        .frame(maxWidth: .infinity)
                        .padding(.top, metrics.spacing.md)
                        .padding(.bottom, metrics.spacing.lg)

                    metadataSection(for: result)
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.bottom, metrics.spacing.lg)
            }
            .edgeDissolve()
            .thinScrollbar()
            .task(id: result.id) {
                thumbnail = nil
                textLines = nil
                probe = nil
                let pixel = max(previewMaxHeight * 2, 240)
                let ext = result.url.pathExtension.lowercased()
                if Self.imageExtensions.contains(ext) {
                    thumbnail = ImageThumbnail.cached(result.url, maxPixel: pixel)
                    if thumbnail == nil {
                        thumbnail = await ImageThumbnail.loadAsync(result.url, maxPixel: pixel)
                    }
                } else if Self.textExtensions.contains(ext) {
                    textLines = await Task.detached(priority: .userInitiated) {
                        FileTextPreview.loadLines(url: result.url)
                    }.value
                } else {
                    thumbnail = FilePreviewThumbnail.cached(result.url, maxPixel: pixel)
                    if thumbnail == nil {
                        thumbnail = await FilePreviewThumbnail.loadAsync(result.url, maxPixel: pixel)
                    }
                    if thumbnail == nil && !result.isDirectory {
                        textLines = await Task.detached(priority: .userInitiated) {
                            FileTextPreview.loadLines(url: result.url)
                        }.value
                    }
                }
                probe = await Task.detached(priority: .userInitiated) {
                    FileMetadataProbe.probe(url: result.url)
                }.value
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func previewStage(for result: FileSearchResult) -> some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: previewMaxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } else if let textLines, !textLines.isEmpty {
                codePreview(lines: textLines)
            } else {
                VStack(spacing: metrics.spacing.sm) {
                    Image(systemName: result.isDirectory ? "folder" : "doc")
                        .font(.system(size: placeholderIconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: previewMaxHeight)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
            }
        }
    }

    private func codePreview(lines: [String]) -> some View {
        HStack(alignment: .top, spacing: metrics.spacing.sm) {
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(0..<lines.count, id: \.self) { idx in
                    Text("\(idx + 1)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<lines.count, id: \.self) { idx in
                    Text(lines[idx].isEmpty ? " " : lines[idx])
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: previewMaxHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
    }

    private var previewMaxHeight: CGFloat {
        metrics.scaled(settings.fileSearchPreviewSize.maxHeight)
    }

    private var placeholderIconSize: CGFloat {
        metrics.scaled(settings.fileSearchPreviewSize.placeholderIconSize)
    }

    private struct MetadataRowItem: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    @ViewBuilder
    private func metadataSection(for result: FileSearchResult) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Metadata")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                let items = metadataItems(for: result)
                ForEach(items) { item in
                    if item.id != items.first?.id {
                        Divider()
                    }
                    HStack(spacing: metrics.spacing.md) {
                        Text(item.label)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(item.value)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
    }

    private func metadataItems(for result: FileSearchResult) -> [MetadataRowItem] {
        var items: [MetadataRowItem] = [
            MetadataRowItem(label: "Name", value: result.name),
            MetadataRowItem(label: "Where", value: result.parentPath),
            MetadataRowItem(
                label: "Type",
                value: probe?.typeName ?? (result.isDirectory ? "Folder" : "File")
            ),
        ]

        if !result.isDirectory, let bytes = probe?.fileBytes {
            items.append(MetadataRowItem(label: "Size", value: FileMetadataProbe.formatBytes(bytes)))
        }

        if let created = probe?.creationDate {
            items.append(MetadataRowItem(label: "Created", value: FileMetadataProbe.formatDate(created)))
        }

        if let modified = probe?.modificationDate {
            items.append(MetadataRowItem(label: "Modified", value: FileMetadataProbe.formatDate(modified)))
        }

        if let accessed = probe?.accessDate {
            items.append(
                MetadataRowItem(label: "Accessed", value: FileMetadataProbe.formatAccessedDate(accessed))
            )
        }

        return items
    }
}

enum FileTextPreview {
    private static let maxBytes = 4096
    private static let maxLines = 14

    nonisolated static func loadLines(url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        guard !data.contains(0) else { return nil }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }
        let lines = text.components(separatedBy: .newlines)
        return Array(lines.prefix(maxLines))
    }
}
