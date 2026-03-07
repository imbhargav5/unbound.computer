use daemon_ipc::TraceContext;
use opentelemetry::trace::TraceContextExt;
use std::future::Future;
use tokio::task::JoinHandle;
use tracing::Instrument;
use tracing_opentelemetry::OpenTelemetrySpanExt;

pub fn current_trace_context() -> Option<TraceContext> {
    let span_context = tracing::Span::current()
        .context()
        .span()
        .span_context()
        .clone();
    if !span_context.is_valid() {
        return None;
    }

    let traceparent = format!(
        "00-{}-{}-{:02x}",
        span_context.trace_id(),
        span_context.span_id(),
        span_context.trace_flags().to_u8()
    );

    let tracestate_header = span_context.trace_state().header();
    let tracestate = if tracestate_header.is_empty() {
        None
    } else {
        Some(tracestate_header)
    };

    Some(TraceContext {
        traceparent,
        tracestate,
    })
}

pub fn spawn_in_current_span<F>(future: F) -> JoinHandle<F::Output>
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    tokio::spawn(future.instrument(tracing::Span::current()))
}
