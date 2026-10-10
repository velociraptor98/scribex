import AppKit
import CoreText
import SwiftUI

// The book on a Mac: native controls, set in Cormorant and Lora on warm dark
// paper, tinted with the gilt of a bound spine. Everything else is SwiftUI's.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static let scribeCanvas = NSColor(hex: 0x171614)
    static let scribeSunken = NSColor(hex: 0x141312)
    static let scribeEditor = NSColor(hex: 0x1A1917)
    static let scribeInk = NSColor(hex: 0xECE7DF)
    static let scribeGilt = NSColor(hex: 0xC28D41)
    static let scribeGiltLight = NSColor(hex: 0xE1AD66)
    static let scribePaper = NSColor(hex: 0xF3F2F2)
    static let scribePaperEdge = NSColor(hex: 0x2D2B2B)
    /// Errors stay within the palette: a proof-reader's red would shout.
    static let scribeMark = NSColor(hex: 0xD98168)
}

extension ShapeStyle where Self == Color {
    static var canvas: Color { Color(nsColor: .scribeCanvas) }
    static var sunken: Color { Color(nsColor: .scribeSunken) }
    static var ink: Color { Color(nsColor: .scribeInk) }
    static var gilt: Color { Color(nsColor: .scribeGilt) }
    static var paper: Color { Color(nsColor: .scribePaper) }
    static var paperEdge: Color { Color(nsColor: .scribePaperEdge) }
    static var mark: Color { Color(nsColor: .scribeMark) }
}

enum Fonts {
    /// The bundled faces, registered once. Only the Latin subsets: their
    /// extended siblings share PostScript names and would shadow them.
    private static let registered: Void = {
        let names = ["cormorant-garamond-latin", "cormorant-garamond-latin-italic", "lora-latin", "lora-latin-italic"]
        let urls = names.compactMap { Bundle.module.url(forResource: $0, withExtension: "woff2", subdirectory: "Fonts") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    /// Cormorant Garamond, for display and headings. A variable font SwiftUI
    /// cannot re-weight, so each weight is its named instance.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = registered
        let name = weight == .light ? "CormorantGaramond-Light" : weight == .semibold ? "CormorantGaramond-SemiBold" : "CormorantGaramond-Regular"
        return .custom(name, fixedSize: size)
    }

    /// Lora, for reading.
    static func text(_ size: CGFloat = 13, italic: Bool = false) -> Font {
        _ = registered
        return .custom(italic ? "Lora-Italic" : "Lora-Regular", fixedSize: size)
    }
}

extension View {
    /// Applied once at the root of each window.
    func scribeStyle() -> some View {
        font(Fonts.text())
            .foregroundStyle(.ink)
            .tint(.gilt)
            .buttonStyle(.bordered)
            .background(.canvas)
            .preferredColorScheme(.dark)
    }

    /// The small-caps label over a panel or group.
    func smallCaps() -> some View {
        font(Fonts.text(10.5)).textCase(.uppercase).tracking(1.7).foregroundStyle(.secondary)
    }
}
