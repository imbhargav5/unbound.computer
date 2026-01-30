import Foundation
import Logging
import os.log

struct OSLogHandler: LogHandler {
    private let osLog: OSLog
    let label: String

    var logLevel: Logging.Logger.Level = .info
    var metadata: Logging.Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    init(subsystem: String, category: String) {
        self.label = "\(subsystem).\(category)"
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let osLogType: OSLogType = {
            switch level {
            case .trace, .debug: return .debug
            case .info, .notice: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }()

        os_log("%{public}@", log: osLog, type: osLogType, message.description)
    }
}
