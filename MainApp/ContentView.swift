import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            MenuConfigView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Menu Items", systemImage: "list.bullet")
                }
                .tag(0)

            TemplateListView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Templates", systemImage: "doc.badge.plus")
                }
                .tag(1)

            ScriptEditorView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Scripts", systemImage: "terminal")
                }
                .tag(2)
        }
        .padding()
    }
}
