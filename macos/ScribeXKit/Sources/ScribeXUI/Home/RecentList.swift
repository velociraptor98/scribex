import ScribeXCore
import SwiftUI

/// The system's recent documents, the same list as File ▸ Open Recent.
struct RecentList: View {
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
        // Full width even when empty, so the heading sits where the list would.
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    RecentList().environment(Engine.preview).frame(width: 640, height: 820).background(.sunken).scribeStyle()
}
