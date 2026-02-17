import SwiftUI

@main
struct DadSoftApp: App {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentSize)
    }
}
