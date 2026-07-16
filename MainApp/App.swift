import AppKit
import Combine
import OSLog
import SwiftUI

private let appLifecycleLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "io.github.syjia06.rightclickmaster",
  category: "Lifecycle"
)

@main
struct RightClickMasterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          appDelegate.showMainWindow(force: true)
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let coordinator = AppCoordinator()
  private var mainWindowController: NSWindowController?
  private var newFileWindowController: NSWindowController?
  private var subscriptions: Set<AnyCancellable> = []
  private var receivedExternalCommand = false
  private var finishedLaunching = false
  private var suppressMainWindowForExternalLaunch = false

  override init() {
    super.init()

    coordinator.$newFileSession
      .dropFirst()
      .sink { [weak self] session in
        guard let self else { return }
        if let session {
          self.showNewFileWindow(session: session)
        } else {
          self.closeNewFileWindow()
          self.terminateIfExternalCommandFinished()
        }
      }
      .store(in: &subscriptions)

    coordinator.$errorMessage
      .dropFirst()
      .compactMap { $0 }
      .sink { [weak self] _ in
        self?.showMainWindow(force: true)
      }
      .store(in: &subscriptions)
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(handleFinderCommandReady(_:)),
      name: Notification.Name(Constants.v2FinderCommandReadyNotificationName),
      object: nil
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !isRunningUnitTests else { return }
    if coordinator.hasPendingExternalRequests() {
      receivedExternalCommand = true
      suppressMainWindowForExternalLaunch = true
    }
    if coordinator.consumePendingExternalRequests() > 0 {
      if let session = coordinator.newFileSession {
        showNewFileWindow(session: session)
      } else {
        scheduleAutomaticTermination()
      }
    }
    finishedLaunching = true
    // URL activation is delivered during launch. A short deferral prevents
    // an unnecessary settings-window flash for terminal/editor actions.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self, !self.receivedExternalCommand else { return }
      self.showMainWindow()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSAppleEventManager.shared().removeEventHandler(
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
    DistributedNotificationCenter.default().removeObserver(
      self,
      name: Notification.Name(Constants.v2FinderCommandReadyNotificationName),
      object: nil
    )
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !suppressMainWindowForExternalLaunch else { return false }
    showMainWindow()
    return true
  }

  func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }

  func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if window === newFileWindowController?.window {
      newFileWindowController = nil
      if coordinator.newFileSession != nil {
        coordinator.dismissNewFile()
      }
    } else if window === mainWindowController?.window {
      mainWindowController = nil
    }
  }

  func showMainWindow(force: Bool = false) {
    if force { suppressMainWindowForExternalLaunch = false }
    guard !suppressMainWindowForExternalLaunch else { return }
    if let window = mainWindowController?.window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let rootView = RootView(coordinator: coordinator)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Right Click Master"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 760, height: 560))
    window.minSize = NSSize(width: 560, height: 440)
    window.center()
    window.setFrameAutosaveName("RightClickMaster.MainWindow")
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.isRestorable = false

    let controller = NSWindowController(window: window)
    mainWindowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    receivedExternalCommand = true
    if !finishedLaunching { suppressMainWindowForExternalLaunch = true }
    appLifecycleLog.notice("Received Finder command URL")
    guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: value),
      coordinator.consumeExternalURL(url)
    else {
      coordinator.reportError(
        V2Presentation.text(
          "The Finder request URL is invalid.",
          "Finder 请求链接无效。",
          language: coordinator.language
        )
      )
      return
    }

    if let session = coordinator.newFileSession {
      showNewFileWindow(session: session)
    } else {
      scheduleAutomaticTermination()
    }
  }

  @objc private func handleFinderCommandReady(_ notification: Notification) {
    guard let value = notification.object as? String,
      let requestID = UUID(uuidString: value)
    else {
      return
    }
    receivedExternalCommand = true
    if !finishedLaunching { suppressMainWindowForExternalLaunch = true }
    appLifecycleLog.notice(
      "Received Finder command notification \(requestID.uuidString, privacy: .public)"
    )
    _ = coordinator.consumeExternalRequest(id: requestID)
    if let session = coordinator.newFileSession {
      showNewFileWindow(session: session)
    } else {
      scheduleAutomaticTermination()
    }
  }

  private func showNewFileWindow(session: NewFileSession) {
    appLifecycleLog.notice("Showing New File panel")
    if let window = newFileWindowController?.window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let view = NewFilePanel(coordinator: coordinator, session: session)
    let hostingController = NSHostingController(rootView: view)
    let panel = NSPanel(contentViewController: hostingController)
    panel.title = V2Presentation.text(
      "New File",
      "新建文件",
      language: coordinator.language
    )
    panel.styleMask = [.titled, .closable]
    panel.setContentSize(NSSize(width: 500, height: 370))
    panel.center()
    panel.delegate = self
    panel.isReleasedWhenClosed = false

    let controller = NSWindowController(window: panel)
    newFileWindowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func closeNewFileWindow() {
    guard let controller = newFileWindowController else { return }
    newFileWindowController = nil
    controller.window?.delegate = nil
    controller.close()
  }

  private func scheduleAutomaticTermination() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      self?.terminateIfExternalCommandFinished()
    }
  }

  private func terminateIfExternalCommandFinished() {
    guard receivedExternalCommand,
      mainWindowController?.window?.isVisible != true,
      newFileWindowController?.window?.isVisible != true,
      coordinator.errorMessage == nil
    else {
      return
    }
    NSApp.terminate(nil)
  }

  private var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }
}
