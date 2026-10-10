import ScribeXCore
import SwiftUI

/// Create and Open, with the setup card beneath while the engine isn't ready.
struct StartActions: View {
    @Environment(Engine.self) private var engine
    @Environment(\.newDocument) private var newDocument

    var body: some View {
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
            Setup(compact: false)
        }
    }
}

#Preview {
    StartActions().environment(Engine.preview).frame(width: 472).padding(40).scribeStyle()
}
