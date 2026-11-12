import AppKit

// Observe only launches; no polling, screen capture or accessibility access.
let arguments = CommandLine.arguments
let targetID = arguments.count > 1 ? arguments[1] : "com.openai.codex"
let launcherPath = arguments.count > 2 ? arguments[2] : NSHomeDirectory() + "/Applications/Dragon Codex Boot.app"
var lastLaunch = Date.distantPast
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let observer = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { notification in
    guard let target = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          target.bundleIdentifier == targetID,
          Date().timeIntervalSince(lastLaunch) > 8,
          NSRunningApplication.runningApplications(withBundleIdentifier: "local.dragoncodexboot.macos").isEmpty else { return }
    lastLaunch = Date()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.arguments = ["--from-monitor"]
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: launcherPath), configuration: configuration) { _, error in
        if let error = error { NSLog("Dragon launch overlay failed: %@", error.localizedDescription) }
        else { NSLog("Dragon launch overlay started for %@", targetID) }
    }
}
app.run()
