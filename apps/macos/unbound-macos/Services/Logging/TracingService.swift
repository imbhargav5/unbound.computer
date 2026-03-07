import Foundation
import Logging
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk

private let tracingLogger = Logging.Logger(label: "app.observability.trace")

private struct DictionaryTraceContextSetter: Setter {
    func set(carrier: inout [String: String], key: String, value: String) {
        carrier[key] = value
    }
}

private struct DictionaryTraceContextGetter: Getter {
    func get(carrier: [String: String], key: String) -> [String]? {
        guard let value = carrier[key], !value.isEmpty else {
            return nil
        }
        return [value]
    }
}

enum TracingService {
    private static let tracerName = "com.unbound.macos.ipc"
    private static let tracerVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String
    private static let propagator = W3CTraceContextPropagator()
    private static let lock = NSLock()
    private static var didBootstrap = false
    private static var tracerProvider: TracerProviderSdk?

    static func bootstrap() {
        lock.lock()
        defer { lock.unlock() }

        guard !didBootstrap else {
            return
        }
        didBootstrap = true

        guard let endpoint = normalizedOTLPTracesURL(from: Config.otlpEndpoint) else {
            return
        }

        let headers = Config.otlpHeaders
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
        let exporter = OtlpHttpTraceExporter(
            endpoint: endpoint,
            config: OtlpConfiguration(
                timeout: 10,
                compression: CompressionType.gzip,
                headers: headers.isEmpty ? nil : headers,
                exportAsJson: false
            )
        )
        let processor = BatchSpanProcessor(
            spanExporter: exporter,
            scheduleDelay: 1,
            exportTimeout: 10,
            maxQueueSize: 2048,
            maxExportBatchSize: 256
        )
        let tracerProvider = TracerProviderBuilder()
            .with(resource: resource())
            .with(sampler: sampler())
            .add(spanProcessor: processor)
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        Self.tracerProvider = tracerProvider

        tracingLogger.info(
            "OTLP trace export enabled for macOS app.",
            metadata: [
                "component": .string("observability"),
                "otlp_enabled": .stringConvertible(true),
                "otlp_base_url": .string(Config.otlpEndpoint?.absoluteString ?? ""),
                "otlp_traces_url": .string(endpoint.absoluteString)
            ]
        )
    }

    static func shutdown(timeout: TimeInterval = 2.0) {
        lock.lock()
        let provider = tracerProvider
        lock.unlock()

        provider?.forceFlush(timeout: timeout)
        provider?.shutdown()
    }

    static func withClientSpan<T>(
        method: String,
        requestId: String,
        sessionId: String?,
        operation: (Span, DaemonTraceContext?) async throws -> T
    ) async throws -> T {
        let span = startSpan(
            name: "daemon.\(method)",
            kind: .client,
            parent: nil,
            makeRoot: true,
            attributes: requestAttributes(method: method, requestId: requestId, sessionId: sessionId)
        )
        defer {
            span.end()
        }

        let context = traceContext(for: span.context)

        do {
            return try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
                try await operation(span, context)
            }
        } catch {
            record(error: error, on: span)
            throw error
        }
    }

    static func withRemoteReceiveSpan<T>(
        name: String,
        eventType: String,
        sessionId: String,
        remoteContext: DaemonTraceContext?,
        operation: (Span) throws -> T
    ) rethrows -> T {
        let span = startSpan(
            name: name,
            kind: .consumer,
            parent: spanContext(from: remoteContext),
            makeRoot: remoteContext == nil,
            attributes: [
                "ipc.event_type": .string(eventType),
                "ipc.session_id": .string(sessionId)
            ]
        )
        defer {
            span.end()
        }

        return try OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
            try operation(span)
        }
    }

    static func withChildSpan<T>(
        name: String,
        kind: SpanKind = .internal,
        requestId: String? = nil,
        sessionId: String? = nil,
        attributes: [String: AttributeValue] = [:],
        operation: (Span) throws -> T
    ) rethrows -> T {
        var resolvedAttributes = attributes
        if let requestId {
            resolvedAttributes["ipc.request_id"] = .string(requestId)
        }
        if let sessionId {
            resolvedAttributes["ipc.session_id"] = .string(sessionId)
        }

        let span = startSpan(
            name: name,
            kind: kind,
            parent: nil,
            makeRoot: false,
            attributes: resolvedAttributes
        )
        defer {
            span.end()
        }

        return try OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
            try operation(span)
        }
    }

    static func metadata(
        requestId: String? = nil,
        sessionId: String? = nil,
        span: Span? = nil
    ) -> Logging.Logger.Metadata {
        metadata(requestId: requestId, sessionId: sessionId, spanContext: span?.context)
    }

    static func metadata(
        requestId: String? = nil,
        sessionId: String? = nil,
        spanContext: SpanContext?
    ) -> Logging.Logger.Metadata {
        var metadata: Logging.Logger.Metadata = [:]

        if let requestId {
            metadata["request_id"] = .string(requestId)
        }
        if let sessionId {
            metadata["session_id"] = .string(sessionId)
        }
        if let spanContext, spanContext.isValid {
            metadata["trace_id"] = .string(spanContext.traceId.hexString)
            metadata["span_id"] = .string(spanContext.spanId.hexString)
        }

        return metadata
    }

    static func record(error: Error, on span: Span) {
        span.recordException(error)
        span.status = .error(description: error.localizedDescription)
    }

    static func traceContext(for spanContext: SpanContext) -> DaemonTraceContext? {
        guard spanContext.isValid else {
            return nil
        }

        var carrier: [String: String] = [:]
        propagator.inject(
            spanContext: spanContext,
            carrier: &carrier,
            setter: DictionaryTraceContextSetter()
        )

        guard let traceparent = carrier["traceparent"], !traceparent.isEmpty else {
            return nil
        }

        return DaemonTraceContext(
            traceparent: traceparent,
            tracestate: carrier["tracestate"]
        )
    }

    static func spanContext(from traceContext: DaemonTraceContext?) -> SpanContext? {
        guard let traceContext else {
            return nil
        }

        var carrier = ["traceparent": traceContext.traceparent]
        if let tracestate = traceContext.tracestate, !tracestate.isEmpty {
            carrier["tracestate"] = tracestate
        }

        return propagator.extract(
            carrier: carrier,
            getter: DictionaryTraceContextGetter()
        )
    }

    private static func tracer() -> Tracer {
        OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: tracerName,
            instrumentationVersion: tracerVersion
        )
    }

    private static func startSpan(
        name: String,
        kind: SpanKind,
        parent: SpanContext?,
        makeRoot: Bool,
        attributes: [String: AttributeValue]
    ) -> Span {
        let builder = tracer()
            .spanBuilder(spanName: name)
            .setSpanKind(spanKind: kind)

        if let parent {
            builder.setParent(parent)
        } else if makeRoot {
            builder.setNoParent()
        }

        for (key, value) in attributes {
            builder.setAttribute(key: key, value: value)
        }

        return builder.startSpan()
    }

    private static func requestAttributes(
        method: String,
        requestId: String,
        sessionId: String?
    ) -> [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [
            "ipc.method": .string(method),
            "ipc.request_id": .string(requestId),
            "rpc.system": .string("unix_socket")
        ]
        if let sessionId {
            attributes["ipc.session_id"] = .string(sessionId)
        }
        return attributes
    }

    private static func resource() -> Resource {
        var base = Resource()
        base.merge(
            other: Resource(
                attributes: [
                    "service.name": .string("macos"),
                    "service.namespace": .string("unbound"),
                    "service.version": .string(tracerVersion ?? "unknown"),
                    "deployment.environment.name": .string(Config.observabilityEnvironment)
                ]
            )
        )
        return base
    }

    private static func sampler() -> Sampler {
        let status = Config.resolvedObservabilityStatus
        switch status.mode {
        case .devVerbose:
            return Samplers.alwaysOn
        case .prodMetadataOnly:
            return Samplers.parentBased(root: Samplers.traceIdRatio(ratio: status.infoSampleRate))
        }
    }

    private static func normalizedOTLPTracesURL(from endpoint: URL?) -> URL? {
        guard let endpoint else {
            return nil
        }

        let base = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1/traces") {
            return endpoint
        }
        if base.hasSuffix("/v1/logs") {
            let prefix = String(base.dropLast("/v1/logs".count))
            return URL(string: "\(prefix)/v1/traces")
        }
        return URL(string: "\(base)/v1/traces")
    }
}
