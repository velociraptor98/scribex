import AppKit
import SwiftUI

/// The 40px bar across the top of every screen.
///
/// The window's own title bar is transparent, so the traffic lights are drawn
/// by the system over this one; it leaves room for them and moves the window
/// when dragged.
struct TitleBar<Right: View>: View {
    /// Centred, in small caps. Omitted on the welcome screen.
    var title: String?
    /// Right-hand indicators: the offline lamp, downloads, autosave.
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

/// Empty title-bar space that drags the window, and zooms it on a double click
/// as a real title bar would.
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
