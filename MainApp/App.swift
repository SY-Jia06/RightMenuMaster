import SwiftUI

@main
struct RightMenuMasterApp: App {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 640, minHeight: 500)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)

        Settings {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 640, minHeight: 500)
        }
    }
}
