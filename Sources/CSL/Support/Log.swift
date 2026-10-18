import Foundation
import os

/// Tiny logging helper. Enable with `CSL_DEBUG=1`.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["CSL_DEBUG"] == "1"
    private static let logger = Logger(subsystem: "com.henri.csl", category: "CSL")

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
        if let data = ("· " + text + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    static func always(_ message: String) {
        FileHandle.standardOutput.write((message + "\n").data(using: .utf8) ?? Data())
    }
}
