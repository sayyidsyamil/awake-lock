import AppKit
import SwiftUI
import ServiceManagement
import IOKit.pwr_mgt
import IOKit.ps
import Darwin

func onACPower() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
    return source as String == kIOPSACPowerValue
}

final class AwakeSession {
    var enabled = false
    var deadline: Date?
    private(set) var assertion: IOPMAssertionID = 0
    var error: IOReturn = kIOReturnSuccess
    func reconcile(now: Date = Date()) {
        if let deadline, now >= deadline { enabled = false; self.deadline = nil }
        if enabled && assertion == 0 {
            error = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Awake Lock — keep AI tasks running" as CFString, &assertion)
        } else if !enabled && assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) } }
}

final class PanelState: ObservableObject {
    @Published var enabled = false
    @Published var active = false
    @Published var remaining = "Until turned off"
    @Published var deadline: Date?
    @Published var ac = false
    @Published var closedLid = false
    @Published var helperInstalled = false
    @Published var helperActive = false
    @Published var installing = false
    @Published var login = true
    @Published var durationMinutes = 60.0
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var loginFramework: UnsafeMutableRawPointer?
    private var timer: Timer?
    private let panelState = PanelState()
    private let popover = NSPopover()
    private let session = AwakeSession()
    private let defaults = UserDefaults.standard
    private var closedLid = false
    private var installing = false
    private let helperPath = "/Library/PrivilegedHelperTools/com.user.awake-lock-helper"
    private let requestURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Awake Lock/request.plist")

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["awakeEnabled": false, "startAtLogin": false])
        defaults.set(SMAppService.mainApp.status == .enabled, forKey: "startAtLogin")
        session.enabled = defaults.bool(forKey: "awakeEnabled")
        let end = defaults.double(forKey: "deadline")
        if end > 0 { session.deadline = Date(timeIntervalSince1970: end) }
        closedLid = defaults.bool(forKey: "closedLid")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if defaults.object(forKey: "NSStatusItem Preferred Position AwakeLock") == nil {
            defaults.set(260, forKey: "NSStatusItem Preferred Position AwakeLock")
        }
        statusItem.autosaveName = "AwakeLock"
        statusItem.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 368, height: 590)
        popover.contentViewController = NSHostingController(rootView: AwakePanel(state: panelState,
            toggle: { [weak self] in self?.toggleAwake() },
            start: { [weak self] minutes in self?.start(minutes: minutes) },
            custom: { [weak self] in self?.customDuration() },
            lid: { [weak self] in self?.toggleClosedLid() },
            lock: { [weak self] in self?.popover.close(); self?.lockScreen() },
            login: { [weak self] in self?.toggleLogin(); self?.syncPanel() },
            about: { [weak self] in self?.about() },
            quit: { [weak self] in self?.quitApp() }))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        loginFramework = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
        tick()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(tick),
            name: NSWorkspace.didWakeNotification, object: nil)
        if CommandLine.arguments.contains("--install-helper") {
            DispatchQueue.main.async { self.installHelper() }
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.togglePanel() }
        }
    }

    @objc private func tick() {
        session.reconcile()
        save()
        writeRequest()
        updateIcon()
        syncPanel()
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            tick()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func syncPanel() {
        panelState.enabled = session.enabled
        panelState.active = session.assertion != 0
        panelState.remaining = remainingText
        panelState.deadline = session.deadline
        panelState.ac = onACPower()
        panelState.closedLid = closedLid
        panelState.helperInstalled = FileManager.default.fileExists(atPath: helperPath)
        panelState.helperActive = helperActive
        panelState.installing = installing
        panelState.login = defaults.bool(forKey: "startAtLogin")
        panelState.durationMinutes = defaults.object(forKey: "durationMinutes") as? Double ?? 60
    }

    private func save() {
        defaults.set(session.enabled, forKey: "awakeEnabled")
        defaults.set(session.deadline?.timeIntervalSince1970 ?? 0, forKey: "deadline")
        defaults.set(closedLid, forKey: "closedLid")
    }

    private func writeRequest(stopping: Bool = false) {
        let request: [String: Any] = [
            "pid": Int(getpid()), "expires": Date().timeIntervalSince1970 + 12,
            "deadline": session.deadline?.timeIntervalSince1970 ?? 0,
            "requested": !stopping && closedLid && session.enabled && session.assertion != 0
        ]
        do {
            try FileManager.default.createDirectory(at: requestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try PropertyListSerialization.data(fromPropertyList: request, format: .binary, options: 0)
            try data.write(to: requestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        } catch { NSLog("Awake Lock: could not update helper request: %@", error.localizedDescription) }
    }

    private func rootSleepDisabled() -> Bool {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if entry == 0 { return false }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool ?? false
    }

    private var helperActive: Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/var/run/com.user.awake-lock-helper.plist")),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let time = value["updated"] as? Double,
              Date().timeIntervalSince1970 - time < 6 else { return false }
        return value["active"] as? Bool == true && rootSleepDisabled()
    }

    private func updateIcon() {
        let active = session.assertion != 0
        let symbol = active ? "lock.fill" : "lock"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Awake Lock")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = active ? " ·" : ""
        statusItem.button?.toolTip = active ? "Awake Lock: awake — \(remainingText)" : "Awake Lock: normal sleep"
    }

    private var remainingText: String {
        guard let deadline = session.deadline else { return "until turned off" }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        return String(format: "%d:%02d:%02d remaining", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func add(_ title: String, action: Selector? = nil, to menu: NSMenu,
                     enabled: Bool = true, checked: Bool = false, tag: Int = 0) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        item.tag = tag
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        tick()
        menu.removeAllItems()
        add("Awake Lock", to: menu, enabled: false)
        let status = session.assertion != 0 ? "Awake · \(remainingText)" :
            (session.enabled ? "Could not prevent sleep (\(session.error))" : "Normal sleep allowed")
        add(status, to: menu, enabled: false)
        add(onACPower() ? "Power: plugged in" : "Power: battery", to: menu, enabled: false)
        menu.addItem(.separator())
        add("Keep Mac Awake", action: #selector(toggleAwake), to: menu, checked: session.enabled)
        let durations = NSMenu()
        durations.autoenablesItems = false
        for (title, minutes) in [("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60),
                                 ("2 hours", 120), ("4 hours", 240), ("8 hours", 480),
                                 ("Until turned off", 0)] {
            add(title, action: #selector(startDuration(_:)), to: durations, tag: minutes)
        }
        durations.addItem(.separator())
        add("Custom duration…", action: #selector(customDuration), to: durations)
        let duration = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        duration.submenu = durations
        menu.addItem(duration)
        add("Stop Keep-Awake Session", action: #selector(stopSession), to: menu, enabled: session.enabled)
        menu.addItem(.separator())
        add("Stay Awake With Lid Closed (AC Only)", action: #selector(toggleClosedLid),
            to: menu, enabled: !installing, checked: closedLid)
        let lidStatus: String
        if helperActive { lidStatus = "Closed-lid override active · AC only" }
        else if closedLid && !onACPower() { lidStatus = "Closed-lid mode waiting for charger" }
        else if closedLid && session.enabled { lidStatus = "Closed-lid helper starting / unavailable" }
        else if closedLid { lidStatus = "Closed-lid mode ready · start a session" }
        else { lidStatus = "Lid closure follows normal macOS behavior" }
        add(lidStatus, to: menu, enabled: false)
        if !FileManager.default.fileExists(atPath: helperPath) {
            add(installing ? "Installing helper…" : "Enable Closed-Lid Support…", action: #selector(installHelper),
                to: menu, enabled: !installing)
        }
        menu.addItem(.separator())
        add("Lock Screen Now", action: #selector(lockScreen), to: menu)
        add("Start at Login", action: #selector(toggleLogin), to: menu,
            checked: defaults.bool(forKey: "startAtLogin"))
        add("About Awake Lock…", action: #selector(about), to: menu)
        menu.addItem(.separator())
        add("Quit Awake Lock", action: #selector(quitApp), to: menu)
    }

    @objc private func toggleAwake() {
        session.enabled.toggle()
        session.deadline = nil
        tick()
    }
    @objc private func stopSession() { session.enabled = false; session.deadline = nil; tick() }
    @objc private func startDuration(_ sender: NSMenuItem) { start(minutes: Double(sender.tag)) }
    private func start(minutes: Double) {
        defaults.set(minutes, forKey: "durationMinutes")
        session.enabled = true
        session.deadline = minutes > 0 ? Date().addingTimeInterval(minutes * 60) : nil
        tick()
    }
    @objc private func customDuration() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Keep Awake For"
        alert.informativeText = "Enter a duration in minutes (1–10,080)."
        let input = NSTextField(string: "60")
        input.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn {
            if let minutes = Double(input.stringValue), minutes.isFinite, minutes >= 1, minutes <= 10080 {
                start(minutes: minutes)
            } else { show("Invalid duration", "Please enter a number from 1 to 10,080 minutes.") }
        }
    }

    @objc private func toggleClosedLid() {
        if !FileManager.default.fileExists(atPath: helperPath) { installHelper(); return }
        closedLid.toggle()
        tick()
    }
    @objc private func installHelper() {
        guard !installing, let resources = Bundle.main.resourceURL else { return }
        installing = true
        syncPanel()
        let scriptPath = resources.appendingPathComponent("install-helper.sh").path
        let shell = "/bin/sh '" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global().async {
            var error: NSDictionary?
            let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")
            script?.executeAndReturnError(&error)
            let message = error?[NSAppleScript.errorMessage] as? String
            DispatchQueue.main.async {
                self.installing = false
                self.syncPanel()
                if let message { self.show("Closed-lid setup did not finish", message) }
                else { self.closedLid = true; self.tick(); self.show("Closed-lid support enabled",
                    "Connect your charger and start a keep-awake session. The override automatically stops on battery, when the session ends, or when this app exits. Keep the Mac on a ventilated surface, not in a bag. Lock your screen before closing the lid.") }
            }
        }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            defaults.set(SMAppService.mainApp.status == .enabled, forKey: "startAtLogin")
        } catch { show("Could not update login setting", error.localizedDescription) }
    }
    private func show(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    @objc private func about() {
        show("Awake Lock", "Keep AI tools and other apps running while the screen locks or turns off. Choose a timed session or stay awake until turned off. Ending a timer releases this app’s sleep prevention; it does not force sleep or stop your tasks. Closed-lid support requires administrator setup and AC power. It disables system sleep during the session and restores the previous setting afterwards. Other apps may also prevent sleep.")
    }
    @objc private func lockScreen() {
        guard let handle = loginFramework, let symbol = dlsym(handle, "SACLockScreenImmediate") else { NSSound.beep(); return }
        typealias LockFunction = @convention(c) () -> Void
        unsafeBitCast(symbol, to: LockFunction.self)()
    }
    @objc private func quitApp() { stopSession(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { writeRequest(stopping: true) }
}

if let index = CommandLine.arguments.firstIndex(of: "--capture-preview"), CommandLine.arguments.count > index + 1 {
    // Render documentation previews without altering a user's live session or power settings.
    _ = NSApplication.shared
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    for dark in [false, true] {
        let state = PanelState()
        state.enabled = true; state.active = true; state.ac = true
        state.helperInstalled = true; state.login = true
        state.deadline = Date().addingTimeInterval(3600)
        let panel = AwakePanel(state: state, toggle: {}, start: { _ in }, custom: {}, lid: {}, lock: {}, login: {}, about: {}, quit: {})
            .environment(\.colorScheme, dark ? .dark : .light)
        let view = NSHostingView(rootView: panel)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(dark ? "dark.png" : "light.png"))
    }
    print("Saved light and dark documentation previews")
} else if CommandLine.arguments.contains("--self-test") {
    let session = AwakeSession()
    session.enabled = true
    session.deadline = Date().addingTimeInterval(1)
    session.reconcile()
    precondition(session.assertion != 0, "Native sleep assertion failed")
    precondition(session.enabled)
    session.reconcile(now: Date().addingTimeInterval(2))
    precondition(!session.enabled && session.assertion == 0 && session.deadline == nil, "Timer did not release assertion")
    session.enabled = true
    session.reconcile()
    precondition(session.assertion != 0 && session.deadline == nil)
    session.enabled = false
    session.reconcile()
    precondition(session.assertion == 0)
    print("PASS: native assertion creation, timed expiry, indefinite session, manual release")
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
