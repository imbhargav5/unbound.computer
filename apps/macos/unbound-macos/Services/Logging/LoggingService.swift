import Foundation
import Logging

struct ObservabilityStartupEvent {
    let level: Logger.Level
    let message: String
    let metadata: Logger.Metadata
}

enum LoggingService {
    private static let subsystem = "com.unbound.macos"

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

        TracingService.bootstrap()
        emitObservabilityStartupStatus()
    }

    @discardableResult
    static func flush(timeout: TimeInterval = 2.0) -> Bool {
        ObservabilityService.flush(timeout: timeout)
    }

    nonisolated static func makeObservabilityStartupEvent(
        status: ResolvedObservabilityStatus
    ) -> ObservabilityStartupEvent {
        var metadata = status.metadata
        metadata["component"] = .string("observability")
        metadata["event_code"] = .string("macos.observability.startup")

        if status.otlpEnabled {
            return ObservabilityStartupEvent(
                level: .info,
                message: "OTLP log export enabled for macOS app.",
                metadata: metadata
            )
        }

        return ObservabilityStartupEvent(
            level: .warning,
            message: "OTLP log export disabled for macOS app. Set UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT in Xcode Run environment variables or via build-config/Info.plist injection to send logs to Signoz.",
            metadata: metadata
        )
    }

    private static func emitObservabilityStartupStatus() {
        let event = makeObservabilityStartupEvent(status: Config.resolvedObservabilityStatus)
        let logger = Logger(label: "app.observability")

        switch event.level {
        case .trace:
            logger.trace("\(event.message)", metadata: event.metadata)
        case .debug:
            logger.debug("\(event.message)", metadata: event.metadata)
        case .info:
            logger.info("\(event.message)", metadata: event.metadata)
        case .notice:
            logger.notice("\(event.message)", metadata: event.metadata)
        case .warning:
            logger.warning("\(event.message)", metadata: event.metadata)
        case .error:
            logger.error("\(event.message)", metadata: event.metadata)
        case .critical:
            logger.critical("\(event.message)", metadata: event.metadata)
        }
    }
}
