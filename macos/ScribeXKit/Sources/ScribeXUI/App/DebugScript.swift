#if DEBUG
import AppKit
import ScribeXCore
import SwiftUI

/// A development aid: drive the app through a few steps and render the front
/// window to PNGs after each, without needing Screen Recording permission.
///
///     SCRIBEX_DEBUG_SCRIPT="snap welcome; new; wait 3; snap editor; quit" \
///     SCRIBEX_DEBUG_OUT=/tmp/shots ScribeX.app/Contents/MacOS/ScribeX
///
/// Steps: `snap NAME`, `wait SECONDS`, `size WIDTH HEIGHT`, `fullscreen`, `new`, `open PATH`,
/// `run COMMAND-ID`, `palette TEXT`, `close`, `type TEXT`, `key TEXT`, `page NAME`, `fetch`,
/// `essentials`, `save`, `undo`, `menus`, `state LABEL`, `quit`. `run` takes an
/// id from `Command.all`, e.g. `run issues`.
public enum DebugScript {
    public static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let script = env["SCRIBEX_DEBUG_SCRIPT"] else { return }
        let out = URL(filePath: env["SCRIBEX_DEBUG_OUT"] ?? NSTemporaryDirectory())
        // Unbuffered, so a run cut short by a timeout still shows how far it got.
        setvbuf(stdout, nil, _IONBF, 0)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let (verb, arg) = step.firstIndex(of: " ").map {
                    (String(step[..<$0]), String(step[step.index(after: $0)...]))
                } ?? (step, "")
                await run(verb, arg, out: out)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// The last document window to appear, as its commands see it.
    static var focus: Command.Focus?

    /// The app runs in the background, so there is often no key window: this
    /// is the frontmost one, or the sheet on it.
    private static var front: NSWindow? {
        let window = NSApp.keyWindow ?? NSApp.orderedWindows.first { $0.isVisible && $0.canBecomeKey && !$0.isSheet }
        return window?.attachedSheet ?? window
    }

    private static func run(_ verb: String, _ arg: String, out: URL) async {
        let session = focus?.session
        switch verb {
        case "snap": if let front { snap(front, to: out.appending(path: "\(arg).png")) }
        case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
        case "size":
            let wh = arg.split(separator: " ").compactMap { Double($0) }
            if wh.count == 2 { front?.setContentSize(NSSize(width: wh[0], height: wh[1])) }
        case "fullscreen": front?.toggleFullScreen(nil)
        case "new": NSDocumentController.shared.newDocument(nil)
        case "open":
            _ = try? await NSDocumentController.shared.openDocument(withContentsOf: URL(filePath: arg), display: true)
        case "run":
            // The palette's route: the window's own commands, so the app need
            // not be active (the menu bar acts only on the focused window).
            if let focus, let command = Command.all(focus, engine: focus.session!.engine).first(where: { $0.id == arg }) {
                command.run()
            } else {
                print("debug script: no command \(arg)")
            }
        case "palette":
            if let focus { Command.all(focus, engine: focus.session!.engine).first { $0.id == "palette" }?.run() }
            try? await Task.sleep(for: .milliseconds(300))
            (front?.firstResponder as? NSTextView)?.insertText(arg, replacementRange: NSRange(location: NSNotFound, length: 0))
        case "close":
            // Escape, which both sheets answer.
            if let window = front, let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                window.sendEvent(event)
            }
        case "type": session?.editor.insert(arg)
        case "page":
            // Neither snapshot route captures PDFKit's page tiles, so this
            // renders the page itself.
            if let page = session?.typesetting.preview?.document.page(at: 0) {
                let image = page.thumbnail(of: NSSize(width: 600, height: 800), for: .mediaBox)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: "\(arg).png"))
                }
            }
        case "fetch": session?.typesetting.build(allowNetwork: true)
        case "essentials": session?.setUp()
        case "state":
            print("debug state [\(arg)]: text=\(session?.source.prefix(25).debugDescription ?? "-") key=\(NSApp.keyWindow?.title ?? "-") fr=\(String(describing: type(of: NSApp.keyWindow?.firstResponder as Any))) status=\(session?.typesetting.status ?? "-") busy=\(session?.typesetting.busy ?? false) windows=\(NSApp.windows.filter(\.isVisible).map { "\($0.title) edited=\($0.isDocumentEdited) full=\($0.styleMask.contains(.fullScreen)) size=\(Int($0.frame.width))x\(Int($0.frame.height))" })")
        case "key":
            // Real key events through the window, as typing would send them.
            guard let window = front else { break }
            session?.editor.focus()
            for ch in arg {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, characters: String(ch),
                                                    charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0) {
                        window.sendEvent(event)
                    }
                }
            }
        case "menus":
            // The menu bar as the app built it, for checking from a terminal.
            for top in NSApp.mainMenu?.items ?? [] where ["File", "Format", "Build", "View", "Window"].contains(top.title) {
                NSApp.mainMenu?.update()
                top.submenu?.update()
                let items: [String] = top.submenu?.items.filter { !$0.isSeparatorItem && !$0.title.isEmpty }.map { item in
                    let mods = item.keyEquivalentModifierMask
                    let keys = item.keyEquivalent.isEmpty ? "" : " " + (mods.contains(.shift) ? "⇧" : "") + "⌘" + item.keyEquivalent.uppercased()
                    return "\(item.title)\(keys)\(item.state == .on ? " ✓" : "")\(item.isEnabled ? "" : " (off)")"
                } ?? []
                print("menu \(top.title): " + items.joined(separator: " | "))
            }
        case "scroll":
            // Scroll every scroll view in the window (editor, preview, lists) by ARG points.
            func scrollViews(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrollViews) }
            for sv in front.map({ scrollViews($0.contentView!) }) ?? [] {
                let clip = sv.contentView
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + (Double(arg) ?? 400)))
                sv.reflectScrolledClipView(clip)
            }
        case "save": NSDocumentController.shared.documents.first?.save(nil)
        case "undo": NSDocumentController.shared.documents.first?.undoManager?.undo()
        case "quit": NSApp.terminate(nil)
        default: print("debug script: unknown step \(verb)")
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
