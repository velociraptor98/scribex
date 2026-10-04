import PDFKit
import SwiftUI

struct PreviewView: NSViewRepresentable {
    var preview: AppModel.Preview?
    var zoom: AppModel.Zoom
    var onScale: (Double) -> Void
    var onPages: (Int) -> Void
    var onPage: (Int) -> Void

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
        view.backgroundColor = Ink.deep
        view.minScaleFactor = AppModel.minZoom
        view.maxScaleFactor = AppModel.maxZoom
        view.autoScales = true
        let plates = Plates(frame: view.bounds)
        plates.autoresizingMask = [.width, .height]
        view.addSubview(plates)
        context.coordinator.plates = plates

        let center = NotificationCenter.default
        context.coordinator.observers = [
            center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    context.coordinator.onScale?(Double(view.scaleFactor))
                    context.coordinator.plates?.needsDisplay = true
                }
            },

            center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated {
                    guard let view, let page = view.currentPage, let doc = view.document else { return }
                    context.coordinator.onPage?(doc.index(for: page) + 1)
                }
            },
        ]
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let c = context.coordinator
        c.onScale = onScale
        c.onPage = onPage

        if preview?.id != c.shown {
            c.shown = preview?.id
            swap(in: preview?.document, on: view)
            onPages(preview?.document.pageCount ?? 0)
            c.followScrolling(of: view)
            c.plates?.needsDisplay = true
        }

        if zoom != c.zoom {
            c.zoom = zoom
            switch zoom {
            case .fit:
                view.autoScales = true
            case let .scale(s):
                view.autoScales = false
                view.scaleFactor = s
            }
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
        var zoom: AppModel.Zoom?
        var onScale: ((Double) -> Void)?
        var onPage: ((Int) -> Void)?
        var observers: [any NSObjectProtocol] = []
        weak var plates: Plates?
        private weak var clip: NSClipView?

        /// Scrolling moves the pages under the plates. PDFKit makes its scroll
        /// view along with the first document, so this waits until there is one.
        func followScrolling(of view: PDFView) {
            guard let clip = view.documentView?.enclosingScrollView?.contentView, clip !== self.clip else { return }
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.plates?.needsDisplay = true }
            })
        }
    }
}

/// Drawn over the PDF view rather than into the pages, so the border sits
/// outside each page, hides none of it, and stays 7pt at any zoom.
final class Plates: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdf = superview as? PDFView, pdf.document != nil else { return }
        for page in pdf.visiblePages {
            let rect = convert(pdf.convert(page.bounds(for: pdf.displayBox), from: page), from: pdf)
            guard rect.intersects(dirtyRect) else { continue }
            Ink.text(0.14).setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: -7.5, dy: -7.5))
            outline.lineWidth = 1
            outline.stroke()
            Ink.plateEdge.setStroke()
            let edge = NSBezierPath(rect: rect.insetBy(dx: -3.5, dy: -3.5))
            edge.lineWidth = 7
            edge.stroke()
        }
    }
}

