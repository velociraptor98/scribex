import ScribeXCore
import SwiftUI

/// The strip along the window's foot: the last build in one line, opening
/// into TeX's passes.
struct PressLogView: View {
    let model: Session

    var body: some View {
        @Bindable var model = model
        DisclosureGroup(isExpanded: $model.pressOpen) {
            let rows = model.press.isEmpty ? [PressRow(stage: "—", detail: "no run yet")] : model.press
            Grid(alignment: .leading, verticalSpacing: 4) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.stage)
                        Text(row.detail).foregroundStyle(row.flagged ? AnyShapeStyle(.gilt) : AnyShapeStyle(.secondary))
                    }
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Press log").smallCaps()
                Spacer()
                Text("Tectonic" + (model.buildMs.map { " · " + String(format: "%.2f s", Double($0) / 1000) } ?? ""))
                    .font(Fonts.text(11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    PressLogView(model: .preview()).scribeStyle().frame(width: 900)
}
