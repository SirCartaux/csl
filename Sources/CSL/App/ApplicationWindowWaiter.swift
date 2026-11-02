import AppKit

/// Window-server metadata needs no screen capture or new accessibility prompt.
/// Read it away from the UI thread while an application is starting.
actor ApplicationWindowProbe {
    static let shared = ApplicationWindowProbe()

    func hasVisibleWindow(processID: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { Self.isVisibleApplicationWindow($0, processID: processID) }
    }

    nonisolated static func isVisibleApplicationWindow(_ info: [String: Any], processID: pid_t) -> Bool {
        guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              rect.width > 1, rect.height > 1 else { return false }
        return true
    }
}

// Like AppDelegate, this coordinator is owned and called by AppKit on main.
final class ApplicationWindowWaiter {
    struct ProcessState {
        let processID: pid_t
        let finishedLaunching: Bool
        let terminated: Bool
    }

    private var task: Task<Void, Never>?

    func wait(for application: NSRunningApplication, completion: @escaping (Bool) -> Void) {
        wait(state: {
            ProcessState(processID: application.processIdentifier,
                         finishedLaunching: application.isFinishedLaunching,
                         terminated: application.isTerminated)
        }, hasWindow: { pid in
            await ApplicationWindowProbe.shared.hasVisibleWindow(processID: pid)
        }, completion: completion)
    }

    /// A process being active or finished launching is insufficient: wait for
    /// its visible window. Windowless apps stay here until explicitly dismissed.
    func wait(state: @escaping () -> ProcessState,
              hasWindow: @escaping (pid_t) async -> Bool,
              interval: Duration = .milliseconds(120),
              completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                let current = state()
                if current.terminated { completion(false); return }
                if current.finishedLaunching {
                    let visible = await hasWindow(current.processID)
                    guard !Task.isCancelled else { return }
                    if state().terminated { completion(false); return }
                    if visible { completion(true); return }
                }
                do { try await Task.sleep(for: interval) }
                catch { return }
            }
        }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
