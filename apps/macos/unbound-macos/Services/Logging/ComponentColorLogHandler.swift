import Foundation
import Logging

struct ComponentColorLogHandler: LogHandler {
    private let label: String
    private var stream: TextOutputStream

    var logLevel: Logger.Level = .debug
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    init(label: String, stream: TextOutputStream = StdoutStream()) {
        self.label = label
        self.stream = stream
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let color = Self.color(forLabel: label)
        let levelStr = Self.levelString(level)
        let timestamp = Self.timestamp()

        var stream = self.stream
        stream.write("\(color)[\(timestamp)] [\(label)] \(levelStr): \(message)\(ANSI.reset)\n")
    }

    private static func color(forLabel label: String) -> String {
        let prefix = label.split(separator: ".").prefix(2).joined(separator: ".")

        switch prefix {
        case _ where prefix.contains("network"): return ANSI.cyan
        case _ where prefix.contains("database"): return ANSI.green
        case _ where prefix.contains("sync"): return ANSI.yellow
        case _ where prefix.contains("ui"): return ANSI.magenta
        case _ where prefix.contains("auth"): return ANSI.blue
        case _ where prefix.contains("claude"): return ANSI.brightMagenta
        case _ where prefix.contains("relay"): return ANSI.brightCyan
        case _ where prefix.contains("outbox"): return ANSI.brightYellow
        case _ where prefix.contains("session"): return ANSI.brightGreen
        case _ where prefix.contains("device"): return ANSI.brightBlue
        case _ where prefix.contains("json"): return ANSI.brightRed
        default: return ANSI.gray
        }
    }

    private static func levelString(_ level: Logger.Level) -> String {
        switch level {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRIT"
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
        return formatter.string(from: Date())
    }
}

struct StdoutStream: TextOutputStream {
    private static let lock = NSLock()

    mutating func write(_ string: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        FileHandle.standardOutput.write(Data(string.utf8))
    }
}
