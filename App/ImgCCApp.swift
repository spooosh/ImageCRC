import SwiftUI

@main
struct ImgCCApp: App {
    @State private var viewModel = ConversionViewModel()

    var body: some Scene {
        Window("img-cc", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
