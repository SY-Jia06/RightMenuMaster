import SwiftUI

struct TemplateListView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var selectedTemplate: FileTemplate?
    @State private var showAddSheet = false

    var allTemplates: [FileTemplate] {
        viewModel.config.allTemplates()
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("File Templates")
                    .font(.headline)

                List(selection: $selectedTemplate) {
                    Section("Built-in") {
                        ForEach(allTemplates.filter { $0.isBuiltIn }) { template in
                            TemplateRow(template: template)
                        }
                    }
                    Section("Custom") {
                        ForEach(allTemplates.filter { !$0.isBuiltIn }) { template in
                            TemplateRow(template: template)
                        }
                    }
                }

                HStack {
                    Button(action: { showAddSheet = true }) {
                        Label("Add Template", systemImage: "plus")
                    }
                    Button(action: {
                        if let template = selectedTemplate, !template.isBuiltIn {
                            viewModel.removeTemplate(template)
                        }
                    }) {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(selectedTemplate == nil || selectedTemplate?.isBuiltIn == true)
                }
                .padding(.top, 4)
            }
            .frame(minWidth: 280)

            // Right: Template Editor
            if let template = selectedTemplate {
                TemplateEditorView(template: template)
                    .environmentObject(viewModel)
                    .frame(minWidth: 300)
            } else {
                VStack {
                    Spacer()
                    Text("Select a template to edit")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(minWidth: 300)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTemplateView { name, ext in
                let template = FileTemplate(name: name, ext: ext, content: "", isBuiltIn: false)
                viewModel.addTemplate(template)
            }
        }
    }
}

struct TemplateRow: View {
    let template: FileTemplate

    var body: some View {
        HStack {
            Image(systemName: template.isBuiltIn ? "lock.doc" : "doc")
                .foregroundColor(template.isBuiltIn ? .secondary : .accentColor)
            Text(template.displayName)
        }
        .padding(.vertical, 2)
    }
}

struct TemplateEditorView: View {
    let template: FileTemplate
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var content: String
    @State private var templateName: String
    @State private var fileExt: String

    init(template: FileTemplate) {
        self.template = template
        _content = State(initialValue: template.content)
        _templateName = State(initialValue: template.name)
        _fileExt = State(initialValue: template.ext)
    }

    var body: some View {
        Form {
            Section("Template Info") {
                if template.isBuiltIn {
                    Text("Built-in template (cannot rename)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                TextField("Name", text: $templateName)
                    .disabled(template.isBuiltIn)
                    .onChange(of: templateName) { _, newValue in
                        var updated = template
                        updated.name = newValue
                        viewModel.updateTemplate(updated)
                    }

                TextField("Extension", text: $fileExt)
                    .disabled(template.isBuiltIn)
                    .onChange(of: fileExt) { _, newValue in
                        var updated = template
                        updated.ext = newValue
                        viewModel.updateTemplate(updated)
                    }
            }

            Section("Content") {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .onChange(of: content) { _, newValue in
                        var updated = template
                        updated.content = newValue
                        viewModel.updateTemplate(updated)
                    }
            }
        }
        .formStyle(.grouped)
    }
}

struct AddTemplateView: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ext = "txt"

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Template")
                .font(.headline)

            TextField("Template Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Extension:")
                TextField("ext", text: $ext)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Button("Add") {
                    guard !name.isEmpty, !ext.isEmpty else { return }
                    onAdd(name, ext.replacingOccurrences(of: ".", with: ""))
                    dismiss()
                }
                .disabled(name.isEmpty || ext.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300, height: 180)
    }
}
