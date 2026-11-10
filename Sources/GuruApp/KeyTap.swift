import AppKit

/// Turns ⌘Return into a plain Return while the popup shows, because terminals keep ⌘Return for themselves.
/// The shell then reports an ordinary Enter and the coordinator sees ⌘ still held.
final class KeyTap {
    var isArmed: () -> Bool = { false }
    private var port: CFMachPort?

    static var commandHeld: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    }

    // Retried on demand: the Accessibility permission can be granted while the app runs.
    func ensure() {
        guard port == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if (keyCode == 36 || keyCode == 76), modifiers == .maskCommand, isArmed() {
            event.flags.remove(.maskCommand)
        }
        return Unmanaged.passUnretained(event)
    }
}
