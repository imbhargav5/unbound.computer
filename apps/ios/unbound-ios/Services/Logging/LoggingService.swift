import Foundation
import Logging

enum LoggingService {
    private static let subsystem = "com.unbound.ios"

    static func bootstrap() {
        LoggingSystem.bootstrap { label in
            let category = label.split(separator: ".").dropFirst().first.map(String.init) ?? label
            let osLogHandler = OSLogHandler(subsystem: subsystem, category: category)
            let observabilityHandler = ObservabilityService.makeHandler(label: label)

            #if DEBUG
            if let observabilityHandler {
                return MultiplexLogHandler([
                    osLogHandler,
                    observabilityHandler,
                    ComponentColorLogHandler(label: label)
                ])
            }
            return MultiplexLogHandler([
                osLogHandler,
                ComponentColorLogHandler(label: label)
            ])
            #else
            if let observabilityHandler {
                return MultiplexLogHandler([
                    osLogHandler,
                    observabilityHandler
                ])
            }
            return osLogHandler
            #endif
        }
    }
}
