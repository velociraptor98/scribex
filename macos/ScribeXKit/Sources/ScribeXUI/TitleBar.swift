import AppKit
import SwiftUI

/// The window's own title bar is transparent: the system draws the traffic
/// lights over this one, which has to move the window when dragged.
struct TitleBar<Right: View>: View {
    var title: String?
    @ViewBuilder var right: Right

    var body: some View {
        ZStack {
            WindowDragArea()
            if let title {
                Text(title)
                    .font(Fonts.heading(12.5))
                    .textCase(.uppercase)
                    .tracking(12.5 * 0.14)
                    .foregroundStyle(Tone.text55)
                    .lineLimit(1)
                    .padding(.horizontal, 200)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 16) {
                Spacer(minLength: 66)
                right
            }
            .padding(.horizontal, 15)
        }
        .frame(height: 40)
        .background(Tone.inkRaised)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension TitleBar where Right == EmptyView {
    init(title: String? = nil) {
        self.init(title: title) { EmptyView() }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                if action == "Minimize" {
                    window.performMiniaturize(nil)
                } else if action != "None" {
                    window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
