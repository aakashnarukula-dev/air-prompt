import SwiftUI

struct LauncherView: View {
    var body: some View {
        LoadingIndicator()
            .frame(width: 56, height: 56)
            .background(WindowConfigurator())
    }
}

private struct LoadingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 5)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0.12, to: 0.72)
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.95), .white.opacity(0.3)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isAnimating)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask = [.borderless, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
