import SwiftUI

struct ScriptEditorView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var scriptActions: [MenuAction] {
        viewModel.config.enabledActions.filter { $0.type == .customScript }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scriptActions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No custom scripts configured")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add a \"Run Script\" action from the Menu Items tab first.")
                        .foregroundColor(.secondary)

                    Button("Add Script Action") {
                        viewModel.addAction(type: .customScript)
                    }
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Custom Scripts")
                    .font(.headline)

                List {
                    ForEach(scriptActions) { action in
                        ScriptRow(action: action)
                            .environmentObject(viewModel)
                    }
                }
            }
        }
        .padding()
    }
}

struct ScriptRow: View {
    let action: MenuAction
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var scriptContent: String

    init(action: MenuAction) {
        self.action = action
        _scriptContent = State(initialValue: action.scriptContent ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(action.title)
                    .font(.headline)
                Spacer()
                Text("Script")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            TextEditor(text: $scriptContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .border(.secondary.opacity(0.3))
                .onChange(of: scriptContent) { _, newValue in viewModel.updateScript(for: action, content: newValue) }

            Text("Script runs in Terminal at the selected directory. Use cautiously.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
