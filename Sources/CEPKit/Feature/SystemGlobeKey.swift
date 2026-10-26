import Foundation

/// Reads and writes the system-wide Fn/Globe key preference.
/// 0 = do nothing, 1 = change input source, 2 = show emoji & symbols,
/// 3 = start dictation. Absent means the system default (2).
enum SystemGlobeKey {
    static func usageType() -> Int {
        let key = "AppleFnUsageType" as CFString
        let application = "com.apple.HIToolbox" as CFString
        guard let value = CFPreferencesCopyAppValue(key, application) else { return 2 }
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "do nothing": return 0
            case "change input source": return 1
            case "show emoji & symbols", "show emoji and symbols": return 2
            case "start dictation": return 3
            default: return 2
            }
        }
        return 2
    }

    @discardableResult
    static func setToDoNothing() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.HIToolbox", "AppleFnUsageType", "-int", "0"]
        do {
            try process.run()
            process.waitUntilExit()
            CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
            return process.terminationStatus == 0
        } catch {
            Log.debug("could not write AppleFnUsageType: \(error)")
            return false
        }
    }
}
