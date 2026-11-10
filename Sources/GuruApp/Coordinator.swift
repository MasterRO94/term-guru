import AppKit
import GuruCore

final class ShellSession {
    let connection: SocketConnection
    var pid: pid_t = 0
    var shell = "zsh"
    var path = ""
    var aliases: [String: String] = [:]
    var buffer = ""
    var cursor = 0
    var cwd = ""
    var popupVisible = false
    /// Word index the user dismissed with Escape; the popup stays hidden until they move to another word.
    var dismissedWord: Int?
    lazy var hostApp: NSRunningApplication? = ProcessTree.owningApp(of: pid)

    init(connection: SocketConnection) { self.connection = connection }
}

final class Coordinator {
    private let log = FileLog(name: "app.log")
    private let engineQueue = DispatchQueue(label: "dev.termguru.engine", qos: .userInteractive)
    private lazy var engine = Engine(specs: SpecRuntime(specsDirectory: GuruResources.specs))
    private var server: SocketServer?
    private var sessions: [Int: ShellSession] = [:]
    private var connections: [Int: SocketConnection] = [:]
    private var active: ShellSession?
    private var generation = 0
    private var navigated = false
    private var paused = false
    private var enterAction = EnterAction.insert
    private let keyTap = KeyTap()
    private let popup = PopupController()
    private let caret = CaretLocator()
    private var statusItem: NSStatusItem?
    private let settingsWindow = SettingsWindowController()
    private var pauseItem: NSMenuItem?
    private let updates = UpdateController()
    private let headless = ProcessInfo.processInfo.environment["GURU_HEADLESS"] != nil

    func start() {
        let server = SocketServer { [weak self] connection in self?.accept(connection) }
        do {
            try server.start()
        } catch {
            log.write("socket failed: \(error)")
            NSApp.terminate(nil)
            return
        }
        self.server = server
        popup.onPick = { [weak self] index in self?.pick(index) }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.hide() }
        keyTap.isArmed = { [weak self] in self?.active?.popupVisible == true }
        keyTap.ensure()
        installStatusItem()
        let settings = settingsWindow.model
        settings.onChange = { [weak self] in self?.apply($0) }
        settings.onPause = { [weak self] in self?.setPaused($0) }
        settings.onRescan = { [weak self] in self?.rescan() }
        settings.onCheckUpdates = { [weak self] in self?.updates.checkNow() }
        apply(settings.settings)
        if !headless { updates.start() }
        // Warm the JavaScript engine so the first keystroke is not the slow one.
        engineQueue.async { [engine] in _ = engine.suggest(EngineRequest(buffer: "git ", cursor: 4, cwd: "/", path: "")) }
        log.write("started, specs at \(GuruResources.specs.path)")
    }

    func stop() { server?.stop() }

    // MARK: Connections

    private func accept(_ connection: SocketConnection) {
        connections[connection.id] = connection
        connection.onLine = { [weak self, weak connection] line in
            guard let self, let connection else { return }
            self.handle(line, from: connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            if let session = self.sessions.removeValue(forKey: connection.id), session === self.active {
                self.active = nil
                self.popup.hide()
            }
            self.caret.unregister(connection)
            self.connections[connection.id] = nil
        }
    }

    private func handle(_ line: String, from connection: SocketConnection) {
        if line.hasPrefix("{") {
            handleJSON(line, from: connection)
            return
        }
        let fields = Wire.split(line)
        guard let type = fields.first else { return }
        if type == "C" {
            handleCommand(Array(fields.dropFirst()), from: connection)
            return
        }
        let session = sessions[connection.id] ?? {
            let created = ShellSession(connection: connection)
            sessions[connection.id] = created
            return created
        }()
        switch type {
        case "H" where fields.count >= 5:
            session.pid = pid_t(fields[1]) ?? 0
            session.shell = fields[2]
            session.path = fields[4]
        case "A":
            var aliases: [String: String] = [:]
            var index = 1
            while index + 1 < fields.count {
                aliases[fields[index]] = fields[index + 1]
                index += 2
            }
            session.aliases = aliases
        case "E" where fields.count >= 4:
            session.cursor = Int(fields[1]) ?? 0
            session.cwd = fields[2]
            session.buffer = fields[3]
            edit(session)
        case "K" where fields.count >= 2:
            key(fields[1], session: session)
        case "X", "L":
            session.dismissedWord = nil
            if session === active { hide() }
        default:
            break
        }
    }

    private func handleJSON(_ line: String, from connection: SocketConnection) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        switch object["t"] as? String {
        case "ide":
            if let pid = (object["pid"] as? NSNumber)?.int32Value {
                caret.registerIDE(pid: pid, connection: connection)
                log.write("ide connected pid=\(pid)")
            }
        case "caret":
            caret.handleRawReply(line)
            caret.handleIDEReply(object)
        default:
            break
        }
    }

    private func handleCommand(_ arguments: [String], from connection: SocketConnection) {
        switch arguments.first {
        case "status":
            let payload: [String: Any] = [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "shells": sessions.values.map { ["pid": Int($0.pid), "shell": $0.shell] },
                "ides": caret.connectedIDEs.map(Int.init),
                "paused": paused,
                "accessibility": AXIsProcessTrusted(),
                "specs": GuruResources.specs.path,
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            connection.send(String(decoding: data, as: UTF8.self))
        case "rescan":
            engineQueue.async { [engine] in
                engine.rescan()
                DispatchQueue.main.async { connection.send("ok") }
            }
        case "caret":
            caret.probeIDEs { connection.send($0) }
        case "settings":
            settingsWindow.show()
            connection.send("ok")
        case "demo":
            let point = NSEvent.mouseLocation
            popup.setCaret(CGRect(x: point.x, y: point.y, width: 1, height: 18), key: "demo\(generation)")
            let request = EngineRequest(buffer: "git c", cursor: 5, cwd: "/", path: "")
            engineQueue.async { [engine] in
                let items = engine.suggest(request)
                DispatchQueue.main.async {
                    self.popup.show(items)
                    self.popup.model.move(1)
                    let frame = self.popup.captureRect
                    connection.send("\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if self.active?.popupVisible != true { self.popup.hide() } }
                }
            }
        case "quit":
            connection.send("ok")
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            connection.send("unknown")
        }
    }

    // MARK: Editing

    private func edit(_ session: ShellSession) {
        active = session
        generation += 1
        guard !paused else { return }
        let current = generation
        let request = EngineRequest(buffer: session.buffer, cursor: session.cursor, cwd: session.cwd,
                                    path: session.path, aliases: session.aliases)
        let word = Tokenizer.parse(String(session.buffer.prefix(session.cursor))).tokens.count
        if let dismissed = session.dismissedWord {
            if dismissed == word { return }
            session.dismissedWord = nil
        }
        engineQueue.async { [engine] in
            let items = engine.suggest(request)
            DispatchQueue.main.async { [weak self] in
                guard let self, current == self.generation, session === self.active else { return }
                self.present(items, session: session, word: word)
            }
        }
    }

    private func present(_ items: [Suggestion], session: ShellSession, word: Int) {
        // A shell in a background app (or a script driving a pty) must not pop a window over the user's work.
        let foreign = !headless && session.hostApp.map { $0.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier } ?? false
        guard !items.isEmpty, !foreign else {
            hide()
            if session.shell == "bash" { session.connection.send(Wire.join(["V", "0"])) }
            return
        }
        navigated = false
        if popup.isVisible || headless {
            popup.show(items)
            setVisible(true, session: session)
        }
        // bash reads one reply per edit, so it always gets an answer even when nothing changed.
        if session.shell == "bash" { session.connection.send(Wire.join(["V", session.popupVisible ? "1" : "0"])) }
        guard !headless else { return }
        let key = "\(session.connection.id):\(word)"
        let current = generation
        caret.locate { [weak self] rect in
            guard let self, session === self.active, current == self.generation else { return }
            self.popup.setCaret(rect, key: key)
            // The key hooks only take over once the user can actually see the list.
            if !self.popup.isVisible {
                self.popup.show(items)
                self.setVisible(true, session: session)
            }
        }
    }

    private func setVisible(_ visible: Bool, session: ShellSession) {
        guard session.popupVisible != visible else { return }
        session.popupVisible = visible
        if visible { keyTap.ensure() }
        session.connection.send(Wire.join(["V", visible ? "1" : "0"]))
    }

    private func hide() {
        popup.hide()
        if let active { setVisible(false, session: active) }
    }

    private func insertion(_ item: Suggestion, execute: Bool = false) -> String {
        Wire.join([execute ? "R" : "I", String(item.replace), item.insert, String(item.cursorBack)])
    }

    private func key(_ name: String, session: ShellSession) {
        guard session === active, popup.isVisible, let item = popup.model.current else {
            session.connection.send("P")
            return
        }
        switch name {
        case "up":
            popup.model.move(-1); navigated = true
            session.connection.send("N")
        case "down":
            popup.model.move(1); navigated = true
            session.connection.send("N")
        case "tab":
            session.connection.send(insertion(item))
        case "enter" where KeyTap.commandHeld:
            session.connection.send(insertion(item, execute: true))
        case "enter" where navigated || completes(item, session: session):
            session.connection.send(insertion(item, execute: enterAction == .execute))
        case "esc":
            session.dismissedWord = Tokenizer.parse(String(session.buffer.prefix(session.cursor))).tokens.count
            hide()
            session.connection.send("N")
        default:
            hide()
            session.connection.send("P")
        }
    }

    // Return must still run a finished line: an untouched top row only wins while it adds to the typed word.
    private func completes(_ item: Suggestion, session: ShellSession) -> Bool {
        guard item.replace > 0 else { return false }
        let typed = String(session.buffer.prefix(session.cursor).suffix(item.replace))
        return typed != item.insert.trimmingCharacters(in: .whitespaces)
    }

    private func pick(_ index: Int) {
        guard let session = active, popup.model.items.indices.contains(index) else { return }
        session.connection.send(insertion(popup.model.items[index]))
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        let pause = NSMenuItem(title: "Pause Suggestions", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause
        let rescan = NSMenuItem(title: "Rescan Commands", action: #selector(rescan), keyEquivalent: "")
        rescan.target = self
        menu.addItem(rescan)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if !headless { menu.addItem(updates.menuItem) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TermGuru", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func apply(_ settings: GuruSettings) {
        popup.model.maxRows = settings.maxRows
        popup.model.showDetails = settings.showDetails
        enterAction = settings.enterAction
        updates.automatic = settings.checkForUpdates
        engineQueue.async { [engine] in engine.useHistory = settings.historySuggestions }
    }

    private func setPaused(_ value: Bool) {
        paused = value
        pauseItem?.state = value ? .on : .off
        if value { hide() }
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settingsWindow.model.paused.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func rescan() {
        engineQueue.async { [engine] in engine.rescan() }
    }
}
