import SwiftUI

/// The one-time download of the LaTeX packages and fonts: a card on
/// Home, a banner across a document window.
struct Setup: View {
    @Environment(Engine.self) private var engine
    var compact: Bool

    /// Measured against an empty cache: the warmup set plus the four templates.
    /// The bundle can drift, so this only paces the bar and is quoted as "about".
    static let expectedFiles = 440
    static let expectedMB = 45

    var body: some View {
        switch engine.cache {
        case .unknown, .ready: EmptyView()
        case .cold, .downloading, .failed: compact ? AnyView(banner) : AnyView(card)
        }
    }

    private var downloading: Bool { engine.cache == .downloading }

    // Never shows as finished: the last few files can outnumber the estimate,
    // and a full bar that is still working reads as a hang.
    private var share: Double { min(Double(engine.setup.files) / Double(Self.expectedFiles), 0.97) }

    private var headline: String {
        switch engine.cache {
        case .downloading: "Downloading the LaTeX essentials"
        case .failed: "The download stopped"
        default: "One-time setup"
        }
    }

    private var detail: String {
        switch engine.cache {
        case .downloading:
            "\(engine.setup.current ?? "Connecting…") · \(engine.setup.files) of about \(Self.expectedFiles) files"
        case .failed:
            "\(engine.setup.error ?? "Something went wrong.") Check your connection and try again — "
                + (engine.setup.files > 0 ? "what already arrived is kept." : "nothing is lost.")
        default:
            "ScribeX typesets without the internet, but first it needs the core LaTeX packages and fonts: about \(Self.expectedMB) MB, once."
        }
    }

    @ViewBuilder private var action: some View {
        if !downloading {
            Button(engine.cache == .failed ? "Try again" : "Download now", action: engine.setUp)
                .buttonStyle(.borderedProminent)
        }
    }

    private var card: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if downloading { ProgressView(value: share) }
                action
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Text(headline).smallCaps().foregroundStyle(.gilt)
        }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Text(headline).foregroundStyle(.gilt)
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
            if downloading { ProgressView(value: share).frame(width: 140) }
            Spacer(minLength: 0)
            action
        }
        .font(Fonts.text(12.5))
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gilt.opacity(0.12))
    }
}

#Preview("Card") {
    VStack(spacing: 24) {
        Setup(compact: false).environment(Engine.preview(.cold))
        Setup(compact: false).environment(Engine.preview(.downloading, files: 180))
        Setup(compact: false).environment(Engine.preview(.failed, error: "The network connection was lost."))
    }
    .frame(width: 472).padding(40).scribeStyle()
}

#Preview("Banner") {
    VStack(spacing: 0) {
        Setup(compact: true).environment(Engine.preview(.cold))
        Setup(compact: true).environment(Engine.preview(.downloading, files: 180))
        Setup(compact: true).environment(Engine.preview(.failed, error: "The network connection was lost."))
    }
    .frame(width: 900).scribeStyle()
}
