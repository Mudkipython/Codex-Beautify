import AppKit
import AVFoundation
import QuartzCore

// Native, independent launcher. No changes to the target app, Dock or login items.
private let targetID: String = {
    if let i = CommandLine.arguments.firstIndex(of: "--target-bundle"), i + 1 < CommandLine.arguments.count { return CommandLine.arguments[i + 1] }
    return "com.openai.codex"
}()
private let diagnosticURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("local.dragoncodexboot.macos", isDirectory: true)
    .appendingPathComponent("last-run.log")

func report(_ message: String) {
    print("[DragonCodexBoot] \(message)")
    fflush(stdout)
    if let handle = try? FileHandle(forWritingTo: diagnosticURL) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message)\n".utf8))
    }
}

final class MovieWindow: NSWindow {
    var skip: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { skip?() } else { super.keyDown(with: event) }
    }
}

final class Launcher: NSObject, NSApplicationDelegate {
    var window: MovieWindow?
    var player: AVPlayer?
    var target: NSRunningApplication?
    var statusObservation: NSKeyValueObservation?
    var endObserver: NSObjectProtocol?
    var failedObserver: NSObjectProtocol?
    var timeObserver: Any?
    var watchdog: Timer?
    var playbackProgress = PlaybackProgressWatchdog()
    var beganAt = Date()
    var readyAt: Date?
    var heldAt: Date?
    var finishing = false
    var codexRouteRequested = false
    var codexRouteInFlight = false
    var nextActivationAt = Date.distantPast
    var activationAttempts = 0
    var launchFinished = false
    var launchInFlight = false
    var launchAttempts = 0
    var retryAfter = Date.distantPast
    var skipRequested = false
    var playbackStarted = false
    var targetURL: URL?
    let verification = CommandLine.arguments.contains("--verify")

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: diagnosticURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: diagnosticURL, options: .atomic)
        report("START")
        if let i = CommandLine.arguments.firstIndex(of: "--target-path"), i + 1 < CommandLine.arguments.count {
            targetURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        } else {
            targetURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetID)
        }
        guard let url = Bundle.main.url(forResource: "startup", withExtension: "mp4") else {
            fail("缺少启动视频 startup.mp4，请重新安装完整的启动器。")
            return
        }
        guard targetURL != nil else {
            fail("没有找到 ChatGPT（应用标识 com.openai.codex）。请先安装 ChatGPT 桌面客户端。")
            return
        }
        if verification {
            Task { @MainActor in
                do {
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration)
                    let playable = try await asset.load(.isPlayable)
                    let videos = try await asset.loadTracks(withMediaType: .video)
                    let audios = try await asset.loadTracks(withMediaType: .audio)
                    guard playable, duration.seconds > 13.65, !videos.isEmpty, !audios.isEmpty else {
                        self.fail("视频验证失败。")
                        return
                    }
                    report("VERIFY OK: \(duration.seconds)s; video=\(videos.count); audio=\(audios.count); target=\(self.targetURL!.path)")
                    NSApp.terminate(nil)
                } catch { self.fail("视频读取失败：\(error.localizedDescription)") }
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--test-skip-after"), i + 1 < CommandLine.arguments.count,
           let delay = Double(CommandLine.arguments[i + 1]), delay >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.skip() }
        }
        createMenu()
        showMovie(url)
        guard !finishing else { return }
        launchTarget()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func createMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let submenu = NSMenu()
        submenu.addItem(withTitle: "跳过动画", action: #selector(skip), keyEquivalent: ".").target = self
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出启动器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        NSApp.mainMenu = menu
    }

    func showMovie(_ url: URL) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            fail("没有可用的显示器。")
            return
        }
        let visible = screen.visibleFrame
        let width = min(1280, visible.width * 0.9, visible.height * 0.9 * 16 / 9)
        let height = width * 9 / 16
        let rect = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        let movie = MovieWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        movie.title = "Dragon Codex Boot"
        movie.backgroundColor = .black
        movie.isReleasedWhenClosed = false
        movie.level = .floating
        movie.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        movie.hasShadow = true
        movie.skip = { [weak self] in self?.skip() }
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.volume = 1
        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer!.addSublayer(layer)
        let button = NSButton(title: "跳过 · Esc", target: self, action: #selector(skip))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: width - 114, y: height - 42, width: 100, height: 28)
        button.autoresizingMask = [.minXMargin, .minYMargin]
        view.addSubview(button)
        movie.contentView = view
        window = movie
        player = avPlayer
        movie.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        report("WINDOW shown \(Int(width))x\(Int(height))")
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self, !self.finishing else { return }
                if item.status == .readyToPlay {
                    self.readyAt = Date()
                    if !self.skipRequested { self.player?.play() }
                    report("PLAYBACK ready")
                } else if item.status == .failed {
                    report("PLAYBACK failed: \(item.error?.localizedDescription ?? "unknown")")
                    self.skip()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.skip()
        }
        failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.skip()
        }
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self, !self.finishing else { return }
            if time.seconds > 0.1 && !self.playbackStarted {
                self.playbackStarted = true
                report("PLAYBACK advancing")
            }
            if time.seconds >= 11.3 && !self.launchFinished && self.heldAt == nil {
                self.heldAt = Date()
                self.player?.pause()
                report("HOLD waiting for application")
            }
            if time.seconds >= 12.7 && self.launchFinished { self.handoff() }
        }
    }

    func launchTarget() {
        let configuration = NSWorkspace.OpenConfiguration()
        guard !launchInFlight else { return }
        launchInFlight = true
        launchAttempts += 1
        retryAfter = Date().addingTimeInterval(3)
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: targetURL!, configuration: configuration) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self = self, !self.finishing else { return }
                self.launchInFlight = false
                guard let application = application else {
                    self.fail("ChatGPT 启动失败：\(error?.localizedDescription ?? "未知错误")")
                    return
                }
                self.target = application
                report("TARGET launched: \(application.bundleIdentifier ?? "unknown")")
                self.requestCodexRoute()
                self.refreshTarget()
            }
        }
    }

    func requestCodexRoute() {
        guard targetID == "com.openai.codex", !codexRouteRequested,
              !codexRouteInFlight, let appURL = targetURL else { return }
        codexRouteInFlight = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(string: "codex://new?mode=codex")!],
                                withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self, !self.finishing else { return }
                self.codexRouteInFlight = false
                guard error == nil else {
                    self.fail("无法进入 Codex：\(error!.localizedDescription)")
                    return
                }
                self.codexRouteRequested = true
                report("CODEX route accepted: mode=codex")
                self.refreshTarget()
            }
        }
    }

    // LaunchServices may return a transient process. Resolve the live instance
    // again and require a real window before releasing the animation.
    func refreshTarget() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: targetID)
            .filter { !$0.isTerminated }
        let live = running.first { $0.isFinishedLaunching }
        target = live
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ready = live.map { app in
            windows.contains { info in
                guard (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let width = bounds["Width"] as? Double,
                      let height = bounds["Height"] as? Double else { return false }
                return width > 200 && height > 100
            }
        } ?? false
        let routeReady = targetID != "com.openai.codex" || codexRouteRequested
        if let live = live, !ready, Date() >= nextActivationAt, activationAttempts < 4 {
            activationAttempts += 1
            nextActivationAt = Date().addingTimeInterval(3)
            let activated = live.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            report("TARGET wake attempt=\(activationAttempts) activation=\(activated)")
        }
        if ready && routeReady && !launchFinished {
            report("TARGET window ready pid=\(live!.processIdentifier)")
            launchFinished = true
            if skipRequested { handoff() }
            else if heldAt != nil {
                heldAt = nil
                playbackProgress = PlaybackProgressWatchdog()
                player?.play()
            }
        } else if !ready || !routeReady {
            launchFinished = false
            if running.isEmpty && !launchInFlight && Date() > retryAfter && launchAttempts < 2 {
                report("TARGET retry after transient process exit")
                codexRouteRequested = false
                launchTarget()
            }
        }
    }

    func tick() {
        guard !finishing else { return }
        refreshTarget()
        guard !finishing else { return }
        if Date().timeIntervalSince(beganAt) > 65 {
            fail("等待 ChatGPT 超时。请直接打开 ChatGPT 后重试。")
        } else if readyAt == nil && Date().timeIntervalSince(beganAt) > 10 {
            skip()
        } else if playbackProgress.isStalled(
            position: player?.currentTime().seconds ?? .nan,
            now: ProcessInfo.processInfo.systemUptime,
            pausedForLaunch: !launchFinished && heldAt != nil
        ) && launchFinished {
            // Bounded fallback for a stalled media pipeline.
            skip()
        }
    }

    @objc func skip() {
        guard !finishing else { return }
        skipRequested = true
        player?.pause()
        report("SKIP requested")
        window?.orderOut(nil)
        if launchFinished { handoff() }
    }

    func handoff() {
        guard !finishing else { return }
        guard let application = target, !application.isTerminated, launchFinished else {
            launchFinished = false
            return
        }
        finishing = true
        watchdog?.invalidate()
        let activated = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        report("HANDOFF activation=\(activated)")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = skipRequested ? 0.18 : 0.95
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window?.animator().alphaValue = 0
        } completionHandler: {
            self.player?.pause()
            self.window?.orderOut(nil)
            // Repeat after the overlay closes to give the real app keyboard focus.
            _ = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            report("FINISHED")
            NSApp.terminate(nil)
        }
    }

    func fail(_ message: String) {
        report("ERROR: \(message)")
        if verification { exit(1) }
        finishing = true
        watchdog?.invalidate()
        player?.pause()
        window?.orderOut(nil)
        let alert = NSAlert()
        alert.messageText = "Dragon Codex Boot"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        watchdog?.invalidate()
        player?.pause()
        if let observer = timeObserver { player?.removeTimeObserver(observer) }
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = failedObserver { NotificationCenter.default.removeObserver(observer) }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let launcher = Launcher()
application.delegate = launcher
application.run()
