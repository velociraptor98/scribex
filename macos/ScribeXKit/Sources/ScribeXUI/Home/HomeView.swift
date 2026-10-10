import SwiftUI

/// The window shown when no document is open: who we are, the ways in, and
/// the documents the system remembers.
public struct HomeView: View {
    public static let windowID = "home"

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Identity()
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 32) {
                    StartActions()
                    TemplateTiles()
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
}

#Preview {
    HomeView().environment(Engine.preview).frame(width: 1280, height: 820)
}
