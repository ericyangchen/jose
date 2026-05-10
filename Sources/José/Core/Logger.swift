import Foundation
import OSLog

enum Logger {
    static let subsystem = "com.ericyangchen.jose"

    static let app = OSLog(subsystem: subsystem, category: "app")
    static let coordinator = OSLog(subsystem: subsystem, category: "coordinator")
    static let hotkey = OSLog(subsystem: subsystem, category: "hotkey")
    static let audio = OSLog(subsystem: subsystem, category: "audio")
    static let vad = OSLog(subsystem: subsystem, category: "vad")
    static let transcription = OSLog(subsystem: subsystem, category: "transcription")
    static let output = OSLog(subsystem: subsystem, category: "output")
    static let hud = OSLog(subsystem: subsystem, category: "hud")
    static let menubar = OSLog(subsystem: subsystem, category: "menubar")
    static let settings = OSLog(subsystem: subsystem, category: "settings")
    static let permissions = OSLog(subsystem: subsystem, category: "permissions")
    static let storage = OSLog(subsystem: subsystem, category: "storage")
    static let usage = OSLog(subsystem: subsystem, category: "usage")
}

extension OSLog {
    func debug(_ message: @autoclosure () -> String) {
        os_log(.debug, log: self, "%{public}s", message())
    }

    func info(_ message: @autoclosure () -> String) {
        os_log(.info, log: self, "%{public}s", message())
    }

    func warning(_ message: @autoclosure () -> String) {
        os_log(.default, log: self, "⚠️ %{public}s", message())
    }

    func error(_ message: @autoclosure () -> String) {
        os_log(.error, log: self, "❌ %{public}s", message())
    }
}
