import CryptoKit
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

enum UserIntentSource: String, Sendable {
    case sidebar
    case autoSelectFirst = "auto_select_first"
    case createSession = "create_session"
    case addRepository = "add_repository"
    case createTerminalTab = "create_terminal_tab"
    case agentRuns = "agent_runs"
    case toolbar
    case keyboardShortcut = "keyboard_shortcut"
    case unknown
}

enum TracingService {
    final class Scope: @unchecked Sendable {
        fileprivate let span: Span
        let operation: String
        let attemptId: String
        let source: String?
        let startedAt: CFAbsoluteTime

        private let lock = NSLock()
        private var ended = false

        fileprivate init(
            span: Span,
            operation: String,
            attemptId: String,
            source: String?
        ) {
            self.span = span
            self.operation = operation
            self.attemptId = attemptId
            self.source = source
            self.startedAt = CFAbsoluteTimeGetCurrent()
        }

        var context: SpanContext {
            span.context
        }

        func setAttribute(_ key: String, value: AttributeValue) {
            lock.lock()
            defer { lock.unlock() }

            guard !ended else { return }
            span.setAttribute(key: key, value: value)
        }

        func setAttributes(_ attributes: [String: AttributeValue]) {
            lock.lock()
            defer { lock.unlock() }

            guard !ended else { return }
            for (key, value) in attributes {
                span.setAttribute(key: key, value: value)
            }
        }

        fileprivate func end(
            result: String? = nil,
            attributes: [String: AttributeValue] = [:],
            error: Error? = nil
        ) {
            lock.lock()
            defer { lock.unlock() }

            guard !ended else { return }
            ended = true

            if let result {
                span.setAttribute(key: "result", value: .string(result))
            }
            for (key, value) in attributes {
                span.setAttribute(key: key, value: value)
            }
            if let error {
                TracingService.record(error: error, on: span)
            }
            span.end()
        }
    }

    private enum IntentScopeContext {
        @TaskLocal static var current: Scope?
    }

    private static let tracerName = "com.unbound.macos.ipc"
    private static let tracerVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String
    private static let propagator = W3CTraceContextPropagator()
    private static let lock = NSLock()
    private static var didBootstrap = false
    private static var tracerProvider: TracerProviderSdk?

    static var currentIntentScope: Scope? {
        IntentScopeContext.current
    }

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

    static func hashIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        if rawValue.lowercased().hasPrefix("sha256:") {
            return rawValue.lowercased()
        }

        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    static func withUserIntentRoot<T>(
        name: String,
        source: UserIntentSource = .unknown,
        attributes: [String: AttributeValue] = [:],
        operation: (Scope) async throws -> T
    ) async rethrows -> T {
        let scope = startUserIntentScope(
            name: name,
            source: source,
            parentScope: nil,
            attributes: attributes
        )

        do {
            let result = try await withActivatedScope(scope) {
                try await operation(scope)
            }
            endScope(scope)
            return result
        } catch {
            endScope(scope, result: "error", error: error)
            throw error
        }
    }

    static func withUserIntentRootIfNeeded<T>(
        name: String,
        source: UserIntentSource = .unknown,
        attributes: [String: AttributeValue] = [:],
        operation: (Scope?) async throws -> T
    ) async rethrows -> T {
        if let currentIntentScope {
            return try await operation(currentIntentScope)
        }

        return try await withUserIntentRoot(
            name: name,
            source: source,
            attributes: attributes
        ) { scope in
            try await operation(scope)
        }
    }

    static func startUserIntentScope(
        name: String,
        source: UserIntentSource = .unknown,
        parentScope: Scope? = nil,
        attributes: [String: AttributeValue] = [:]
    ) -> Scope {
        let attemptId = UUID().uuidString.lowercased()
        var resolvedAttributes = attributes
        resolvedAttributes["operation"] = .string(name)
        resolvedAttributes["attempt_id"] = .string(attemptId)
        resolvedAttributes["result"] = .string("in_progress")
        resolvedAttributes["selection.source"] = .string(source.rawValue)

        let span = startSpan(
            name: name,
            kind: .internal,
            parent: parentScope?.context,
            makeRoot: parentScope == nil,
            attributes: resolvedAttributes
        )
        return Scope(
            span: span,
            operation: name,
            attemptId: attemptId,
            source: source.rawValue
        )
    }

    static func startChildScope(
        name: String,
        parentScope: Scope,
        kind: SpanKind = .internal,
        requestId: String? = nil,
        sessionId: String? = nil,
        attributes: [String: AttributeValue] = [:]
    ) -> Scope {
        var resolvedAttributes = attributes
        resolvedAttributes["attempt_id"] = .string(parentScope.attemptId)
        resolvedAttributes["root.operation"] = .string(parentScope.operation)
        if let requestId {
            resolvedAttributes["ipc.request_id"] = .string(requestId)
        }
        if let sessionId {
            resolvedAttributes["ipc.session_id"] = .string(sessionId)
        }

        let span = startSpan(
            name: name,
            kind: kind,
            parent: parentScope.context,
            makeRoot: false,
            attributes: resolvedAttributes
        )
        return Scope(
            span: span,
            operation: parentScope.operation,
            attemptId: parentScope.attemptId,
            source: parentScope.source
        )
    }

    static func withActivatedScope<T>(
        _ scope: Scope,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await IntentScopeContext.$current.withValue(scope) {
            try await OpenTelemetry.instance.contextProvider.withActiveSpan(scope.span) {
                try await operation()
            }
        }
    }

    static func endScope(
        _ scope: Scope,
        result: String = "success",
        attributes: [String: AttributeValue] = [:],
        error: Error? = nil
    ) {
        var resolvedAttributes = attributes
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - scope.startedAt) * 1_000)
        resolvedAttributes["duration.ms"] = .int(durationMs)
        scope.end(result: result, attributes: resolvedAttributes, error: error)
    }

    static func cancelScope(
        _ scope: Scope,
        attributes: [String: AttributeValue] = [:]
    ) {
        endScope(scope, result: "cancelled", attributes: attributes)
    }

    static func withClientSpan<T>(
        method: String,
        requestId: String,
        sessionId: String?,
        parentScope: Scope? = nil,
        attributes: [String: AttributeValue] = [:],
        operation: (Span, DaemonTraceContext?) async throws -> T
    ) async throws -> T {
        let resolvedParentScope = parentScope ?? currentIntentScope
        var resolvedAttributes = requestAttributes(method: method, requestId: requestId, sessionId: sessionId)
        for (key, value) in attributes {
            resolvedAttributes[key] = value
        }
        if let resolvedParentScope {
            resolvedAttributes["attempt_id"] = .string(resolvedParentScope.attemptId)
            resolvedAttributes["root.operation"] = .string(resolvedParentScope.operation)
        }

        let span = startSpan(
            name: "daemon.\(method)",
            kind: .client,
            parent: resolvedParentScope?.context,
            makeRoot: resolvedParentScope == nil && activeSpanContext() == nil,
            attributes: resolvedAttributes
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
        parentScope: Scope? = nil,
        attributes: [String: AttributeValue] = [:],
        operation: (Span) throws -> T
    ) rethrows -> T {
        let resolvedParentScope = parentScope ?? currentIntentScope
        var resolvedAttributes = attributes
        if let requestId {
            resolvedAttributes["ipc.request_id"] = .string(requestId)
        }
        if let sessionId {
            resolvedAttributes["ipc.session_id"] = .string(sessionId)
        }
        if let resolvedParentScope {
            resolvedAttributes["attempt_id"] = .string(resolvedParentScope.attemptId)
            resolvedAttributes["root.operation"] = .string(resolvedParentScope.operation)
        }

        let span = startSpan(
            name: name,
            kind: kind,
            parent: resolvedParentScope?.context,
            makeRoot: resolvedParentScope == nil && activeSpanContext() == nil,
            attributes: resolvedAttributes
        )
        defer {
            span.end()
        }

        return try OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
            try operation(span)
        }
    }

    static func withChildSpanAsync<T>(
        name: String,
        kind: SpanKind = .internal,
        requestId: String? = nil,
        sessionId: String? = nil,
        parentScope: Scope? = nil,
        attributes: [String: AttributeValue] = [:],
        operation: (Span) async throws -> T
    ) async rethrows -> T {
        let resolvedParentScope = parentScope ?? currentIntentScope
        var resolvedAttributes = attributes
        if let requestId {
            resolvedAttributes["ipc.request_id"] = .string(requestId)
        }
        if let sessionId {
            resolvedAttributes["ipc.session_id"] = .string(sessionId)
        }
        if let resolvedParentScope {
            resolvedAttributes["attempt_id"] = .string(resolvedParentScope.attemptId)
            resolvedAttributes["root.operation"] = .string(resolvedParentScope.operation)
        }

        let span = startSpan(
            name: name,
            kind: kind,
            parent: resolvedParentScope?.context,
            makeRoot: resolvedParentScope == nil && activeSpanContext() == nil,
            attributes: resolvedAttributes
        )
        defer {
            span.end()
        }

        return try await OpenTelemetry.instance.contextProvider.withActiveSpan(span) {
            try await operation(span)
        }
    }

    static func metadata(
        requestId: String? = nil,
        sessionId: String? = nil,
        scope: Scope? = nil,
        span: Span? = nil
    ) -> Logging.Logger.Metadata {
        metadata(
            requestId: requestId,
            sessionId: sessionId,
            scope: scope,
            spanContext: span?.context
        )
    }

    static func metadata(
        requestId: String? = nil,
        sessionId: String? = nil,
        scope: Scope? = nil,
        spanContext: SpanContext?
    ) -> Logging.Logger.Metadata {
        var metadata: Logging.Logger.Metadata = [:]
        let resolvedScope = scope ?? currentIntentScope

        if let requestId {
            metadata["request_id"] = .string(requestId)
        }
        if let sessionId {
            metadata["session_id"] = .string(sessionId)
        }
        if let resolvedScope {
            metadata["attempt_id"] = .string(resolvedScope.attemptId)
            metadata["operation"] = .string(resolvedScope.operation)
            if let source = resolvedScope.source {
                metadata["selection_source"] = .string(source)
            }
        }
        let resolvedSpanContext = spanContext ?? resolvedScope?.context
        if let resolvedSpanContext, resolvedSpanContext.isValid {
            metadata["trace_id"] = .string(resolvedSpanContext.traceId.hexString)
            metadata["span_id"] = .string(resolvedSpanContext.spanId.hexString)
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

    private static func activeSpanContext() -> SpanContext? {
        guard let activeSpan = OpenTelemetry.instance.contextProvider.activeSpan else {
            return nil
        }

        let spanContext = activeSpan.context
        return spanContext.isValid ? spanContext : nil
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
        if let override = Config.otlpSamplerOverride {
            switch override {
            case .alwaysOn:
                return Samplers.alwaysOn
            case let .parentBasedTraceIdRatio(ratio):
                return Samplers.parentBased(root: Samplers.traceIdRatio(ratio: ratio))
            }
        }

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
