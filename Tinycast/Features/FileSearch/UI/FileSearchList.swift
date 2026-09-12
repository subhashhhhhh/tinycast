import AppKit
import Darwin
import SwiftUI

struct FileSearchList: View {

    @Environment(\.metrics) private var metrics
    let results: [FileSearchResult]
    let selectedID: FileSearchResult.ID?
    var showsInfoPanel = false
    let scroll: ScrollIntent
    let onSelect: (FileSearchResult) -> Void
    let onActivate: (FileSearchResult) -> Void
    let onActions: (FileSearchResult) -> Void
    var onDropped: (() -> Void)? = nil

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Results", isFirst: true)
                    ForEach(results) { result in
                        FileSearchRow(
                            result: result,
                            selected: result.id == selectedID,
                            showsInfoPanel: showsInfoPanel
                        )
                        .id(result.id)
                        .selectionFrame(result.id == selectedID)
                        .contentShape(Rectangle())
                        .overlay {
                            FileDragHandle(
                                url: result.url,
                                resultID: result.id,
                                onSelect: { onSelect(result) },
                                onActivate: { onActivate(result) },
                                onDropped: onDropped)
                        }
                        .onRightClick { onActions(result) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        .onDisappear {
            IconCache.purgeFitted()
            FilePreviewThumbnail.purgePreviews()
            ImageThumbnail.purgePreviews()
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}

private struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    let showsInfoPanel: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool, showsInfoPanel: Bool) {
        self.result = result
        self.selected = selected
        self.showsInfoPanel = showsInfoPanel
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(result.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(showsInfoPanel ? .tail : .middle)
            Spacer(minLength: showsInfoPanel ? 0 : metrics.spacing.md)
            if !showsInfoPanel {
                Text(result.parentPath)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            if let warm = IconCache.cachedFitted(forFile: result.id) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}

private struct FileDragHandle: NSViewRepresentable {
    var url: URL
    var resultID: String
    var onSelect: () -> Void
    var onActivate: () -> Void
    var onDropped: (() -> Void)?

    func makeNSView(context: Context) -> FileDragView {
        FileDragView()
    }

    func updateNSView(_ nsView: FileDragView, context: Context) {
        nsView.bind(
            url: url, resultID: resultID, onSelect: onSelect, onActivate: onActivate,
            onDropped: onDropped)
    }
}

private final class FileDragView: NSView, NSDraggingSource {
    private static let threshold: CGFloat = 4
    private static let previewPixel: CGFloat = 64

    private var url: URL?
    private var resultID: String?
    private var onSelect: (() -> Void)?
    private var onActivate: (() -> Void)?
    private var onDropped: (() -> Void)?

    func bind(
        url: URL, resultID: String, onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void, onDropped: (() -> Void)?
    ) {
        self.url = url
        self.resultID = resultID
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onDropped = onDropped
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return nil
        default: return super.hitTest(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onSelect?()
        if event.clickCount == 2 {
            onActivate?()
            return
        }

        let start = NSEvent.mouseLocation
        var passedThreshold = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.threshold else { return }
            passedThreshold = true
            stop.pointee = true
        }

        guard passedThreshold, let url else { return }
        beginDrag(url: url, with: event)
    }

    private func beginDrag(url: URL, with event: NSEvent) {
        let image = dragImage(for: url)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragImage(for url: URL) -> NSImage {
        ImageThumbnail.cached(url, maxPixel: Self.previewPixel)
            ?? FilePreviewThumbnail.cached(url, maxPixel: Self.previewPixel)
            ?? (resultID.flatMap { IconCache.cachedFitted(forFile: $0) })
            ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        onDropped?()
    }
}
