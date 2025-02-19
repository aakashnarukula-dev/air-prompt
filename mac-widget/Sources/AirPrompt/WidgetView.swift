import SwiftUI
import AppKit

struct WidgetView: View {
    @EnvironmentObject private var store: WidgetStore

    private var windowSize: CGSize {
        store.showQRCode ? CGSize(width: 224, height: 258) : CGSize(width: 296, height: 52)
    }

    var body: some View {
        Group {
            if store.showQRCode {
                PairingWidgetView(store: store)
            } else {
                CompactWidgetView(store: store)
            }
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 296)
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
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
            .frame(maxWidth: .infinity)

        Button { store.toggleRecording() } label: {
            Image(systemName: store.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isRecording ? Color.red : .white)
        .frame(maxWidth: .infinity)

        Button { store.pasteLast() } label: {
            Image(systemName: "document.on.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.lastText.isEmpty ? .white.opacity(0.3) : .white)
        .disabled(store.lastText.isEmpty)
        .frame(maxWidth: .infinity)

        Button { store.toggleQRCode() } label: {
            Image(systemName: "qrcode")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)

        Button { store.signOut() } label: {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)

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
        VStack(spacing: 10) {
            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 204, height: 204)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 204, height: 204)
                    .overlay(ProgressView().scaleEffect(1.2))
            }

            Text("Scan to connect your phone")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(width: 188)

            HStack(spacing: 8) {
                Button(action: { store.copyShareLink() }) {
                    Text(store.copiedShareLink ? "Copied" : "Copy Link")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(store.joinURL.isEmpty ? 0.3 : 0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(store.joinURL.isEmpty)

                Button(action: { store.stopDemo() }) {
                    Text("Stop")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 224, height: 258)
        .background(.ultraThinMaterial)
        .background(DragRegion())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
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
