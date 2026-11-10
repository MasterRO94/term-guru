import AppKit
import GuruCore
import UserNotifications

final class UpdateController: NSObject {
    private static let checkInterval: TimeInterval = 1800
    private static let pollInterval: TimeInterval = 2

    let menuItem = NSMenuItem(title: "Check for Updates…", action: #selector(menuClicked), keyEquivalent: "")
    var automatic = true { didSet { if automatic != oldValue { schedule() } } }

    private let log = FileLog(name: "app.log")
    private let store = UpdateStore()
    private let queue = DispatchQueue(label: "dev.termguru.update", qos: .utility)
    private let supported = SemVer.normalize(GuruVersion.current) != nil
    private var checkTimer: Timer?
    private var pollTimer: Timer?
    private var available: String?
    private var checking = false

    override init() {
        super.init()
        menuItem.target = self
    }

    func start() {
        guard supported else {
            menuItem.title = "Updates Unavailable (Development Build)"
            menuItem.action = nil
            return
        }
        if let latest = store.load().latest, SemVer.isNewer(latest, than: GuruVersion.current) { available = latest }
        if store.currentRun() != nil { watchRun() }
        refreshMenu()
        schedule()
    }

    func checkNow() {
        check(manual: true)
    }

    private func schedule() {
        checkTimer?.invalidate()
        checkTimer = nil
        guard supported, automatic else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in self?.check(manual: false) }
        check(manual: false)
    }

    // MARK: Checking

    private func check(manual: Bool) {
        guard supported, !checking, pollTimer == nil else { return }
        checking = true
        refreshMenu()
        queue.async {
            let resolved = UpdateSource.resolve()
            let lookup = resolved.source.map(LatestRelease.fetch)
            DispatchQueue.main.async { self.finishCheck(resolved.reason, lookup, manual: manual) }
        }
    }

    private func finishCheck(_ sourceProblem: String?, _ lookup: LatestRelease.Lookup?, manual: Bool) {
        checking = false
        defer { refreshMenu() }
        switch lookup {
        case .found(let latest):
            store.mutate { $0.latest = latest; $0.checkedAt = Date() }
            guard SemVer.isNewer(latest, than: GuruVersion.current) else {
                available = nil
                if manual { alert("TermGuru is up to date", "Version \(GuruVersion.current) is the newest release.") }
                return
            }
            available = latest
            if manual {
                confirmInstall(latest)
            } else if store.load().notifiedVersion != latest {
                store.mutate { $0.notifiedVersion = latest }
                notify("TermGuru \(latest) is available", "Choose “Update to \(latest)…” in the TermGuru menu to install it.")
            }
        case .noReleases:
            if manual { alert("No releases found", "The repository has no release tags yet.") }
        case .unreachable(let reason):
            log.write("update check failed: \(reason)")
            if manual { alert("Could not check for updates", reason.isEmpty ? "The repository could not be reached." : reason) }
        case nil:
            if manual { alert("Could not check for updates", sourceProblem ?? "The source checkout was not found.") }
        }
    }

    // MARK: Installing

    @objc private func menuClicked() {
        if let available { confirmInstall(available) } else { check(manual: true) }
    }

    private func confirmInstall(_ version: String) {
        let resolved = UpdateSource.resolve()
        guard let source = resolved.source else {
            alert("Could not update", resolved.reason ?? "The source checkout was not found.")
            return
        }
        let prompt = NSAlert()
        prompt.messageText = "Update TermGuru to \(version)?"
        var details = "Version \(GuruVersion.current) is installed. The update is fetched into \(source.path), rebuilt there and reinstalled. TermGuru restarts when it is done."
        if source.isAdHocSigned {
            details += "\n\nmacOS forgets the Accessibility permission after a rebuild, so you will be asked to enable TermGuru again."
        }
        prompt.informativeText = details
        prompt.addButton(withTitle: "Install")
        prompt.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        do {
            let pid = try UpdateLauncher.launchDetached(source: source, version: version)
            store.mutate { $0.run = UpdateRun(state: .preparing, version: version, pid: pid) }
            log.write("update to \(version) started, pid \(pid)")
            watchRun()
        } catch {
            alert("Could not update", "\(error.localizedDescription)")
        }
    }

    private func watchRun() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.pollRun() }
        refreshMenu()
        pollRun()
    }

    private func pollRun() {
        guard let run = store.currentRun() else { return stopWatching() }
        if run.state.isBusy { return }
        stopWatching()
        store.clearRun()
        log.write("update to \(run.version) finished: \(run.state.rawValue)")
        if run.state == .installed {
            // The run outlives the app that started it; only the freshly installed build reports success.
            if run.version == GuruVersion.current { finishInstall(run) }
            return
        }
        reportFailure(run)
    }

    private func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
        refreshMenu()
    }

    private func finishInstall(_ run: UpdateRun) {
        available = nil
        guard run.resetAccessibility else {
            notify("TermGuru updated", "Version \(run.version) is installed.")
            return
        }
        let prompt = NSAlert()
        prompt.messageText = "TermGuru updated to \(run.version)"
        prompt.informativeText = "macOS dropped the Accessibility permission for the rebuilt app. Enable TermGuru again in Privacy & Security › Accessibility so the popup can follow the caret."
        prompt.addButton(withTitle: "Open Accessibility Settings")
        prompt.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard prompt.runModal() == .alertFirstButtonReturn,
              let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(pane)
    }

    private func reportFailure(_ run: UpdateRun) {
        let prompt = NSAlert()
        prompt.alertStyle = .warning
        switch run.state {
        case .dirty: prompt.messageText = "Update paused"
        case .diverged: prompt.messageText = "Update stopped"
        default: prompt.messageText = "Update to \(run.version) failed"
        }
        var details = run.error ?? "The update did not finish."
        if run.state == .failed, let log = run.log, let text = try? String(contentsOfFile: log, encoding: .utf8) {
            details += "\n\n" + text.split(separator: "\n").suffix(12).joined(separator: "\n")
        }
        prompt.informativeText = details
        prompt.addButton(withTitle: "OK")
        if run.log != nil { prompt.addButton(withTitle: "Reveal Log") }
        NSApp.activate(ignoringOtherApps: true)
        if prompt.runModal() == .alertSecondButtonReturn, let log = run.log {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: log)])
        }
    }

    // MARK: Presentation

    private func refreshMenu() {
        if pollTimer != nil {
            menuItem.title = "Updating…"
            menuItem.action = nil
        } else if checking {
            menuItem.title = "Checking for Updates…"
            menuItem.action = nil
        } else {
            menuItem.title = available.map { "Update to \($0)…" } ?? "Check for Updates…"
            menuItem.action = #selector(menuClicked)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func notify(_ title: String, _ body: String) {
        // The notification centre traps without a bundle, which a bare `swift build` binary lacks.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
