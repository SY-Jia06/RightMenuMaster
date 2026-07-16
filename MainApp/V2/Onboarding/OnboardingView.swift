import SwiftUI

struct OnboardingView: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject private var integrationHealth: IntegrationHealthService
  @ObservedObject private var folderGrants: SecurityScopedFolderGrantStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(coordinator: AppCoordinator) {
    self.coordinator = coordinator
    _integrationHealth = ObservedObject(wrappedValue: coordinator.integrationHealth)
    _folderGrants = ObservedObject(wrappedValue: coordinator.folderGrants)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        ForEach(0..<4, id: \.self) { step in
          Capsule()
            .fill(
              step <= coordinator.onboardingStep ? Color.accentColor : Color.secondary.opacity(0.22)
            )
            .frame(width: step == coordinator.onboardingStep ? 34 : 18, height: 5)
        }
        Spacer()
        Text("\(min(coordinator.onboardingStep + 1, 4)) / 4")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        V2Presentation.text(
          "Setup step \(min(coordinator.onboardingStep + 1, 4)) of 4",
          "设置第 \(min(coordinator.onboardingStep + 1, 4)) 步，共 4 步",
          language: coordinator.language
        )
      )
      .padding(.horizontal, 28)
      .padding(.top, 24)

      Group {
        switch coordinator.onboardingStep {
        case 0:
          WelcomeStep(language: coordinator.language)
        case 1:
          ToolChoiceStep(
            coordinator: coordinator,
            catalog: coordinator.applicationCatalog
          )
        case 2:
          IntegrationStep(
            coordinator: coordinator,
            health: integrationHealth,
            grants: folderGrants
          )
        default:
          VerifyStep(coordinator: coordinator, health: integrationHealth)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 28)
      .padding(.vertical, 20)

      Divider()
      HStack {
        if coordinator.onboardingStep > 0 {
          Button(V2Presentation.text("Back", "返回", language: coordinator.language)) {
            changeStep { coordinator.retreatOnboarding() }
          }
        }
        Spacer()
        Button(nextButtonTitle) {
          changeStep { coordinator.advanceOnboarding() }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canAdvance)
      }
      .padding(20)
    }
    .frame(minWidth: 560, idealWidth: 560, minHeight: 440, idealHeight: 440)
  }

  private var nextButtonTitle: String {
    if coordinator.onboardingStep >= 3 {
      return V2Presentation.text("Finish", "完成", language: coordinator.language)
    }
    return V2Presentation.text("Continue", "继续", language: coordinator.language)
  }

  private func changeStep(_ change: () -> Void) {
    if reduceMotion {
      change()
    } else {
      withAnimation(.easeInOut(duration: 0.14), change)
    }
  }

  private var canAdvance: Bool {
    switch coordinator.onboardingStep {
    case 1:
      coordinator.config.preferredTerminal != nil && coordinator.config.preferredEditor != nil
    case 2:
      integrationHealth.isExtensionEnabled && !folderGrants.grants.isEmpty
    case 3:
      integrationHealth.snapshot.isHealthy
    default:
      true
    }
  }
}

private struct WelcomeStep: View {
  let language: V2Language

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "contextualmenu.and.cursorarrow")
        .font(.system(size: 58, weight: .light))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text("Right Click Master")
        .font(.largeTitle.weight(.semibold))
      Text(
        V2Presentation.text(
          "Four useful Finder actions, right where you expect them.",
          "四个实用 Finder 操作，就在你习惯的位置。",
          language: language
        )
      )
      .font(.title3)
      .multilineTextAlignment(.center)
      .foregroundStyle(.secondary)
      Label(
        V2Presentation.text(
          "Runs locally. No account required.", "完全本地运行，无需账户。", language: language),
        systemImage: "hand.raised.fill"
      )
      .font(.callout.weight(.medium))
      .padding(.top, 4)
    }
    .frame(maxWidth: 430)
  }
}

private struct ToolChoiceStep: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var catalog: ApplicationCatalog

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      stepHeading(
        V2Presentation.text("Choose your tools", "选择你的工具", language: coordinator.language),
        detail: V2Presentation.text(
          "Installed apps are detected locally. These choices never change system defaults.",
          "已安装应用仅在本地检测，这些选择不会改变系统默认设置。",
          language: coordinator.language
        )
      )

      toolRow(
        role: .terminal, icon: "apple.terminal",
        title: V2Presentation.text("Terminal", "终端", language: coordinator.language))
      toolRow(
        role: .editor, icon: "square.and.pencil",
        title: V2Presentation.text("Editor", "编辑器", language: coordinator.language))

      Spacer()
    }
    .onAppear { coordinator.chooseSuggestedToolsIfNeeded() }
  }

  private func toolRow(role: ApplicationRole, icon: String, title: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.headline)
        Picker(title, selection: selectedApplicationID(role)) {
          Text(V2Presentation.text("Choose…", "选择…", language: coordinator.language)).tag(
            String?.none)
          ForEach(catalog.applications(for: role), id: \.id) { application in
            Text(application.displayName).tag(Optional(application.id))
          }
        }
        .labelsHidden()
        .frame(maxWidth: 260)
      }
      Spacer()
      Button(V2Presentation.text("Other…", "其他…", language: coordinator.language)) {
        Task { await coordinator.chooseApplication(for: role) }
      }
    }
    .v2Card()
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
        coordinator.setPreferredApplication(
          catalog.applications(for: role).first { $0.id == id },
          for: role
        )
      }
    )
  }
}

private struct IntegrationStep: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var health: IntegrationHealthService
  @ObservedObject var grants: SecurityScopedFolderGrantStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      stepHeading(
        V2Presentation.text(
          "Enable Finder integration", "启用 Finder 集成", language: coordinator.language),
        detail: V2Presentation.text(
          "Two explicit choices give Finder its menu and New File its folder access.",
          "完成两个明确选择：启用 Finder 菜单，并授权新建文件的目录。",
          language: coordinator.language
        )
      )

      setupRow(
        complete: health.isExtensionEnabled,
        title: V2Presentation.text("Finder extension", "Finder 扩展", language: coordinator.language),
        detail: health.isExtensionEnabled
          ? V2Presentation.text("Enabled", "已启用", language: coordinator.language)
          : V2Presentation.text(
            "Enable it in Login Items & Extensions", "请在“登录项与扩展”中启用", language: coordinator.language
          )
      ) {
        Button(V2Presentation.text("Open Settings…", "打开设置…", language: coordinator.language)) {
          health.showExtensionManagement()
        }
      }

      setupRow(
        complete: !grants.grants.isEmpty,
        title: V2Presentation.text("Working folder", "工作文件夹", language: coordinator.language),
        detail: grants.grants.isEmpty
          ? V2Presentation.text(
            "Choose Home or a specific working folder", "选择主文件夹或具体工作目录",
            language: coordinator.language)
          : V2Presentation.text(
            "\(grants.grants.count) folder(s) allowed", "已授权 \(grants.grants.count) 个文件夹",
            language: coordinator.language)
      ) {
        Button(V2Presentation.text("Choose Folder…", "选择文件夹…", language: coordinator.language)) {
          Task { await coordinator.authorizeFolder() }
        }
      }

      Label(
        V2Presentation.text(
          "No Accessibility, Screen Recording, Full Disk Access, or administrator permission.",
          "不需要辅助功能、屏幕录制、完全磁盘访问或管理员权限。",
          language: coordinator.language
        ),
        systemImage: "checkmark.shield.fill"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.top, 2)

      Spacer()
    }
  }

  private func setupRow<Accessory: View>(
    complete: Bool,
    title: String,
    detail: String,
    @ViewBuilder accessory: () -> Accessory
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
        .font(.title2)
        .foregroundStyle(complete ? Color.green : Color.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      accessory()
    }
    .v2Card()
  }
}

private struct VerifyStep: View {
  @ObservedObject var coordinator: AppCoordinator
  @ObservedObject var health: IntegrationHealthService

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      stepHeading(
        V2Presentation.text("Verify setup", "验证设置", language: coordinator.language),
        detail: V2Presentation.text(
          "Checks use only shared storage and app-owned temporary files.",
          "检查仅使用共享存储和应用自有的临时文件。",
          language: coordinator.language
        )
      )

      VStack(alignment: .leading, spacing: 12) {
        ForEach(health.snapshot.checks) { check in
          HealthCheckRow(check: check, language: coordinator.language)
        }
      }
      .v2Card()

      HStack {
        Button {
          health.runVerification()
        } label: {
          Label(
            V2Presentation.text("Run Again", "重新检查", language: coordinator.language),
            systemImage: "arrow.clockwise")
        }
        Button {
          coordinator.openSafeTestFolder()
        } label: {
          Label(
            V2Presentation.text("Open Test Folder", "打开测试文件夹", language: coordinator.language),
            systemImage: "folder")
        }
        Spacer()
      }

      Spacer()
    }
    .onAppear { health.runVerification() }
  }
}

@ViewBuilder
private func stepHeading(_ title: String, detail: String) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    Text(title).font(.title2.weight(.semibold))
    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}
