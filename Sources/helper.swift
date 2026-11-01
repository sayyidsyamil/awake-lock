import Foundation
import IOKit
import IOKit.ps
import Darwin

func onACPower() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
    return source as String == kIOPSACPowerValue
}
func wantsOverride(requested: Bool, ac: Bool, alive: Bool, expires: Double, deadline: Double, now: Double) -> Bool {
    requested && ac && alive && expires > now && expires <= now + 20 && (deadline == 0 || deadline > now)
}

if CommandLine.arguments.contains("--self-test") {
    let now = Date().timeIntervalSince1970
    precondition(wantsOverride(requested: true, ac: true, alive: true, expires: now + 12, deadline: 0, now: now))
    for (requested, ac, alive, expires, deadline) in [
        (false, true, true, now + 12, 0.0), (true, false, true, now + 12, 0.0),
        (true, true, false, now + 12, 0.0), (true, true, true, now - 1, 0.0),
        (true, true, true, now + 12, now - 1), (true, true, true, now + 100, 0.0)] {
        precondition(!wantsOverride(requested: requested, ac: ac, alive: alive, expires: expires, deadline: deadline, now: now))
    }
    print("PASS: AC gating, off switch, app exit, heartbeat expiry, session deadline, bounded lease")
    exit(0)
}

guard getuid() == 0, CommandLine.arguments.count == 4,
      let expectedUID = uid_t(CommandLine.arguments[1]), expectedUID != 0 else { exit(1) }
let requestURL = URL(fileURLWithPath: CommandLine.arguments[2])
let expectedExecutable = CommandLine.arguments[3]
let markerURL = URL(fileURLWithPath: "/var/db/com.user.awake-lock-previous-sleep.plist")
let statusURL = URL(fileURLWithPath: "/var/run/com.user.awake-lock-helper.plist")

@Sendable func sleepDisabled() -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    return IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? Bool ?? false
}
@Sendable func setSleepDisabled(_ disabled: Bool) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
    do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 && sleepDisabled() == disabled }
    catch { return false }
}
@Sendable func writePlist(_ value: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    try data.write(to: url, options: .atomic)
}
@Sendable func readPlist(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url), data.count < 4096 else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}
@Sendable func restore() -> Bool {
    guard let marker = readPlist(markerURL), let previous = marker["previous"] as? Bool else { return true }
    guard setSleepDisabled(previous) else { return false }
    try? FileManager.default.removeItem(at: markerURL)
    return true
}

// Recover the original setting after a crash/reboot before accepting a new lease.
var recovered = restore()
var active = false
var lastStatus: TimeInterval = 0
func tick() {
    let now = Date().timeIntervalSince1970
    var requested = false
    var metadata = stat()
    if lstat(requestURL.path, &metadata) == 0, metadata.st_uid == expectedUID,
       metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size < 4096,
       let request = readPlist(requestURL), let pid = request["pid"] as? Int32 {
        var path = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        let alive = length > 0 && String(cString: path) == expectedExecutable
        requested = wantsOverride(requested: request["requested"] as? Bool ?? false,
            ac: onACPower(), alive: alive, expires: request["expires"] as? Double ?? 0,
            deadline: request["deadline"] as? Double ?? 0, now: now)
    }
    if !recovered { recovered = restore(); if recovered { active = false } }
    if recovered && requested && !active {
        do {
            try writePlist(["previous": sleepDisabled()], to: markerURL)
            if setSleepDisabled(true) { active = true }
            else { recovered = restore() }
        } catch { NSLog("Awake Lock helper: %@", error.localizedDescription) }
    } else if !requested && active {
        if restore() { active = false } else { recovered = false }
    }
    if now - lastStatus >= 2 {
        try? writePlist(["updated": now, "active": active && requested && sleepDisabled()], to: statusURL)
        lastStatus = now
    }
}
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
for source in [term, interrupt] {
    source.setEventHandler { _ = restore(); try? FileManager.default.removeItem(at: statusURL); exit(0) }
    source.resume()
}
tick()
let timer = Timer(timeInterval: 1, repeats: true) { _ in tick() }
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
