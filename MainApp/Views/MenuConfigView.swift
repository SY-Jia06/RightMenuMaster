import SwiftUI

struct MenuConfigView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var selectedAction: MenuAction?
    @State private var showAddSheet = false
    @State private var editingTitle: UUID?

    var body: some View {
        HSplitView {
            // Left: Action List
            VStack(alignment: .leading) {
                Text("Right-Click Menu Items")
                    .font(.headline)

                List(selection: $selectedAction) {
                    ForEach(viewModel.config.enabledActions) { action in
                        HStack {
                            Image(systemName: action.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(action.isEnabled ? .green : .secondary)
                                .onTapGesture { viewModel.toggleAction(action) }

                            if editingTitle == action.id {
                                TextField("Title", text: Binding(
                                    get: { action.title },
                                    set: { viewModel.updateActionTitle(action, title: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { editingTitle = nil }
                            } else {
                                Text(action.title)
                                    .onTapGesture(count: 2) { editingTitle = action.id }
                            }

                            Spacer()

                            Text(action.type.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: viewModel.moveAction)
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.removeAction(viewModel.config.enabledActions[index])
                        }
                    }
                }

                HStack {
                    Button(action: { showAddSheet = true }) {
                        Label("Add Action", systemImage: "plus")
                    }
                    Button(action: {
                        if let action = selectedAction {
                            viewModel.removeAction(action)
                        }
                    }) {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(selectedAction == nil || viewModel.config.enabledActions.count <= 1)
                }
                .padding(.top, 4)
            }
            .frame(minWidth: 300)

            // Right: Action Detail
            if let action = selectedAction {
                ActionDetailView(action: action)
                    .environmentObject(viewModel)
                    .frame(minWidth: 280)
            } else {
                VStack {
                    Spacer()
                    Text("Select a menu item to configure")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(minWidth: 280)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddActionView { actionType in
                viewModel.addAction(type: actionType)
            }
        }
    }
}

struct ActionDetailView: View {
    let action: MenuAction
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var title: String
    @State private var script: String

    init(action: MenuAction) {
        self.action = action
        _title = State(initialValue: action.title)
        _script = State(initialValue: action.scriptContent ?? "")
    }

    var body: some View {
        Form {
            Section("Action Info") {
                TextField("Title", text: $title)
                    .onChange(of: title) { viewModel.updateActionTitle(action, title: $0) }

                LabeledContent("Type", value: action.type.rawValue)

                Toggle("Enabled", isOn: Binding(
                    get: { action.isEnabled },
                    set: { _ in viewModel.toggleAction(action) }
                ))
            }

            if action.type == .customScript {
                Section("Script Content") {
                    TextEditor(text: $script)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .onChange(of: script) { viewModel.updateScript(for: action, content: $0) }
                }
            }

            if action.type == .moveTo {
                Section("Move-To Folders") {
                    FolderListEditor(
                        folders: viewModel.config.moveToFolders,
                        onAdd: { viewModel.addMoveToFolder($0) },
                        onRemove: { viewModel.removeMoveToFolder($0) }
                    )
                }
            }

            if action.type == .copyTo {
                Section("Copy-To Folders") {
                    FolderListEditor(
                        folders: viewModel.config.copyToFolders,
                        onAdd: { viewModel.addCopyToFolder($0) },
                        onRemove: { viewModel.removeCopyToFolder($0) }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FolderListEditor: View {
    let folders: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    @State private var showOpenPanel = false

    var body: some View {
        List {
            ForEach(folders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder")
                    Text(URL(fileURLWithPath: folder).lastPathComponent)
                    Spacer()
                    Text(folder)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .onDelete { indexSet in
                for index in indexSet { onRemove(folders[index]) }
            }
        }
        .frame(minHeight: 80)

        Button("Add Folder...") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                onAdd(url.path)
            }
        }
    }
}

struct AddActionView: View {
    let onSelect: (ActionType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Menu Action")
                .font(.headline)

            List(ActionType.allCases, id: \.self) { type in
                Button(action: {
                    onSelect(type)
                    dismiss()
                }) {
                    HStack {
                        Text(type.defaultTitle)
                        Spacer()
                        Text(type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 350, height: 400)
    }
}
