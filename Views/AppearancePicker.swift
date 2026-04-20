import SwiftUI

struct AppearancePicker: View {
    @Binding var appearance: AppAppearance

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.label, systemImage: mode.sfSymbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(appearance.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: appearance.sfSymbol)
                    .imageScale(.large)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance")
    }
}
