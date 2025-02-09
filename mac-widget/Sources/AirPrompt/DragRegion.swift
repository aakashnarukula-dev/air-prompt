import SwiftUI
import AppKit

struct DragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragNSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
