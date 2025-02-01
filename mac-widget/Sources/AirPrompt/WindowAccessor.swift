import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Fully borderless — removes the black title bar area
            window.styleMask = [.borderless, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setContentSize(size)
            Self.positionBottomRight(window: window, size: size)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.contentLayoutRect.size != size {
                let oldFrame = window.frame
                let newOriginY = oldFrame.origin.y + oldFrame.height - size.height
                window.setContentSize(size)
                window.setFrameOrigin(NSPoint(x: oldFrame.origin.x + oldFrame.width - size.width, y: max(newOriginY, (window.screen ?? NSScreen.main)!.visibleFrame.minY + 12)))
            }
        }
    }

    private static func positionBottomRight(window: NSWindow, size: CGSize) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let originX = visible.maxX - size.width - margin
        let originY = visible.minY + margin
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
