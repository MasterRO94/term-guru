import AppKit
import ApplicationServices
import GuruCore

/// Finds the text caret of the frontmost app in Cocoa screen coordinates (origin bottom-left).
final class CaretLocator {
    private var ides: [pid_t: SocketConnection] = [:]
    private var pending: ((CGRect) -> Void)?

    func registerIDE(pid: pid_t, connection: SocketConnection) { ides[pid] = connection }

    func unregister(_ connection: SocketConnection) {
        ides = ides.filter { $0.value !== connection }
    }

    var connectedIDEs: [pid_t] { Array(ides.keys) }

    private var probe: ((String) -> Void)?

    /// Diagnostic: asks every connected IDE and hands back the first raw answer.
    func probeIDEs(_ completion: @escaping (String) -> Void) {
        guard !ides.isEmpty else { completion("{\"error\":\"no IDE connected\"}"); return }
        probe = completion
        for ide in ides.values { ide.send(#"{"t":"caret?"}"#) }
    }

    func handleRawReply(_ line: String) {
        probe?(line)
        probe = nil
    }

    func locate(_ completion: @escaping (CGRect) -> Void) {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if let ide = ides[front.processIdentifier] {
            pending = completion
            ide.send(#"{"t":"caret?"}"#)
            // The terminal repaints after the shell echoes, so the first answer can be one cell behind.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { ide.send(#"{"t":"caret?"}"#) }
            return
        }
        if let rect = accessibilityCaret(pid: front.processIdentifier) ?? windowFallback(pid: front.processIdentifier) {
            completion(rect)
        }
    }

    func handleIDEReply(_ object: [String: Any]) {
        guard object["ok"] as? Bool == true,
              let x = (object["x"] as? NSNumber)?.doubleValue, let y = (object["y"] as? NSNumber)?.doubleValue,
              let w = (object["w"] as? NSNumber)?.doubleValue, let h = (object["h"] as? NSNumber)?.doubleValue
        else { return }
        pending?(Self.flip(CGRect(x: x, y: y, width: w, height: max(h, 14))))
    }

    /// AWT and Accessibility both use a top-left origin on the primary display.
    static func flip(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return (focused as! AXUIElement)
    }

    private func accessibilityCaret(pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted(), let element = focusedElement(pid: pid) else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue
        else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.height > 0, rect.height < 200 else { return nil }
        return Self.flip(rect)
    }

    /// Last resort when a terminal exposes no caret: pin the popup to the bottom-left of its window.
    private func windowFallback(pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue)
        var position = CGPoint.zero, size = CGSize.zero
        guard let positionValue, let sizeValue,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return Self.flip(CGRect(x: position.x + 24, y: position.y + size.height - 60, width: 2, height: 18))
    }
}
