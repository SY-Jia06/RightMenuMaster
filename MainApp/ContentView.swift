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

            PermissionView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Permissions", systemImage: "lock.open")
                }
                .tag(3)
        }
        .padding()
    }
}

struct PermissionView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var selectedFolder: AuthorizedFolderGrant.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Authorized Folders")
                    .font(.headline)

                Spacer()
                
                Button(action: viewModel.authorizeCommonFolders) {
                    Label("Quick Setup", systemImage: "bolt")
                }

                Button(action: viewModel.authorizeHomeFolder) {
                    Label("Enable Everywhere", systemImage: "house")
                }

                Button(action: viewModel.addAuthorizedFolder) {
                    Label("Authorize Folder", systemImage: "folder.badge.plus")
                }
            }

            Text("Quick Setup authorizes common folders (工作区, Documents, Desktop, Downloads). Enable Everywhere asks for your home folder once. Authorized folders also become Finder monitored roots for the right-click menu.")
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: viewModel.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(viewModel.accessibilityTrusted ? .green : .orange)

                Text(viewModel.accessibilityTrusted ? "Rename permission enabled" : "Rename permission needed")
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: viewModel.requestAccessibilityPermission) {
                    Label("Enable Rename", systemImage: "keyboard")
                }

                Button(action: viewModel.refreshAccessibilityPermission) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            List(selection: $selectedFolder) {
                ForEach(viewModel.authorizedFolders) { folder in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(folder.displayName)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(folder.id)
                }
            }
            .frame(minHeight: 240)

            HStack {
                Button(role: .destructive) {
                    guard let selectedFolder,
                          let folder = viewModel.authorizedFolders.first(where: { $0.id == selectedFolder }) else { return }
                    viewModel.removeAuthorizedFolder(folder)
                    self.selectedFolder = nil
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .disabled(selectedFolder == nil)

                Spacer()
            }

            if let message = viewModel.permissionErrorMessage {
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}
