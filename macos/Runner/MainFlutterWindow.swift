import Cocoa
import FlutterMacOS
import Carbon
import EventKit
import Speech
import AVFoundation
import Security
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow, NSWindowDelegate, UNUserNotificationCenterDelegate {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  private var bridge: FlutterMethodChannel!
  private var hotkeys: [EventHotKeyRef?] = []
  private var hotkeyHandler: EventHandlerRef?
  private let eventStore = EKEventStore()
  private let audioEngine = AVAudioEngine()
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
  private var hasAudioTap = false
  private var speechStarting = false
  private var speechGeneration = 0
  private var chatHeight: CGFloat = 300

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 430, height: chatHeight))
    self.minSize = NSSize(width: 390, height: 280)
    self.maxSize = NSSize(width: 520, height: 820)
    self.title = "Local Mind"
    self.center()
    self.isReleasedWhenClosed = false
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
    self.delegate = self
    configurePanel()
    bridge = FlutterMethodChannel(name: "local_mind/native", binaryMessenger: flutterViewController.engine.binaryMessenger)
    bridge.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    configureHotkeys()
    UNUserNotificationCenter.current().delegate = self
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
    // Local Mind is a menu-bar utility. It should not steal focus when macOS
    // launches it at login; the panel opens from LM or the global shortcut.
    orderOut(nil)
  }

  private func configurePanel() {
    styleMask = [.borderless, .resizable, .fullSizeContentView]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    isReleasedWhenClosed = false
    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 16
    contentView?.layer?.masksToBounds = true
    positionPanel()
  }

  private func positionPanel() {
    let mouse = NSEvent.mouseLocation
    let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    guard let visible = target?.visibleFrame else { return }
    let size = frame.size
    setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 10))
  }

  private func configureHotkeys() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
      var id = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
      let window = Unmanaged<MainFlutterWindow>.fromOpaque(context).takeUnretainedValue()
      DispatchQueue.main.async { window.capture(voice: id.id == 2, toggles: id.id == 1) }
      return noErr
    }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotkeyHandler)
    for id: UInt32 in [1, 2] {
      var ref: EventHotKeyRef?
      let modifiers = UInt32(controlKey | optionKey | (id == 2 ? shiftKey : 0))
      let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x4C4D494E, id: id), GetApplicationEventTarget(), 0, &ref)
      if status == noErr { hotkeys.append(ref) }
    }
  }

  func toggleCapturePanel() { capture(voice: false, toggles: true) }
  func openCapturePanel() { capture(voice: false) }
  func openVoicePanel() { capture(voice: true) }
  func openSettingsPanel() {
    showPanel(page: 2)
    bridge.invokeMethod("navigate", arguments: 2)
  }
  private func showPanel(page: Int = 0) {
    let availableHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 720
    let targetSize: NSSize
    switch page {
    case -1: targetSize = NSSize(width: 430, height: min(520, availableHeight * 0.5))
    case 1: targetSize = NSSize(width: 430, height: min(540, availableHeight - 24))
    case 2: targetSize = NSSize(width: 430, height: min(640, availableHeight - 24))
    default: targetSize = NSSize(width: 430, height: min(chatHeight, availableHeight * 0.5))
    }
    setContentSize(targetSize)
    positionPanel()
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func wokeUp() { bridge.invokeMethod("wake", arguments: nil) }
  private func capture(voice: Bool, toggles: Bool = false) {
    if toggles && isVisible {
      stopSpeech()
      orderOut(nil)
      return
    }
    showPanel(page: 0)
    bridge.invokeMethod("capture", arguments: voice)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    stopSpeech()
    orderOut(nil)
    return false
  }

  private func fail(_ result: @escaping FlutterResult, _ message: String) {
    result(FlutterError(code: "local_mind", message: message, details: nil))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "dataDirectory":
      let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Local Mind", isDirectory: true)
      result(url.path)
    case "hotkeyStatus": result(hotkeys.count == 2)
    case "codexStatus":
      if let path = codexExecutable() { result(["installed": true, "path": path]) }
      else { result(["installed": false]) }
    case "runCodex": runCodex(args, result: result)
    case "expandWindow":
      let page = args["page"] as? Int ?? 0
      showPanel(page: page)
      result(nil)
    case "resizeChat":
      let messages = args["messages"] as? Int ?? 0
      let hasAction = args["hasAction"] as? Bool ?? false
      resizeChat(messages: messages, hasAction: hasAction)
      result(nil)
    case "showCapture":
      openCapturePanel()
      result(nil)
    case "showVoice":
      openVoicePanel()
      result(nil)
    case "showSettings":
      openSettingsPanel()
      result(nil)
    case "disableFallbackTray":
      (NSApp.delegate as? AppDelegate)?.disableFallbackStatusItem()
      result(nil)
    case "launchAtLoginStatus":
      result(SMAppService.mainApp.status == .enabled)
    case "toggleLaunchAtLogin":
      do {
        if SMAppService.mainApp.status == .enabled {
          try SMAppService.mainApp.unregister()
        } else {
          try SMAppService.mainApp.register()
        }
        result(SMAppService.mainApp.status == .enabled)
      } catch {
        fail(result, "Не удалось изменить автозапуск: \(error.localizedDescription)")
      }
    case "quit":
      NSApp.terminate(nil)
      result(nil)
    case "hideWindow": stopSpeech(); orderOut(nil); result(nil)
    case "chooseDirectory", "chooseMarkdown":
      let panel = NSOpenPanel()
      panel.canChooseDirectories = call.method == "chooseDirectory"
      panel.canChooseFiles = call.method == "chooseMarkdown"
      panel.allowsMultipleSelection = false
      panel.prompt = "Выбрать"
      panel.message = call.method == "chooseDirectory" ? "Выберите vault Obsidian. Local Mind использует только свою подпапку." : "Только этот файл будет приложен к AI-запросу (до 30 КБ)."
      if call.method == "chooseMarkdown" { panel.allowedContentTypes = [.text, .plainText] }
      panel.begin { response in result(response == .OK ? panel.url?.path : nil) }
    case "openPath":
      if let path = args["path"] as? String { NSWorkspace.shared.open(URL(fileURLWithPath: path)); result(nil) }
      else { fail(result, "Нет пути к файлу") }
    case "getSecret":
      guard let key = args["key"] as? String else { fail(result, "Нет имени ключа"); return }
      var query = keychainQuery(key)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var value: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &value)
      if status == errSecItemNotFound { result(nil) }
      else if status == errSecSuccess, let data = value as? Data { result(String(data: data, encoding: .utf8)) }
      else { fail(result, "Keychain: \(status)") }
    case "setSecret":
      guard let key = args["key"] as? String, let value = args["value"] as? String else { fail(result, "Нет данных ключа"); return }
      let query = keychainQuery(key)
      if value.isEmpty {
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil) } else { fail(result, "Keychain: \(status)") }
        return
      }
      let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
      var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        var add = query
        add.merge(attributes) { _, new in new }
        status = SecItemAdd(add as CFDictionary, nil)
      }
      if status == errSecSuccess { result(nil) } else { fail(result, "Не удалось сохранить ключ: \(status)") }
    case "calendars", "today", "createEvent":
      calendarAccess { [weak self] granted, error in
        guard let self = self else { return }
        guard granted else { self.fail(result, error?.localizedDescription ?? "Разрешите Local Mind доступ к календарю в настройках macOS"); return }
        self.handleCalendar(call.method, args: args, result: result)
      }
    case "startSpeech": startSpeech(result)
    case "stopSpeech": stopSpeech(); result(nil)
    case "notifyAt":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        guard granted else {
          DispatchQueue.main.async { self.fail(result, error?.localizedDescription ?? "Разрешите уведомления Local Mind в настройках macOS") }
          return
        }
        guard let id = args["id"] as? String, let at = args["at"] as? Double else {
          DispatchQueue.main.async { self.fail(result, "Некорректное напоминание") }; return
        }
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? "Local Mind"
        content.body = args["body"] as? String ?? ""
        content.sound = .default
        let seconds = max(1, at / 1000 - Date().timeIntervalSince1970)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        UNUserNotificationCenter.current().add(request) { error in
          DispatchQueue.main.async {
            if let error = error { self.fail(result, error.localizedDescription) } else { result(nil) }
          }
        }
      }
    case "cancelNotification":
      if let id = args["id"] as? String { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func resizeChat(messages: Int, hasAction: Bool) {
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
    let content = CGFloat(min(max(messages - 1, 0), 4)) * 48
    let action = hasAction ? CGFloat(150) : 0
    chatHeight = min(max(300 + content + action, 300), max(300, visible.height * 0.5))
    guard isVisible else { return }
    let target = NSRect(
      x: visible.maxX - 430 - 12,
      y: visible.maxY - chatHeight - 10,
      width: 430,
      height: chatHeight
    )
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      animator().setFrame(target, display: true)
    }
  }

  private func keychainQuery(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.localmind.credentials", kSecAttrAccount as String: key]
  }

  private func codexExecutable() -> String? {
    var candidates = [
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "/usr/bin/codex",
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
    ]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
    }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  private func runCodex(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let executable = codexExecutable() else {
      fail(result, "Codex CLI не найден. Установите Codex и выполните codex login.")
      return
    }
    guard let prompt = args["prompt"] as? String, !prompt.isEmpty else {
      fail(result, "Пустой запрос для Codex")
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
          .appendingPathComponent("Local Mind/Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let schemaURL = support.appendingPathComponent("intent-schema.json")
        let schema = """
        {"type":"object","properties":{"kind":{"type":"string","enum":["note","task","event","answer","clarification"]},"text":{"type":"string"},"start":{"type":["string","null"]},"end":{"type":["string","null"]},"question":{"type":["string","null"]}},"required":["kind","text","start","end","question"],"additionalProperties":false}
        """
        try schema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = [
          "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
          "--skip-git-repo-check",
          "--sandbox", "read-only", "--cd", support.path,
          "--output-schema", schemaURL.path, "--color", "never",
        ]
        if let model = args["model"] as? String, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          arguments.append(contentsOf: ["--model", model])
        }
        let supportedEfforts: Set<String> = ["low", "medium", "high", "xhigh"]
        if let effort = args["reasoningEffort"] as? String,
           supportedEfforts.contains(effort) {
          arguments.append(contentsOf: ["-c", "model_reasoning_effort=\(effort)"])
        }
        arguments.append("-")
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(prompt.utf8))
        try input.fileHandleForWriting.close()

        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        group.enter()
        DispatchQueue.global().async {
          outputData = output.fileHandleForReading.readDataToEndOfFile()
          group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
          errorData = errors.fileHandleForReading.readDataToEndOfFile()
          group.leave()
        }
        process.waitUntilExit()
        group.wait()

        let response = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let diagnostics = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
          if process.terminationStatus == 0, !response.isEmpty { result(response) }
          else { self.fail(result, diagnostics.isEmpty ? "Codex завершился без ответа" : String(diagnostics.suffix(1200))) }
        }
      } catch {
        DispatchQueue.main.async { self.fail(result, "Не удалось запустить Codex: \(error.localizedDescription)") }
      }
    }
  }

  private func calendarAccess(_ completion: @escaping (Bool, Error?) -> Void) {
    let done: (Bool, Error?) -> Void = { granted, error in DispatchQueue.main.async { completion(granted, error) } }
    if #available(macOS 14.0, *) { eventStore.requestFullAccessToEvents(completion: done) }
    else { eventStore.requestAccess(to: .event, completion: done) }
  }

  private func handleCalendar(_ method: String, args: [String: Any], result: @escaping FlutterResult) {
    if method == "calendars" {
      result(eventStore.calendars(for: .event).filter { $0.allowsContentModifications }.map { ["id": $0.calendarIdentifier, "name": $0.title, "source": $0.source.title] })
    } else if method == "today" {
      let start = Calendar.current.startOfDay(for: Date())
      let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
      let events = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
      result(events.map { ["id": $0.eventIdentifier ?? "", "title": $0.title ?? "", "start": $0.startDate.timeIntervalSince1970 * 1000, "end": $0.endDate.timeIntervalSince1970 * 1000, "calendar": $0.calendar.title, "allDay": $0.isAllDay] as [String: Any] })
    } else {
      guard let id = args["id"] as? String, let calendarID = args["calendar"] as? String,
            let calendar = eventStore.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
            let startMs = args["start"] as? Double, let endMs = args["end"] as? Double, endMs > startMs else {
        fail(result, "Проверьте календарь и время события"); return
      }
      let start = Date(timeIntervalSince1970: startMs / 1000)
      let end = Date(timeIntervalSince1970: endMs / 1000)
      let url = URL(string: "localmind://entry/\(id)")!
      let existing = eventStore.events(matching: eventStore.predicateForEvents(withStart: start.addingTimeInterval(-86400), end: end.addingTimeInterval(86400), calendars: [calendar])).first { $0.url == url }
      if let existing = existing { result(existing.eventIdentifier); return }
      let event = EKEvent(eventStore: eventStore)
      event.calendar = calendar
      event.title = args["title"] as? String ?? ""
      event.notes = args["notes"] as? String
      event.startDate = start
      event.endDate = end
      event.url = url
      event.addAlarm(EKAlarm(relativeOffset: -Double(args["reminderMinutes"] as? Int ?? 0) * 60))
      do { try eventStore.save(event, span: .thisEvent, commit: true); result(event.eventIdentifier) }
      catch { fail(result, error.localizedDescription) }
    }
  }

  private func startSpeech(_ result: @escaping FlutterResult) {
    guard !speechStarting && !audioEngine.isRunning else {
      result(nil)
      return
    }
    stopSpeech(notify: false)
    speechStarting = true
    speechGeneration += 1
    let generation = speechGeneration
    SFSpeechRecognizer.requestAuthorization { authorization in
      guard authorization == .authorized else {
        DispatchQueue.main.async {
          guard generation == self.speechGeneration else { return }
          self.speechStarting = false
          self.fail(result, "Разрешите распознавание речи в настройках конфиденциальности macOS")
        }
        return
      }
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          guard generation == self.speechGeneration else { return }
          guard granted else {
            self.speechStarting = false
            self.fail(result, "Разрешите доступ к микрофону")
            return
          }
          self.beginRecognition(result, generation: generation)
        }
      }
    }
  }

  private func beginRecognition(_ result: @escaping FlutterResult, generation: Int) {
    guard generation == speechGeneration, speechStarting else { return }
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    guard let recognizer = recognizer, recognizer.isAvailable else {
      speechStarting = false
      fail(result, "Распознавание русской речи сейчас недоступно. Проверьте настройки диктовки macOS.")
      return
    }
    guard recognizer.supportsOnDeviceRecognition else {
      speechStarting = false
      fail(result, "На этом Mac недоступна локальная русская диктовка. Включите и загрузите русский язык в настройках диктовки macOS; пока можно использовать системную диктовку в текстовом поле.")
      return
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    let input = audioEngine.inputNode
    let format = input.inputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      speechStarting = false
      fail(result, "Микрофон недоступен")
      return
    }
    speechRequest = request
    input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in request.append(buffer) }
    hasAudioTap = true
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopSpeech(notify: false)
      fail(result, "Не удалось запустить микрофон: \(error.localizedDescription)")
      return
    }
    speechTask = recognizer.recognitionTask(with: request) { [weak self] response, error in
      DispatchQueue.main.async {
        guard let self = self, generation == self.speechGeneration else { return }
        if let response = response { self.bridge.invokeMethod("transcript", arguments: response.bestTranscription.formattedString) }
        if response?.isFinal == true || error != nil {
          self.stopSpeech()
          if let error = error { self.bridge.invokeMethod("speechError", arguments: error.localizedDescription) }
        }
      }
    }
    speechStarting = false
    result(nil)
  }

  private func stopSpeech(notify: Bool = true) {
    speechGeneration += 1
    speechStarting = false
    if audioEngine.isRunning { audioEngine.stop() }
    if hasAudioTap { audioEngine.inputNode.removeTap(onBus: 0); hasAudioTap = false }
    speechRequest?.endAudio()
    speechTask?.cancel()
    speechRequest = nil
    speechTask = nil
    if notify { bridge?.invokeMethod("speechEnded", arguments: nil) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound])
  }
}
