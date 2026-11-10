import AppKit
import Darwin

public enum ProcessTree {
    public static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// The GUI app hosting a shell (terminal emulator or IDE), found by walking up the process tree.
    public static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current: pid_t? = pid
        var hops = 0
        while let candidate = current, hops < 12 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular {
                return app
            }
            current = parent(of: candidate)
            hops += 1
        }
        return nil
    }
}
