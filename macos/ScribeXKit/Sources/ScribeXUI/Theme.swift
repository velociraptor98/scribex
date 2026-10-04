import AppKit
import CoreText
import SwiftUI

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum Ink {
    static let ground = NSColor(rgb: 0x171614)
    static let raised = NSColor(rgb: 0x1C1B19)
    static let editor = NSColor(rgb: 0x1A1917)
    static let deep = NSColor(rgb: 0x141312)
    static let panel = NSColor(rgb: 0x201F1D)

    static let paper = NSColor(rgb: 0xF3F2F2)
    static let paperInk = NSColor(rgb: 0x201F1D)
    static let plateEdge = NSColor(rgb: 0x2D2B2B)

    static let text = NSColor(rgb: 0xECE7DF)
    static func text(_ alpha: CGFloat) -> NSColor { NSColor(rgb: 0xECE7DF, alpha: alpha) }

    static let accent = NSColor(rgb: 0xC28D41)
    static let accent300 = NSColor(rgb: 0xFACB8D)
    static let accent400 = NSColor(rgb: 0xE1AD66)
    static func accent(_ alpha: CGFloat) -> NSColor { NSColor(rgb: 0xC28D41, alpha: alpha) }

    /// Errors stay within the palette: a proof-reader's red would shout.
    static let mark = NSColor(rgb: 0xD98168)
}

enum Tone {
    static let ink = Color(nsColor: Ink.ground)
    static let inkRaised = Color(nsColor: Ink.raised)
    static let inkEditor = Color(nsColor: Ink.editor)
    static let inkDeep = Color(nsColor: Ink.deep)
    static let inkPanel = Color(nsColor: Ink.panel)

    static let paper = Color(nsColor: Ink.paper)
    static let paperInk = Color(nsColor: Ink.paperInk)
    static let plateEdge = Color(nsColor: Ink.plateEdge)

    static let text = Color(nsColor: Ink.text)
    static let text82 = Color(nsColor: Ink.text(0.82))
    static let text70 = Color(nsColor: Ink.text(0.7))
    static let text62 = Color(nsColor: Ink.text(0.62))
    static let text60 = Color(nsColor: Ink.text(0.6))
    static let text55 = Color(nsColor: Ink.text(0.55))
    static let text50 = Color(nsColor: Ink.text(0.5))
    static let text45 = Color(nsColor: Ink.text(0.45))
    static let text42 = Color(nsColor: Ink.text(0.42))
    static let text38 = Color(nsColor: Ink.text(0.38))
    static let text34 = Color(nsColor: Ink.text(0.34))
    static let text24 = Color(nsColor: Ink.text(0.24))

    static let rule = Color(nsColor: Ink.text(0.12))
    static let rule10 = Color(nsColor: Ink.text(0.1))
    static let ruleSoft = Color(nsColor: Ink.text(0.08))
    static let ruleStrong = Color(nsColor: Ink.text(0.2))
    static let rule14 = Color(nsColor: Ink.text(0.14))

    static let accent = Color(nsColor: Ink.accent)
    static let accent300 = Color(nsColor: Ink.accent300)
    static let accent400 = Color(nsColor: Ink.accent400)
    static let accentWash = Color(nsColor: Ink.accent(0.1))
    static let accentEdge = Color(nsColor: Ink.accent(0.4))

    static let mark = Color(nsColor: Ink.mark)
    static let scrim = Color(nsColor: NSColor(rgb: 0x0C0B0A, alpha: 0.72))
}

enum Fonts {
    /// Register the bundled faces with this process. Only the Latin subsets:
    /// their extended siblings share PostScript names, so registering both
    /// would leave one shadowing the other; anything outside Latin-1 falls back
    /// to the system cascade.
    static let registered: Void = {
        let names = ["cormorant-garamond-latin", "cormorant-garamond-latin-italic", "lora-latin", "lora-latin-italic"]
        let urls = names.compactMap { Bundle.module.url(forResource: $0, withExtension: "woff2", subdirectory: "Fonts") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    /// The serifs are variable fonts, which SwiftUI cannot re-weight, so each
    /// weight is asked for by its named instance.
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = registered
        let name = switch weight {
        case .light: "CormorantGaramond-Light"
        case .medium: "CormorantGaramond-Medium"
        case .semibold: "CormorantGaramond-SemiBold"
        case .bold: "CormorantGaramond-Bold"
        default: "CormorantGaramond-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    static func body(_ size: CGFloat, italic: Bool = false) -> Font {
        _ = registered
        return .custom(italic ? "Lora-Italic" : "Lora-Regular", fixedSize: size)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

extension View {
    func rubric(_ color: Color = Tone.text38, size: CGFloat = 10.5, tracking: CGFloat = 0.18) -> some View {
        font(Fonts.body(size))
            .textCase(.uppercase)
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

struct Hairline: View {
    var color = Tone.rule
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

struct Dot: View {
    var color: Color
    var hollow = false
    var pulsing = false
    var period = 1.1

    var body: some View {
        Circle()
            .fill(hollow ? .clear : color)
            .overlay { if hollow { Circle().strokeBorder(color, lineWidth: 1) } }
            .frame(width: 5, height: 5)
            .pulsing(pulsing, period: period)
    }
}

extension View {
    func pulsing(_ on: Bool, period: Double = 1.1) -> some View {
        modifier(Pulse(on: on, period: period))
    }
}

private struct Pulse: ViewModifier {
    var on: Bool
    var period: Double

    func body(content: Content) -> some View {
        if on {
            content.phaseAnimator([1.0, 0.45]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: period / 2) }
        } else {
            content
        }
    }
}

struct InkButtonStyle: ButtonStyle {
    enum Size { case small, regular, large }

    var primary = false
    var size = Size.regular

    func makeBody(configuration: Configuration) -> some View {
        InkButton(configuration: configuration, primary: primary, size: size)
    }

    private struct InkButton: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let size: Size
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let hot = hovering && enabled
            let (fontSize, h, v): (CGFloat, CGFloat, CGFloat) = switch size {
            case .small: (12.5, 12, 6)
            case .regular: (13.5, 16, 8)
            case .large: (14, 18, 10)
            }
            configuration.label
                .font(Fonts.heading(fontSize, .semibold))
                .lineLimit(1)
                .padding(.horizontal, h)
                .padding(.vertical, v)
                .foregroundStyle(primary ? (hot ? Tone.accent300 : Tone.accent) : (hot ? Tone.text : Tone.text70))
                .background(primary && hot ? Tone.accentWash : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(primary ? Tone.accent : hot ? Tone.text55 : Tone.ruleStrong, lineWidth: 1)
                }
                .contentShape(Rectangle())
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

struct LinkishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Linkish(configuration: configuration)
    }

    private struct Linkish: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let hot = hovering && enabled
            configuration.label
                .foregroundStyle(hot ? Tone.accent300 : Tone.text70)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(hot ? Tone.accentEdge : .clear).frame(height: 1).offset(y: 1)
                }
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

struct HoverButtonStyle: ButtonStyle {
    var color: Color = Tone.text55
    var hover: Color = Tone.text

    func makeBody(configuration: Configuration) -> some View {
        Hovering(configuration: configuration, color: color, hover: hover)
    }

    private struct Hovering: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let hover: Color
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && enabled ? hover : color)
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

struct Keycap: View {
    var label: String
    var color = Tone.text55
    var edge = Tone.ruleStrong

    var body: some View {
        Text(label)
            .font(Fonts.mono(11))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(edge, lineWidth: 1) }
    }
}
