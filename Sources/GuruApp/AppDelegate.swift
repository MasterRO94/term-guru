import AppKit
import GuruCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: Coordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = Coordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
