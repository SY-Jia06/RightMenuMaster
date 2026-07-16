import AppKit
import SwiftUI

/// Main app surface. AppDelegate owns external URL delivery so requests are
/// consumed exactly once even though this view is hosted in a manual NSWindow.
struct RootView: View {
  @StateObject private var coordinator: AppCoordinator

  @MainActor
  init(coordinator: AppCoordinator? = nil) {
    _coordinator = StateObject(wrappedValue: coordinator ?? AppCoordinator())
  }

  var body: some View {
    Group {
      switch coordinator.rootDestination {
      case .onboarding:
        OnboardingView(coordinator: coordinator)
      case .settings:
        SettingsView(coordinator: coordinator)
          .frame(minWidth: 720, minHeight: 520)
      }
    }
    .alert(
      V2Presentation.text(
        "Right Click Master", "Right Click Master", language: coordinator.language),
      isPresented: Binding(
        get: { coordinator.errorMessage != nil },
        set: { if !$0 { coordinator.clearError() } }
      )
    ) {
      Button(V2Presentation.text("OK", "好", language: coordinator.language)) {
        coordinator.clearError()
      }
    } message: {
      Text(coordinator.errorMessage ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      coordinator.applicationDidBecomeActive()
    }
  }
}
