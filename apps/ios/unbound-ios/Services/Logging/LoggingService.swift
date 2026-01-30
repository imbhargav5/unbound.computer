import Foundation
import Logging

enum LoggingService {
    private static let subsystem = "com.unbound.ios"

    static func bootstrap() {
        LoggingSystem.bootstrap { label in
            let category = label.split(separator: ".").dropFirst().first.map(String.init) ?? label

            #if DEBUG
            return MultiplexLogHandler([
                OSLogHandler(subsystem: subsystem, category: category),
                ComponentColorLogHandler(label: label)
            ])
            #else
            return OSLogHandler(subsystem: subsystem, category: category)
            #endif
        }
    }
}
