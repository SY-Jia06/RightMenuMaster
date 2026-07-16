import SwiftUI

final class NewFileSession: Identifiable {
  let id = UUID()
  let directory: URL
  let recipe: FileRecipe

  init(directory: URL, recipe: FileRecipe) {
    self.directory = directory
    self.recipe = recipe
  }
}

struct NewFilePanel: View {
  @ObservedObject var coordinator: AppCoordinator
  let session: NewFileSession

  @State private var filename = "Untitled"
  @State private var recipe: FileRecipe
  @State private var openInEditor: Bool
  @State private var validationMessage: String?
  @State private var suggestedFilename: String?
  @State private var createdURL: URL?
  @State private var isWorking = false
  @FocusState private var filenameFocused: Bool

  init(coordinator: AppCoordinator, session: NewFileSession) {
    self.coordinator = coordinator
    self.session = session
    _recipe = State(initialValue: session.recipe)
    _openInEditor = State(
      initialValue: coordinator.config.postCreateBehavior == .openPreferredEditor)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 10) {
        Image(systemName: "doc.badge.plus")
          .font(.title2)
          .foregroundStyle(.tint)
        Text(V2Presentation.text("New File", "新建文件", language: coordinator.language))
          .font(.title2.weight(.semibold))
      }

      LabeledContent(
        V2Presentation.text("Working Directory", "工作目录", language: coordinator.language)
      ) {
        Text(session.directory.path)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
          .accessibilityLabel(session.directory.path)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(V2Presentation.text("Filename", "文件名", language: coordinator.language))
          .font(.headline)
        TextField(
          V2Presentation.text("Filename", "文件名", language: coordinator.language), text: $filename
        )
        .textFieldStyle(.roundedBorder)
        .focused($filenameFocused)
        .onSubmit { submit() }
        .onChange(of: filename) { validateInput() }
        .disabled(createdURL != nil || isWorking)

        if let validationMessage {
          Text(validationMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        } else if let finalName {
          Text(
            V2Presentation.text(
              "Creates \(finalName)", "将创建 \(finalName)", language: coordinator.language)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if let suggestedFilename {
          Button(
            V2Presentation.text(
              "Use \(suggestedFilename)", "使用 \(suggestedFilename)", language: coordinator.language)
          ) {
            filename = suggestedFilename
            self.suggestedFilename = nil
            validateInput()
          }
          .buttonStyle(.link)
        }
      }

      Picker(
        V2Presentation.text("File Recipe", "文件配方", language: coordinator.language),
        selection: $recipe
      ) {
        ForEach(FileRecipe.allCases) { recipe in
          Text(recipe.title(language: coordinator.language)).tag(recipe)
        }
      }
      .pickerStyle(.segmented)
      .onChange(of: recipe) { validateInput() }
      .disabled(createdURL != nil || isWorking)

      Toggle(isOn: $openInEditor) {
        Text(openWithEditorTitle)
      }
      .disabled(coordinator.config.preferredEditor == nil || createdURL != nil || isWorking)

      HStack {
        Button(V2Presentation.text("Cancel", "取消", language: coordinator.language)) {
          coordinator.dismissNewFile()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        Button(primaryButtonTitle) { submit() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled((validationMessage != nil && createdURL == nil) || isWorking)
      }
    }
    .padding(24)
    .frame(width: 500)
    .onAppear {
      validateInput()
      filenameFocused = true
    }
  }

  private var finalName: String? {
    try? SafeFilenameParser.parse(filename, recipe: recipe).fileName
  }

  private var openWithEditorTitle: String {
    let editor =
      coordinator.config.preferredEditor?.displayName
      ?? V2Presentation.text("preferred editor", "首选编辑器", language: coordinator.language)
    return V2Presentation.text(
      "Open with \(editor) after creating",
      "创建后用 \(editor) 打开",
      language: coordinator.language
    )
  }

  private var primaryButtonTitle: String {
    if createdURL != nil {
      return V2Presentation.text("Retry Open", "重试打开", language: coordinator.language)
    }
    return V2Presentation.text("Create", "创建", language: coordinator.language)
  }

  private func validateInput() {
    do {
      _ = try SafeFilenameParser.parse(filename, recipe: recipe)
      validationMessage = nil
    } catch {
      validationMessage = V2Presentation.errorMessage(error, language: coordinator.language)
    }
  }

  private func submit() {
    guard !isWorking else { return }
    Task { await createOrRetryOpen() }
  }

  @MainActor
  private func createOrRetryOpen() async {
    isWorking = true
    defer { isWorking = false }

    do {
      let fileURL: URL
      if let createdURL {
        fileURL = createdURL
      } else {
        let created = try await coordinator.createFile(
          filename: filename,
          recipe: recipe,
          in: session.directory
        )
        fileURL = created.url
        createdURL = fileURL
      }

      try await coordinator.performPostCreate(
        for: fileURL,
        openInPreferredEditor: openInEditor
      )
      coordinator.dismissNewFile()
    } catch let error as FileCreationError {
      if case .collision(_, let suggestion) = error {
        suggestedFilename = suggestion
      }
      validationMessage = V2Presentation.errorMessage(error, language: coordinator.language)
    } catch let error as CocoaError where error.code == .userCancelled {
      return
    } catch {
      // createdURL remains set after a launch failure. Retry only opens the
      // existing file and can never perform creation a second time.
      validationMessage = V2Presentation.errorMessage(error, language: coordinator.language)
    }
  }
}
