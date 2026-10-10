import ScribeXCore
import SwiftUI

/// The window shown when no document is open: who we are, the ways in, and
/// the documents the system remembers.
public struct WelcomeView: View {
    public static let windowID = "welcome"
    @Environment(Engine.self) private var engine
    @Environment(\.newDocument) private var newDocument

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                identity
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 32) {
                    actions
                    templateTiles
                }
            }
            .frame(width: 472)
            .frame(maxHeight: 620)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RecentList()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.sunken)
        }
        .frame(minWidth: 880, minHeight: 560)
        .scribeStyle()
    }

    private var identity: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 120, height: 120)
            Text("\(Text("Scribe"))\(Text("X").foregroundStyle(.gilt))")
                .font(Fonts.display(44))
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)").font(Fonts.text(11.5)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Group {
                Button { newDocument { TexDocument() } } label: {
                    Label("Create new document…", systemImage: "plus.square").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                Button { NSDocumentController.shared.openDocument(nil) } label: {
                    Label("Open document…", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(Fonts.display(17, .semibold))
            .controlSize(.extraLarge)
            .buttonBorderShape(.capsule)
            .disabled(engine.locked)
            // Unlocks the buttons above, so it stays outside the lock.
            SetupView(compact: false)
        }
    }

    private var templateTiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start from a template").smallCaps()
            HStack(spacing: 12) {
                ForEach(templates) { template in
                    Button { newDocument { TexDocument(text: template.source) } } label: {
                        VStack(spacing: 8) {
                            TemplateSketch(name: template.name)
                                .frame(maxWidth: .infinity, minHeight: 100)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                            Text(template.name)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(template.note)
                }
            }
            .disabled(engine.locked)
        }
    }
}

/// The system's recent documents, the same list as File ▸ Open Recent.
private struct RecentList: View {
    @Environment(Engine.self) private var engine
    @Environment(\.openDocument) private var openDocument
    @State private var recents: [URL] = []
    @State private var selection: URL?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent").smallCaps().padding(.horizontal, 48)
            if let problem {
                Text(problem).foregroundStyle(.mark).padding(.horizontal, 48)
            }
            if recents.isEmpty {
                Text("No recent documents.").italic().foregroundStyle(.secondary).padding(.horizontal, 48)
                Spacer()
            } else {
                List(recents, id: \.self, selection: $selection) { url in
                    RecentRow(url: url)
                }
                .scrollContentBackground(.hidden)
                // Return or a double-click opens, as in Finder.
                .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
                    urls.first.map(open)
                }
                .disabled(engine.locked)
                .padding(.horizontal, 36)
            }
        }
        .padding(.top, 64)
        .onAppear {
            recents = NSDocumentController.shared.recentDocumentURLs
            selection = recents.first
        }
    }

    private func open(_ url: URL) {
        Task {
            do {
                try await openDocument(at: url)
            } catch {
                problem = "\(url.lastPathComponent) could not be opened. It may have moved or been deleted."
                recents = NSDocumentController.shared.recentDocumentURLs
            }
        }
    }
}

private struct RecentRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Fonts.display(17, .semibold))
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(Fonts.text(11.5)).foregroundStyle(.secondary).truncationMode(.middle)
            }
            .lineLimit(1)
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        documentTitle((try? String(contentsOf: url, encoding: .utf8)) ?? "", path: url.path)
    }
}

/// A template's first page in miniature: a sheet of paper with grey lines where
/// its type would be.
private struct TemplateSketch: View {
    let name: String

    var body: some View {
        let slides = name == "Beamer"
        VStack(alignment: .leading, spacing: 3) {
            if slides {
                Rectangle().fill(.paperEdge).frame(height: 12)
            }
            ForEach(lines.indices, id: \.self) { i in
                Rectangle().frame(width: lines[i], height: i == 0 && !slides ? 2.5 : 1)
            }
        }
        .foregroundStyle(Color.paperEdge.opacity(0.5))
        .padding(slides ? 0 : 8)
        .frame(width: slides ? 76 : 57, height: slides ? 57 : 76, alignment: .topLeading)
        .background(.paper)
        .shadow(radius: 3, y: 2)
    }

    private var lines: [CGFloat] {
        switch name {
        case "Letter": [16, 20, 0, 40, 40, 40, 24]
        case "Thesis": [30, 20, 0, 14]
        case "Beamer": [36, 28, 32]
        default: [22, 0, 40, 40, 40, 28, 18, 40, 33]
        }
    }
}

#Preview {
    WelcomeView().environment(Engine.preview).frame(width: 1280, height: 820)
}
