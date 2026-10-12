import PDFKit
import ScribeXCore
import SwiftUI

/// How the preview is zoomed: to the column's width, or to a set scale.
/// `scale` is what is on screen either way, so zooming steps from there.
struct Zoom: Equatable {
    static let range = 0.25...4.0
    static let steps = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    var fit = true
    var scale = 1.0

    /// Fit width can leave the scale between stops; this goes to the next one.
    mutating func step(_ direction: Int) {
        let next = direction > 0
            ? Self.steps.first { $0 > scale + 0.005 }
            : Self.steps.last { $0 < scale - 0.005 }
        fit = false
        scale = next ?? (direction > 0 ? Self.range.upperBound : Self.range.lowerBound)
    }
}

/// The typeset pages, under one line with zoom and Export.
struct Renderer: View {
    let model: Session
    @Binding var zoom: Zoom
    var export: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Preview").smallCaps()
                Spacer(minLength: 0)
                zoomControls
                Button("Export PDF…", action: export)
                    .disabled(model.typesetting.preview == nil || model.typesetting.busy)
            }
            .controlSize(.small)
            .monospacedDigit()
            .padding(12)

            Pages(preview: model.typesetting.preview, zoom: zoom, onScale: { zoom.scale = $0 })
                .overlay { if model.typesetting.preview == nil { Text("Nothing built yet").italic().foregroundStyle(.secondary) } }
                .frame(maxHeight: .infinity)
        }
        .background(.sunken)
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button("Zoom Out", systemImage: "minus") { zoom.step(-1) }.disabled(zoom.scale <= Zoom.range.lowerBound)
                Button("Zoom In", systemImage: "plus") { zoom.step(1) }.disabled(zoom.scale >= Zoom.range.upperBound)
            }
            .fixedSize()
            Button("\(Int((zoom.scale * 100).rounded()))%") { zoom = Zoom(fit: false, scale: 1) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Actual size")
            Toggle("Fit", isOn: $zoom.fit)
                .toggleStyle(.button)
                .help("Fit to width (⌘0)")
        }
        .fixedSize()
    }
}

/// PDFKit's view of the pages, kept in place across rebuilds.
private struct Pages: NSViewRepresentable {
    var preview: Typesetting.Preview?
    var zoom: Zoom
    var onScale: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        // Half of the 18px gap between pages above and below each one.
        view.pageBreakMargins = NSEdgeInsets(top: 9, left: 8, bottom: 9, right: 8)
        view.pageShadowsEnabled = false
        view.backgroundColor = NSColor.scribeSunken
        view.minScaleFactor = Zoom.range.lowerBound
        view.maxScaleFactor = Zoom.range.upperBound
        view.autoScales = true
        // Since macOS 14 views do not clip their drawing by default; without
        // this, the border of a page scrolled half out of view is drawn over
        // the controls around the preview.
        view.clipsToBounds = true
        let frames = PageFrames(frame: view.bounds)
        frames.clipsToBounds = true
        frames.autoresizingMask = [.width, .height]
        view.addSubview(frames)
        context.coordinator.frames = frames

        let center = NotificationCenter.default
        context.coordinator.observers = [
            center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    context.coordinator.frames?.needsDisplay = true
                    // PDFKit posts this from inside updateNSView (a new document or
                    // zoom resets the scale), and the block runs there and then;
                    // writing SwiftUI state mid-update is undefined, so report after.
                    let scale = Double(view.scaleFactor)
                    DispatchQueue.main.async { context.coordinator.onScale?(scale) }
                }
            },
        ]
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let c = context.coordinator
        c.onScale = onScale

        if preview?.id != c.shown {
            c.shown = preview?.id
            swap(in: preview?.document, on: view)
            c.followScrolling(of: view)
            c.frames?.needsDisplay = true
        }

        // The scale comes back through onScale, so only a real difference is applied.
        if zoom.fit {
            if !view.autoScales { view.autoScales = true }
        } else if view.autoScales || abs(Double(view.scaleFactor) - zoom.scale) > 0.001 {
            view.autoScales = false
            view.scaleFactor = zoom.scale
        }
    }

    /// Keeps the scroll offset, or every rebuild would throw the reader back to
    /// page 1. An edit rarely moves the pages, so the same offset shows the same
    /// place.
    private func swap(in document: PDFDocument?, on view: PDFView) {
        let clip = view.documentView?.enclosingScrollView?.contentView
        let origin = clip?.bounds.origin
        let autoScales = view.autoScales
        let scale = view.scaleFactor

        view.document = document
        // Setting a document resets the scale; put back whatever was chosen.
        if autoScales {
            view.autoScales = true
        } else {
            view.scaleFactor = scale
        }
        view.layoutDocumentView()

        if let origin, let clip, let documentView = view.documentView {
            let maxY = max(0, documentView.frame.height - clip.bounds.height)
            let maxX = max(0, documentView.frame.width - clip.bounds.width)
            clip.scroll(to: NSPoint(x: min(origin.x, maxX), y: min(origin.y, maxY)))
            clip.enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
    }

    final class Coordinator {
        var shown: Int?
        var onScale: ((Double) -> Void)?
        var observers: [any NSObjectProtocol] = []
        weak var frames: PageFrames?
        private weak var clip: NSClipView?

        /// Scrolling moves the pages under the frames. PDFKit makes its scroll
        /// view along with the first document, so this waits until there is one.
        func followScrolling(of view: PDFView) {
            guard let clip = view.documentView?.enclosingScrollView?.contentView, clip !== self.clip else { return }
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.frames?.needsDisplay = true }
            })
        }
    }
}

/// Drawn over the PDF view rather than into the pages, so the border sits
/// outside each page, hides none of it, and stays 7pt at any zoom.
private final class PageFrames: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdf = superview as? PDFView, pdf.document != nil else { return }
        for page in pdf.visiblePages {
            let rect = convert(pdf.convert(page.bounds(for: pdf.displayBox), from: page), from: pdf)
            guard rect.intersects(dirtyRect) else { continue }
            NSColor.scribeInk.withAlphaComponent(0.12).setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: -7.5, dy: -7.5))
            outline.lineWidth = 1
            outline.stroke()
            NSColor.scribePaperEdge.setStroke()
            let edge = NSBezierPath(rect: rect.insetBy(dx: -3.5, dy: -3.5))
            edge.lineWidth = 7
            edge.stroke()
        }
    }
}

#Preview {
    @Previewable @State var zoom = Zoom()
    Renderer(model: .preview(), zoom: $zoom, export: {}).scribeStyle().frame(width: 560, height: 700)
}
