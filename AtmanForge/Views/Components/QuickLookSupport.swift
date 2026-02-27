import SwiftUI

#if os(macOS)
import AppKit
import QuickLookUI

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var previewURL: URL?

    func preview(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func updateIfVisible(url: URL) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        preview(url: url)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }
}

struct KeyPressMonitor: NSViewRepresentable {
    let shouldHandleSpace: () -> Bool
    let onSpace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldHandleSpace: shouldHandleSpace, onSpace: onSpace)
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldHandleSpace = shouldHandleSpace
        context.coordinator.onSpace = onSpace
    }

    final class Coordinator: NSObject {
        var shouldHandleSpace: () -> Bool
        var onSpace: () -> Void
        private var monitor: Any?

        init(shouldHandleSpace: @escaping () -> Bool, onSpace: @escaping () -> Void) {
            self.shouldHandleSpace = shouldHandleSpace
            self.onSpace = onSpace
            super.init()
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 49 {
                    if self.isTextInputFocused() { return event }
                    guard self.shouldHandleSpace() else { return event }
                    self.onSpace()
                    return nil
                }
                return event
            }
        }

        private func isTextInputFocused() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            if responder is NSTextView { return true }
            if responder is NSTextField { return true }
            return false
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    private final class KeyCatcherView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }
}

extension View {
    func quickLookKeyHandler(appState: AppState) -> some View {
        background(KeyPressMonitor(
            shouldHandleSpace: { [weak appState] in appState?.hoveredPreviewURL != nil },
            onSpace: { [weak appState] in
                guard let appState, let url = appState.hoveredPreviewURL else { return }
                QuickLookController.shared.preview(url: url)
            }
        ))
    }
}
#endif
