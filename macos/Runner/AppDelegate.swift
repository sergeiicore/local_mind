import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate, NSMenuDelegate {
  static let statusItemName = "LocalMind.StatusItem"
  private(set) var statusItem: NSStatusItem!
  private var statusMenu: NSMenu!
  private var launchAtLoginItem: NSMenuItem!

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // FlutterAppDelegate does not implement this optional NSApplicationDelegate
    // callback. Calling super raises an Objective-C exception before tray setup.
    configureStatusItem()
    mainFlutterWindow?.orderOut(nil)
  }

  private var localMindWindow: MainFlutterWindow? {
    mainFlutterWindow as? MainFlutterWindow
  }

  private func configureStatusItem() {
    Self.prepareStatusItemPosition(in: .standard)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.autosaveName = Self.statusItemName
    statusItem.isVisible = true
    guard let button = statusItem.button else { return }
    if let image = NSImage(
      systemSymbolName: "brain.head.profile",
      accessibilityDescription: "Local Mind"
    ) {
      image.size = NSSize(width: 18, height: 18)
      image.isTemplate = true
      button.image = image
      button.imagePosition = .imageOnly
      button.title = ""
    } else {
      // Keep the status item usable on a system where the SF Symbol is absent.
      button.title = "LM"
      button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    }
    button.setAccessibilityLabel("Local Mind")
    button.toolTip = "Local Mind"
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    statusMenu = NSMenu()
    statusMenu.delegate = self
    let capture = statusMenu.addItem(withTitle: "Открыть чат    ⌃⌥Space", action: #selector(showCapture), keyEquivalent: "")
    capture.target = self
    let voice = statusMenu.addItem(withTitle: "Продиктовать    ⌃⌥⇧Space", action: #selector(showVoice), keyEquivalent: "")
    voice.target = self
    statusMenu.addItem(NSMenuItem.separator())
    launchAtLoginItem = statusMenu.addItem(withTitle: "Запускать при входе в Mac", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLoginItem.target = self
    let settings = statusMenu.addItem(withTitle: "Настройки", action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    statusMenu.addItem(NSMenuItem.separator())
    let quit = statusMenu.addItem(withTitle: "Завершить Local Mind", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    refreshLaunchAtLoginMenuItem()
  }

  static func prepareStatusItemPosition(in defaults: UserDefaults) {
    // New unnamed items land at the far left, where the MacBook notch or a
    // menu-bar manager can hide them even while isVisible reports true.
    // Seed a right-side position once, then preserve the user's arrangement.
    let key = "NSStatusItem Preferred Position \(statusItemName)"
    if defaults.object(forKey: key) == nil {
      defaults.set(0, forKey: key)
    }
  }

  func disableFallbackStatusItem() {
    guard let statusItem else { return }
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
  }

  @objc private func statusItemClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem.button {
      statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    } else {
      localMindWindow?.toggleCapturePanel()
    }
  }

  @objc private func showCapture() { localMindWindow?.openCapturePanel() }
  @objc private func showVoice() { localMindWindow?.openVoicePanel() }
  @objc private func showSettings() { localMindWindow?.openSettingsPanel() }

  @objc private func toggleLaunchAtLogin() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
      refreshLaunchAtLoginMenuItem()
    } catch {
      let alert = NSAlert(error: error)
      alert.messageText = "Не удалось изменить автозапуск"
      alert.informativeText = "Переместите Local Mind в папку «Программы» и повторите попытку."
      alert.runModal()
    }
  }

  private func refreshLaunchAtLoginMenuItem() {
    launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshLaunchAtLoginMenuItem()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    localMindWindow?.openCapturePanel()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
