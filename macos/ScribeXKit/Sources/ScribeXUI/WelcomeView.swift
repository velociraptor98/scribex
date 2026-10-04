import ScribeXCore
import SwiftUI

/// The title page: new, open, the plates, and the recently set documents.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            GeometryReader { geo in
                let narrow = geo.size.width < 1040
                HStack(spacing: 0) {
                    title(narrow: narrow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Hairline(color: Tone.rule10, vertical: true)
                    recent(narrow: narrow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// Why things are greyed out, while they are.
    private var why: String? {
        model.locked ? "Available once the one-time download has finished" : nil
    }

    private func title(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Lockup(size: narrow ? 60 : 76)

            Rectangle()
                .fill(Tone.accent.opacity(0.45))
                .frame(width: 120, height: 1)
                .padding(.top, 26)
                .padding(.bottom, 40)

            HStack(spacing: 12) {
                Button("New document", action: model.newDocument)
                    .buttonStyle(InkButtonStyle(primary: true, size: .large))
                Button("Open…", action: model.openFile)
                    .buttonStyle(InkButtonStyle(size: .large))
            }
            .disabled(model.locked)
            .help(why ?? "")

            SetupView(compact: false)
                .padding(.top, 40)

            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 10) {
                Hairline()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Start from a plate —").foregroundStyle(Tone.text42)
                    ForEach(Array(plates.enumerated()), id: \.element.id) { i, plate in
                        Button(plate.name) { model.openPlate(plate) }
                            .buttonStyle(LinkishButtonStyle())
                            .help(why ?? plate.note)
                        if i < plates.count - 1 {
                            Text(" · ").foregroundStyle(Tone.text24)
                        }
                    }
                }
                .disabled(model.locked)
            }
            .font(Fonts.body(12))
        }
        .padding(.vertical, narrow ? 40 : 64)
        .padding(.horizontal, narrow ? 32 : 56)
    }

    private func recent(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recently set")
                .rubric()
                .padding(.bottom, 24)

            if model.recent.isEmpty {
                Text("No recent documents.")
                    .font(Fonts.body(12.5, italic: true))
                    .foregroundStyle(Tone.text38)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.recent) { doc in
                            RecentRow(doc: doc) { model.openRecent(doc) }
                                .disabled(model.locked)
                                .help(why ?? doc.path)
                        }
                        Hairline(color: Tone.rule10)
                    }
                }
                .scrollIndicators(.automatic)
            }

            Spacer(minLength: 24)

            HStack(spacing: 9) {
                Button { model.paletteOpen = true } label: {
                    Keycap(label: "⌘K")
                }
                .buttonStyle(.plain)
                Text("to search documents")
            }
            .font(Fonts.body(11.5))
            .foregroundStyle(Tone.text42)
        }
        .padding(.top, narrow ? 40 : 64)
        .padding(.bottom, 40)
        .padding(.horizontal, narrow ? 32 : 56)
    }
}

/// The mark and the wordmark, sized together from one font size.
private struct Lockup: View {
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.51) {
            Mark()
                .stroke(Tone.accent, style: StrokeStyle(lineWidth: size * 1.79 * 0.065, lineCap: .round))
                .frame(width: size * 1.79, height: size * 1.79)
            Text("\(Text("Scribe").foregroundStyle(Tone.text))\(Text("X").foregroundStyle(Tone.accent))")
                .font(Fonts.heading(size, .light))
                .tracking(-size * 0.02)
        }
    }
}

/// The ScribeX mark: two crossing strokes, drawn on a 100×100 grid.
nonisolated private struct Mark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(23, 33))
        path.addCurve(to: p(35, 33), control1: p(23, 23), control2: p(34, 24))
        path.addCurve(to: p(65, 67), control1: p(37, 47), control2: p(63, 53))
        path.addCurve(to: p(77, 67), control1: p(66, 77), control2: p(77, 76))
        path.move(to: p(77, 33))
        path.addCurve(to: p(65, 33), control1: p(77, 23), control2: p(66, 24))
        path.addCurve(to: p(35, 67), control1: p(63, 47), control2: p(37, 53))
        path.addCurve(to: p(23, 67), control1: p(34, 77), control2: p(23, 76))
        return path
    }
}

private struct RecentRow: View {
    var doc: RecentDoc
    var open: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 18) {
                Rectangle()
                    .fill(Tone.paper)
                    .overlay { Rectangle().strokeBorder(Tone.paperInk, lineWidth: 3) }
                    .frame(width: 38, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title)
                        .font(Fonts.heading(17, .semibold))
                        .foregroundStyle(hovering && enabled ? Tone.accent300 : Tone.text)
                    Text(details)
                        .font(Fonts.body(11.5))
                        .foregroundStyle(Tone.text42)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(when(doc.opened))
                    .font(Fonts.body(11.5))
                    .monospacedDigit()
                    .foregroundStyle(Tone.text42)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Hairline(color: Tone.rule10) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }

    /// The last two path segments — enough to tell two ch3.tex files apart —
    /// and what the document holds.
    private var details: String {
        var out = doc.path.split(separator: "/").suffix(2).joined(separator: "/")
        if doc.sections > 0 { out += " · \(doc.sections) section\(doc.sections > 1 ? "s" : "")" }
        if doc.citations > 0 { out += " · \(doc.citations) citation\(doc.citations > 1 ? "s" : "")" }
        return out
    }
}
