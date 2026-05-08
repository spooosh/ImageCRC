import SwiftUI

@main
@MainActor
struct ImageCRCApp: App {
    @State private var viewModel = ConversionViewModel()
    @AppStorage("appAppearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        Window("ImageCRC", id: "main") {
            ContentView(viewModel: viewModel, appearance: $appearance)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear {
                    UITestSupport.applyLaunchArguments(to: viewModel)
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
