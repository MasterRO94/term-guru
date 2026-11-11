import SwiftUI
import GuruCore

final class SettingsModel: ObservableObject {
    @Published var settings = GuruSettings.load() { didSet { settings.save(); onChange?(settings) } }
    @Published var launchAtLogin = Installer.launchesAtLogin
    @Published var paused = false { didSet { onPause?(paused) } }
    @Published var aliases: [AliasEntry] = []
    @Published var checks: [DoctorCheck] = []
    @Published var checking = false

    // Aliases pane form state. Kept here, not in `@State`: from the macOS 27 SDK `@State` is a macro
    // whose plugin ships only with Xcode, so the Command Line Tools toolchain cannot expand it.
    @Published var aliasName = ""
    @Published var aliasCommand = ""
    @Published var aliasError: String?
    @Published var aliasSelection: String?

    var onChange: ((GuruSettings) -> Void)?
    var onPause: ((Bool) -> Void)?
    var onRescan: (() -> Void)?
    var onCheckUpdates: (() -> Void)?

    struct AliasEntry: Identifiable, Hashable {
        var name: String
        var value: String
        var id: String { name }
    }

    func reloadAliases() {
        aliases = AliasStore().list().map { AliasEntry(name: $0.name, value: $0.value) }
    }

    func addAlias(name: String, value: String) -> String? {
        do {
            try AliasStore().add(name: name, value: value)
            reloadAliases()
            return nil
        } catch { return "\(error)" }
    }

    func removeAlias(_ name: String) {
        try? AliasStore().remove(name: name)
        reloadAliases()
    }

    func runDoctor() {
        checking = true
        // Doctor queries this app over its own socket, so it must not run on the main queue.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Doctor.run()
            DispatchQueue.main.async {
                self.checks = result
                self.checking = false
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPane(model: model) }
            Tab("Aliases", systemImage: "link") { AliasesPane(model: model) }
            Tab("Diagnostics", systemImage: "stethoscope") { DiagnosticsPane(model: model) }
        }
        .frame(width: 560, height: 440)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { value in
                        try? Installer.setLaunchAtLogin(value)
                        model.launchAtLogin = Installer.launchesAtLogin
                    }
                ))
                Toggle("Pause suggestions", isOn: $model.paused)
            }
            Section {
                Stepper("Visible rows: \(model.settings.maxRows)", value: $model.settings.maxRows, in: 4...14)
                Toggle("Show description panel", isOn: $model.settings.showDetails)
                Picker("Description panel", selection: $model.settings.detailsPosition) {
                    Text("Beside the list").tag(DetailsPosition.side)
                    Text("Below the list").tag(DetailsPosition.below)
                }
                .disabled(!model.settings.showDetails)
            } header: {
                Text("Popup")
            } footer: {
                Text("⌘I switches the description between beside and below while the popup shows.")
            }
            Section {
                Picker("Return on a selected suggestion", selection: $model.settings.enterAction) {
                    Text("Inserts it").tag(EnterAction.insert)
                    Text("Runs it").tag(EnterAction.execute)
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("⌘Return always runs the selected suggestion. Return on an empty or already complete word runs the line as typed.")
            }
            Section {
                Toggle("Suggest commands from shell history", isOn: $model.settings.historySuggestions)
                LabeledContent("Commands and specs") {
                    Button("Rescan Now") { model.onRescan?() }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Rescan after installing new command-line tools. Same as `tgr rescan`.")
            }
            Section {
                Toggle("Check for new releases automatically", isOn: $model.settings.checkForUpdates)
                LabeledContent("Version \(GuruVersion.current)") {
                    Button("Check Now") { model.onCheckUpdates?() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("A new release is fetched into the source checkout, rebuilt and reinstalled. Same as `tgr update`.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AliasesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(model.aliases, selection: $model.aliasSelection) {
                TableColumn("Alias") { Text($0.name).font(.system(.body, design: .monospaced)) }
                    .width(min: 80, ideal: 110, max: 160)
                TableColumn("Command") { Text($0.value).font(.system(.body, design: .monospaced)).lineLimit(1) }
            }
            .overlay {
                if model.aliases.isEmpty {
                    ContentUnavailableView("No Aliases", systemImage: "link", description: Text("Add one below or run `tgr alias add gs 'git status'`."))
                }
            }
            HStack {
                TextField("Name", text: $model.aliasName).frame(width: 110)
                TextField("Command", text: $model.aliasCommand).onSubmit(add)
                Button("Add", action: add)
                    .disabled(model.aliasName.isEmpty || model.aliasCommand.isEmpty)
                Button("Remove", role: .destructive) {
                    if let selection = model.aliasSelection { model.removeAlias(selection) }
                    model.aliasSelection = nil
                }
                .disabled(model.aliasSelection == nil)
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            if let error = model.aliasError {
                Text(error).font(.callout).foregroundStyle(.red)
            } else {
                Text("Aliases load in open shells at their next prompt.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .onAppear { model.reloadAliases() }
    }

    private func add() {
        model.aliasError = model.addAlias(name: model.aliasName.trimmingCharacters(in: .whitespaces), value: model.aliasCommand)
        if model.aliasError == nil { model.aliasName = ""; model.aliasCommand = "" }
    }
}

private struct DiagnosticsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(check.level))
                        .foregroundStyle(color(check.level))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                        if !check.detail.isEmpty {
                            Text(check.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        if let fix = check.fix, check.level != .ok {
                            Text(fix).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Button("Check Again") { model.runDoctor() }
                    .disabled(model.checking)
                if model.checking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Open Accessibility Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(20)
        .onAppear { model.runDoctor() }
    }

    private func symbol(_ level: DoctorCheck.Level) -> String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .info: "info.circle"
        }
    }

    private func color(_ level: DoctorCheck.Level) -> Color {
        switch level {
        case .ok: .green
        case .warning: .orange
        case .failure: .red
        case .info: .secondary
        }
    }
}

final class SettingsWindowController {
    let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "TermGuru Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
