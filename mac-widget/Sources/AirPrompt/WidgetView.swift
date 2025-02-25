import SwiftUI
import AppKit

struct WidgetView: View {
    @EnvironmentObject private var store: WidgetStore

    private var pillWidth: CGFloat {
        store.idToken == nil ? 140 : 260
    }

    private var windowSize: CGSize {
        if store.showQRCode && store.idToken != nil {
            return CGSize(width: max(pillWidth, 224), height: 224 + 10 + 52)
        }
        return CGSize(width: pillWidth, height: 52)
    }

    var body: some View {
        VStack(spacing: 10) {
            if store.showQRCode && store.idToken != nil {
                PairingWidgetView(store: store)
            }
            CompactWidgetView(store: store)
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .bottom)
        .background(WindowAccessor(size: windowSize))
    }
}

private struct CompactWidgetView: View {
    @ObservedObject var store: WidgetStore

    private var isReceiving: Bool {
        store.state == "receiving"
    }

    var body: some View {
        HStack(spacing: 12) {
            if store.idToken == nil {
                signedOutContent
            } else {
                signedInContent
            }
        }
        .padding(.horizontal, store.idToken == nil ? 10 : 14)
        .padding(.vertical, 10)
        .frame(width: store.idToken == nil ? 140 : 260)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                // .background(DragRegion())  // TEMP disabled — may eat button clicks
        )
    }

    @ViewBuilder
    private var signedOutContent: some View {
        Button { store.beginLogin() } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Sign in")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)

        Button { store.stopDemo() } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.36))
                    .frame(width: 16, height: 16)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var signedInContent: some View {
        BeatView(active: isReceiving || store.isRecording)
    
        Button { store.toggleRecording() } label: {
            Image(systemName: store.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isRecording ? Color.red : .white)

        Button { store.pasteLast() } label: {
            Image(systemName: "document.on.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.lastText.isEmpty ? .white.opacity(0.3) : .white)
        .disabled(store.lastText.isEmpty)

        Button { store.toggleQRCode() } label: {
            Image(systemName: "qrcode")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(store.showQRCode ? Color.white.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isRecording ? Color.white.opacity(0.3) : (store.showQRCode ? Color(red: 0.45, green: 0.85, blue: 1.0) : .white))
        .disabled(store.isRecording)

        Button { store.signOut() } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isRecording ? Color.white.opacity(0.3) : .white)
        .disabled(store.isRecording)

        Button { store.stopDemo() } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.36))
                    .frame(width: 16, height: 16)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

private struct PairingWidgetView: View {
    @ObservedObject var store: WidgetStore

    private var qrImage: NSImage? {
        guard !store.joinURL.isEmpty else { return nil }
        return QRCode.make(from: store.joinURL)
    }

    var body: some View {
        Group {
            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 224, height: 224)
            } else {
                Color.white.opacity(0.06)
                    .frame(width: 224, height: 224)
                    .overlay(ProgressView().scaleEffect(1.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

}

private struct BeatView: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: !active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(index == 1 ? Color.white : Color.white.opacity(0.75))
                        .frame(width: 4, height: barHeight(index: index, phase: phase))
                }
            }
            .frame(width: 28, height: 32)
            .padding(.leading, 2)
        }
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        guard active else { return [10.0, 16.0, 12.0, 8.0][index] }
        let wave = sin((phase * 6) + Double(index) * 0.9)
        return max(8, CGFloat(18 + wave * 10))
    }
}
