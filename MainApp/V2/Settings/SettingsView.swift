import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var coordinator: AppCoordinator

  var body: some View {
    NavigationSplitView {
      List(SettingsDestination.allCases, selection: $coordinator.settingsDestination) {
        destination in
        Label(
          destination.title(language: coordinator.language), systemImage: destination.systemImage
        )
        .tag(destination)
      }
      .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
      .safeAreaInset(edge: .bottom) {
        Text("Right Click Master")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(12)
      }
    } detail: {
      Group {
        switch coordinator.settingsDestination {
        case .actions:
          ActionsSettingsView(coordinator: coordinator)
        case .applications:
          ApplicationsSettingsView(
            coordinator: coordinator,
            catalog: coordinator.applicationCatalog
          )
        case .system:
          SystemSettingsView(
            coordinator: coordinator,
            health: coordinator.integrationHealth,
            grants: coordinator.folderGrants
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .navigationSplitViewStyle(.balanced)
  }
}

private struct ActionsSettingsView: View {
  @ObservedObject var coordinator: AppCoordinator

  var body: some View {
    Form {
      Section {
        List {
          ForEach(coordinator.config.actionOrder) { action in
            HStack(spacing: 10) {
              Toggle(isOn: actionBinding(action)) {
                Label {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(action.title(language: coordinator.language))
                    Text(action.detail(language: coordinator.language))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                } icon: {
                  Image(systemName: action.systemImage)
                    .frame(width: 22)
                }
              }
              .toggleStyle(.switch)

              ControlGroup {
                Button {
                  coordinator.moveAction(action, by: -1)
                } label: {
                  Image(systemName: "chevron.up")
                }
                .disabled(coordinator.config.actionOrder.first == action)
                .accessibilityLabel(
                  V2Presentation.text("Move up", "上移", language: coordinator.language)
                )

                Button {
                  coordinator.moveAction(action, by: 1)
                } label: {
                  Image(systemName: "chevron.down")
                }
                .disabled(coordinator.config.actionOrder.last == action)
                .accessibilityLabel(
                  V2Presentation.text("Move down", "下移", language: coordinator.language)
                )
              }
              .controlSize(.small)
            }
            .padding(.vertical, 4)
          }
          .onMove(perform: coordinator.moveAction)
        }
        .frame(minHeight: 228)
      } header: {
        Text(V2Presentation.text("Context menu", "右键菜单", language: coordinator.language))
      } footer: {
        Text(
          V2Presentation.text(
            "Drag or use the arrow buttons to reorder. Changes are saved immediately.",
            "拖动或使用箭头按钮排序，修改会立即保存。",
            language: coordinator.language
          ))
      }

      Section(V2Presentation.text("New File defaults", "新建文件默认设置", language: coordinator.language))
      {
        Picker(
          V2Presentation.text("File recipe", "文件配方", language: coordinator.language),
          selection: configBinding(\.defaultRecipe)
        ) {
          ForEach(FileRecipe.allCases) { recipe in
            Text(recipe.title(language: coordinator.language)).tag(recipe)
          }
        }

        Picker(
          V2Presentation.text("After creating", "创建后", language: coordinator.language),
          selection: configBinding(\.postCreateBehavior)
        ) {
          ForEach(PostCreateBehavior.allCases) { behavior in
            Text(behavior.title(language: coordinator.language)).tag(behavior)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(SettingsDestination.actions.title(language: coordinator.language))
  }

  private func actionBinding(_ action: ProductAction) -> Binding<Bool> {
    Binding(
      get: { coordinator.config.enabledActions.contains(action) },
      set: { coordinator.setAction(action, enabled: $0) }
    )
  }

  private func configBinding<Value>(_ keyPath: WritableKeyPath<V2Config, Value>) -> Binding<Value> {
    Binding(
      get: { coordinator.config[keyPath: keyPath] },
      set: { value in coordinator.updateConfig { $0[keyPath: keyPath] = value } }
    )
  }
}

private struct ApplicationsSettingsView: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var catalog: ApplicationCatalog

  var body: some View {
    Form {
      applicationSection(
        role: .terminal,
        title: V2Presentation.text("Preferred terminal", "首选终端", language: coordinator.language),
        detail: V2Presentation.text(
          "Used by Open in Terminal. Your system default is not changed.",
          "用于“在终端中打开”，不会修改系统默认应用。",
          language: coordinator.language
        )
      )

      applicationSection(
        role: .editor,
        title: V2Presentation.text("Preferred editor", "首选编辑器", language: coordinator.language),
        detail: V2Presentation.text(
          "Used by Open with Editor and optional post-create opening.",
          "用于“用编辑器打开”和创建文件后的可选打开操作。",
          language: coordinator.language
        )
      )

      Section {
        Button {
          catalog.refresh(
            including: coordinator.config.preferredTerminal,
            preferredEditor: coordinator.config.preferredEditor
          )
        } label: {
          Label(
            V2Presentation.text("Detect Again", "重新检测", language: coordinator.language),
            systemImage: "arrow.clockwise")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(SettingsDestination.applications.title(language: coordinator.language))
  }

  @ViewBuilder
  private func applicationSection(role: ApplicationRole, title: String, detail: String) -> some View
  {
    Section {
      Picker(title, selection: selectedApplicationID(role)) {
        Text(V2Presentation.text("Not selected", "未选择", language: coordinator.language))
          .tag(String?.none)
        ForEach(catalog.applications(for: role), id: \.id) { application in
          Text(application.displayName).tag(Optional(application.id))
        }
      }

      Button {
        Task { await coordinator.chooseApplication(for: role) }
      } label: {
        Label(
          V2Presentation.text("Choose Application…", "选择应用…", language: coordinator.language),
          systemImage: "folder")
      }

      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
    } header: {
      Text(title)
    }
  }

  private func selectedApplicationID(_ role: ApplicationRole) -> Binding<String?> {
    Binding(
      get: {
        switch role {
        case .terminal: coordinator.config.preferredTerminal?.id
        case .editor: coordinator.config.preferredEditor?.id
        }
      },
      set: { id in
        let application = catalog.applications(for: role).first { $0.id == id }
        coordinator.setPreferredApplication(application, for: role)
      }
    )
  }
}

private struct SystemSettingsView: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var health: IntegrationHealthService
  @ObservedObject var grants: SecurityScopedFolderGrantStore

  var body: some View {
    Form {
      Section(V2Presentation.text("Integration Health", "集成健康状态", language: coordinator.language)) {
        ForEach(health.snapshot.checks) { check in
          HealthCheckRow(check: check, language: coordinator.language)
        }

        HStack {
          Button {
            health.showExtensionManagement()
          } label: {
            Label(
              V2Presentation.text("Manage Extension…", "管理扩展…", language: coordinator.language),
              systemImage: "puzzlepiece.extension")
          }

          Button {
            health.runVerification()
          } label: {
            Label(
              V2Presentation.text("Run Checks", "运行检查", language: coordinator.language),
              systemImage: "checkmark.circle")
          }
        }
      }

      Section {
        ForEach(grants.grants) { grant in
          HStack {
            Image(systemName: "folder.fill")
              .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(grant.displayName)
              Text(grant.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(grant.path)
            }
            Spacer()
            Button(role: .destructive) {
              coordinator.revokeFolder(grant)
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(V2Presentation.text("Remove access", "移除权限", language: coordinator.language))
            .accessibilityLabel(
              V2Presentation.text("Remove access", "移除权限", language: coordinator.language)
            )
          }
        }

        Button {
          Task { await coordinator.authorizeFolder() }
        } label: {
          Label(
            V2Presentation.text("Allow Folder…", "授权文件夹…", language: coordinator.language),
            systemImage: "folder.badge.plus")
        }
      } header: {
        Text(
          V2Presentation.text(
            "Folders allowed for New File", "允许新建文件的文件夹", language: coordinator.language))
      } footer: {
        Text(
          V2Presentation.text(
            "Only folders you choose receive persistent write access.",
            "只有你选择的文件夹会获得持久写入权限。",
            language: coordinator.language
          ))
      }

      Section(V2Presentation.text("Preferences", "偏好设置", language: coordinator.language)) {
        Picker(
          V2Presentation.text("Language", "语言", language: coordinator.language),
          selection: languageBinding
        ) {
          ForEach(V2Language.allCases) { language in
            Text(languageTitle(language)).tag(language)
          }
        }
      }

      Section(V2Presentation.text("Privacy & Support", "隐私与支持", language: coordinator.language)) {
        Label(
          V2Presentation.text(
            "No account, telemetry, or path upload", "无账户、遥测或路径上传", language: coordinator.language),
          systemImage: "hand.raised.fill"
        )

        Button(action: copyDiagnostics) {
          Label(
            V2Presentation.text(
              "Copy Redacted Diagnostics", "复制脱敏诊断信息", language: coordinator.language),
            systemImage: "doc.on.doc")
        }

        Link(
          destination: URL(string: "https://github.com/SY-Jia06/RightMenuMaster")!
        ) {
          Label("GitHub", systemImage: "link")
        }

        LabeledContent(V2Presentation.text("Version", "版本", language: coordinator.language)) {
          Text(versionString)
            .foregroundStyle(.secondary)
        }

        Button(V2Presentation.text("Run Setup Again", "重新运行设置", language: coordinator.language)) {
          coordinator.restartOnboarding()
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(SettingsDestination.system.title(language: coordinator.language))
  }

  private var languageBinding: Binding<V2Language> {
    Binding(
      get: { coordinator.config.language },
      set: { language in coordinator.updateConfig { $0.language = language } }
    )
  }

  private func languageTitle(_ language: V2Language) -> String {
    if language == .system {
      return V2Presentation.text("System", "跟随系统", language: coordinator.language)
    }
    return language.title
  }

  private var versionString: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return build.map { "\(version) (\($0))" } ?? version
  }

  private func copyDiagnostics() {
    let extensionState = health.isExtensionEnabled ? "enabled" : "disabled"
    let text = """
      Right Click Master \(versionString)
      macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
      Finder extension: \(extensionState)
      Folder grants: \(grants.grants.count)
      Detected terminals: \(coordinator.applicationCatalog.terminals.count)
      Detected editors: \(coordinator.applicationCatalog.editors.count)
      """
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

struct HealthCheckRow: View {
  let check: IntegrationCheck
  let language: V2Language

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: check.systemImage)
        .foregroundStyle(statusColor)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(localizedTitle)
        Text(localizedDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var localizedTitle: String {
    switch check.id {
    case "extension":
      V2Presentation.text("Finder integration", "Finder 集成", language: language)
    case "handoff":
      V2Presentation.text("Shared handoff storage", "共享交接存储", language: language)
    case "heartbeat":
      V2Presentation.text("Finder handshake", "Finder 握手", language: language)
    case "creation":
      V2Presentation.text("Safe file creation", "安全文件创建", language: language)
    default:
      check.title
    }
  }

  private var localizedDetail: String {
    switch (check.id, check.level) {
    case ("extension", .checking):
      V2Presentation.text("Checking extension state…", "正在检查扩展状态…", language: language)
    case ("extension", .healthy):
      V2Presentation.text("Finder extension is enabled.", "Finder 扩展已启用。", language: language)
    case ("extension", _):
      V2Presentation.text(
        "Enable Right Click Master in Login Items & Extensions.",
        "请在“登录项与扩展”中启用 Right Click Master。",
        language: language
      )
    case ("handoff", .healthy):
      V2Presentation.text(
        "Shared request storage passed a write/read/remove cycle.",
        "共享请求存储已通过写入、读取和移除测试。",
        language: language
      )
    case ("handoff", _):
      V2Presentation.text(
        "Shared request storage failed. Check App Group entitlements.",
        "共享请求存储失败，请检查 App Group 权限。",
        language: language
      )
    case ("heartbeat", .healthy):
      V2Presentation.text(
        "Finder extension recently reached shared storage.",
        "Finder 扩展最近已访问共享存储。",
        language: language
      )
    case ("heartbeat", _):
      V2Presentation.text(
        "After enabling, open Finder and right-click once to verify the extension.",
        "启用后，请打开 Finder 并右键一次以验证扩展。",
        language: language
      )
    case ("creation", .healthy):
      V2Presentation.text(
        "Exclusive create/remove cycle passed in app-owned temporary storage.",
        "应用自有临时存储已通过独占创建和移除测试。",
        language: language
      )
    case ("creation", _):
      V2Presentation.text(
        "The app could not complete its temporary create/remove check.",
        "应用无法完成临时创建和移除测试。",
        language: language
      )
    default:
      check.detail
    }
  }

  private var statusColor: Color {
    switch check.level {
    case .checking: .secondary
    case .healthy: .green
    case .attention: .orange
    case .failed: .red
    }
  }
}
