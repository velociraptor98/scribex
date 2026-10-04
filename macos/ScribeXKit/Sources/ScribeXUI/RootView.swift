import ScribeXCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.screen {
            case .welcome: WelcomeView()
            case .editor: EditorScreen()
            }

            if model.exportOpen, let preview = model.preview {
                ExportSheet(pdf: preview.data, documentSheet: sheetOf(model.source))
                    .transition(.opacity)
            }

            if model.paletteOpen {
                PaletteView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.paletteOpen)
        .animation(.easeOut(duration: 0.12), value: model.exportOpen)
        .animation(.easeOut(duration: 0.2), value: model.autosaving)
        .background(Tone.ink)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
