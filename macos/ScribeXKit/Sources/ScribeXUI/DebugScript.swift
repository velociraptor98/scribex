#if DEBUG
import AppKit
import ScribeXCore

/// A development aid: drive the app through a few steps and render the window
/// to PNGs after each, without needing Screen Recording permission.
///
///     SCRIBEX_DEBUG_SCRIPT="snap welcome; new; wait 3; snap editor; quit" \
///     SCRIBEX_DEBUG_OUT=/tmp/shots ScribeX.app/Contents/MacOS/ScribeX
///
/// Steps: `snap NAME`, `wait SECONDS`, `new`, `open PATH`, `palette TEXT`,
/// `close`, `export`, `marks`, `type TEXT`, `press`, `fetch`, `essentials`,
/// `network`, `state LABEL`, `quit`.
enum DebugScript {
    static func runIfRequested(model: AppModel, window: NSWindow) {
        let env = ProcessInfo.processInfo.environment
        guard let script = env["SCRIBEX_DEBUG_SCRIPT"] else { return }
        let out = URL(filePath: env["SCRIBEX_DEBUG_OUT"] ?? NSTemporaryDirectory())
        Task {
            try? await Task.sleep(for: .seconds(1))
            for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let (verb, arg) = step.firstIndex(of: " ").map {
                    (String(step[..<$0]), String(step[step.index(after: $0)...]))
                } ?? (step, "")
                switch verb {
                case "snap": snap(window, to: out.appending(path: "\(arg).png"))
                case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
                case "new": model.newDocument()
                case "palette":
                    model.paletteOpen = true
                    try? await Task.sleep(for: .milliseconds(300))
                    (window.firstResponder as? NSTextView)?.insertText(arg, replacementRange: NSRange(location: NSNotFound, length: 0))
                case "close": model.paletteOpen = false; model.exportOpen = false
                case "export": model.requestExport()
                case "marks": model.rightPane = .marks
                case "press": model.pressOpen.toggle()
                case "type": model.editor.insert(arg)
                case "page":
                    // Neither snapshot route captures PDFKit's page tiles, so
                    // this renders the page itself.
                    if let page = model.preview?.document.page(at: 0) {
                        let image = page.thumbnail(of: NSSize(width: 600, height: 800), for: .mediaBox)
                        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                            try? rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: "\(arg).png"))
                        }
                    }
                case "open": model.adopt((try? String(contentsOfFile: arg, encoding: .utf8)) ?? "", url: URL(filePath: arg), note: "Opened")
                case "fetch": model.build(allowNetwork: true)
                case "essentials": model.setUp()
                case "network": model.toggleOffline()
                case "state":
                    print("debug state [\(arg)]: status=\(model.status) busy=\(model.busy) missing=\(model.missing ?? "-") cache=\(model.cache) offline=\(model.offline) preview=\(model.preview?.id ?? -1) fetched=\(model.fetched)")
                case "quit": NSApp.terminate(nil)
                default: print("debug script: unknown step \(step)")
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    static func snap(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else { return }
        let scale = window.backingScaleFactor
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale), pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("debug script: wrote \(url.path)")
    }
}
#endif
