import SwiftUI

/// The app icon, name and version at the top of Home.
struct Identity: View {
    var body: some View {
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
}

#Preview {
    Identity().padding(40).scribeStyle()
}
