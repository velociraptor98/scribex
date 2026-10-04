import SwiftUI

/// The first-run download of the LaTeX packages and fonts, without which
/// nothing builds (see docs/OFFLINE.md). A card on the welcome screen, or a
/// banner above the editor.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    /// One line above the editor, rather than the title-page card.
    var compact: Bool

    /// Measured against an empty cache: the warmup set plus the four plates.
    /// The bundle can drift, so this only paces the bar and is quoted as "about".
    static let expectedFiles = 440
    static let expectedMB = 45

    var body: some View {
        switch model.cache {
        case .unknown, .ready:
            EmptyView()
        case .cold, .downloading, .failed:
            if compact { banner } else { card }
        }
    }

    private var state: AppModel.CacheState { model.cache }
    private var progress: AppModel.SetupProgress { model.setup }

    // Never shows as finished: the last few files can outnumber the estimate,
    // and a full bar that is still working reads as a hang.
    private var share: Double { min(Double(progress.files) / Double(Self.expectedFiles), 0.97) }

    private var headline: String {
        switch state {
        case .downloading: "Downloading the LaTeX essentials"
        case .failed: "The download stopped"
        default: "One-time setup"
        }
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .downloading:
            if let current = progress.current {
                Text(current).font(Fonts.mono(compact ? 12 : 12.5)).foregroundStyle(Tone.accent300)
            } else {
                Text("Connecting…")
            }
            Text("\(progress.files) of about \(Self.expectedFiles) files")
                .foregroundStyle(Tone.text42)
                .font(Fonts.body(compact ? 12.5 : 12))
                .monospacedDigit()
        case .failed:
            Text("\(progress.error ?? "Something went wrong.") Check your connection and try again — "
                + (progress.files > 0 ? "what already arrived is kept." : "nothing is lost."))
        default:
            if compact {
                Text("Nothing can be built until the LaTeX packages and fonts are downloaded — about \(Self.expectedMB) MB, once.")
            } else {
                Text("ScribeX typesets without the internet, but first it needs the core LaTeX packages and fonts: about \(Self.expectedMB) MB, a minute or two, once. Documents open as soon as it finishes, and every plate works offline after that.")
            }
        }
    }

    @ViewBuilder private var action: some View {
        if state != .downloading {
            Button(state == .failed ? "Try again" : "Download now", action: model.setUp)
                .buttonStyle(InkButtonStyle(primary: true, size: compact ? .small : .regular))
        }
    }

    @ViewBuilder private var bar: some View {
        if state == .downloading {
            GeometryReader { geo in
                Rectangle().fill(Tone.rule)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Tone.accent)
                            .frame(width: geo.size.width * share)
                            .animation(.easeOut(duration: 0.3), value: share)
                    }
            }
            .frame(height: 3)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline).rubric(Tone.accent300)
            VStack(alignment: .leading, spacing: 4) { detail }
                .font(Fonts.body(13))
                .lineSpacing(4)
                .foregroundStyle(Tone.text70)
                .fixedSize(horizontal: false, vertical: true)
            bar
            action
            if state == .downloading {
                Text("Documents open as soon as this finishes.")
                    .font(Fonts.body(12, italic: true))
                    .foregroundStyle(Tone.text42)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tone.accentWash)
        .overlay { Rectangle().strokeBorder(state == .failed ? Tone.rule : Tone.accentEdge, lineWidth: 1) }
    }

    private var banner: some View {
        Banner {
            Text(headline).foregroundStyle(Tone.accent300).fixedSize()
            HStack(spacing: 10) { detail }
                .lineLimit(1)
                .truncationMode(.tail)
            if state == .downloading {
                bar.frame(width: 140)
            }
            action
            if state == .downloading {
                Text("keep writing — the preview appears when it finishes").bannerNote()
            }
        }
    }
}

/// The strip above the editor for setup and missing packages.
struct Banner<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
            Spacer(minLength: 0)
        }
        .font(Fonts.body(12.5))
        .foregroundStyle(Tone.text70)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(Tone.accentWash)
        .overlay(alignment: .bottom) { Hairline(color: Tone.accentEdge) }
    }
}

extension Text {
    func bannerNote() -> some View {
        italic().foregroundStyle(Tone.text38).lineLimit(1)
    }
}
