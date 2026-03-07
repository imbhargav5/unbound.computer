use std::cell::Cell;
use std::sync::Arc;
use std::time::SystemTime;

use opentelemetry::logs::{LogRecord as _, Logger as _, Severity};
use opentelemetry::trace::TraceContextExt;
use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::layer::Context;
use tracing_subscriber::registry::LookupSpan;
use tracing_subscriber::Layer;

thread_local! {
    static OTEL_LOG_EXPORT_IN_PROGRESS: Cell<bool> = const { Cell::new(false) };
}

#[derive(Clone)]
pub struct OtlpLogLayer {
    logger: Arc<opentelemetry_sdk::logs::SdkLogger>,
}

impl OtlpLogLayer {
    pub fn new(logger: opentelemetry_sdk::logs::SdkLogger) -> Self {
        Self {
            logger: Arc::new(logger),
        }
    }
}

impl<S> Layer<S> for OtlpLogLayer
where
    S: Subscriber + for<'span> LookupSpan<'span>,
{
    fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>) {
        let metadata = event.metadata();
        if should_skip_target(metadata.target()) {
            return;
        }

        let Some(_guard) = ExportGuard::enter() else {
            return;
        };

        let mut visitor = EventVisitor::default();
        event.record(&mut visitor);

        let mut record = self.logger.create_log_record();
        let severity = severity_from_level(metadata.level());

        record.set_event_name("tracing.event");
        record.set_target(metadata.target().to_string());
        record.set_timestamp(SystemTime::now());
        record.set_severity_number(severity);
        record.set_severity_text(severity.name());
        record.set_body(
            visitor
                .message
                .unwrap_or_else(|| metadata.target().to_string())
                .into(),
        );

        if let Some(module_path) = metadata.module_path() {
            record.add_attribute("code.module_path", module_path.to_string());
        }
        if let Some(file) = metadata.file() {
            record.add_attribute("code.filepath", file.to_string());
        }
        if let Some(line) = metadata.line() {
            record.add_attribute("code.lineno", i64::from(line));
        }
        if let Some(span) = ctx.event_span(event) {
            record.add_attribute("tracing.current_span", span.name().to_string());
        }
        if let Some(scope) = ctx.event_scope(event) {
            let span_path = scope
                .from_root()
                .map(|span| span.name())
                .collect::<Vec<_>>()
                .join(" > ");
            if !span_path.is_empty() {
                record.add_attribute("tracing.span_path", span_path);
            }
        }

        for (key, value) in visitor.attributes {
            record.add_attribute(key, value);
        }

        let span_context = tracing::Span::current()
            .context()
            .span()
            .span_context()
            .clone();
        if span_context.is_valid() {
            record.set_trace_context(
                span_context.trace_id(),
                span_context.span_id(),
                Some(span_context.trace_flags()),
            );
        }

        self.logger.emit(record);
    }
}

#[derive(Default)]
struct EventVisitor {
    attributes: Vec<(String, opentelemetry::logs::AnyValue)>,
    message: Option<String>,
}

impl EventVisitor {
    fn push_attribute(&mut self, field: &Field, value: opentelemetry::logs::AnyValue) {
        if field.name() == "message" {
            self.message = Some(any_value_to_string(&value));
            return;
        }

        self.attributes.push((field.name().to_string(), value));
    }
}

impl Visit for EventVisitor {
    fn record_bool(&mut self, field: &Field, value: bool) {
        self.push_attribute(field, value.into());
    }

    fn record_f64(&mut self, field: &Field, value: f64) {
        self.push_attribute(field, value.into());
    }

    fn record_i64(&mut self, field: &Field, value: i64) {
        self.push_attribute(field, value.into());
    }

    fn record_u64(&mut self, field: &Field, value: u64) {
        if let Ok(value) = i64::try_from(value) {
            self.push_attribute(field, value.into());
        } else {
            self.push_attribute(field, value.to_string().into());
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        self.push_attribute(field, value.to_string().into());
    }

    fn record_error(&mut self, field: &Field, value: &(dyn std::error::Error + 'static)) {
        self.push_attribute(field, value.to_string().into());
    }

    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        self.push_attribute(field, format!("{value:?}").into());
    }
}

struct ExportGuard;

impl ExportGuard {
    fn enter() -> Option<Self> {
        OTEL_LOG_EXPORT_IN_PROGRESS.with(|flag| {
            if flag.get() {
                None
            } else {
                flag.set(true);
                Some(Self)
            }
        })
    }
}

impl Drop for ExportGuard {
    fn drop(&mut self) {
        OTEL_LOG_EXPORT_IN_PROGRESS.with(|flag| flag.set(false));
    }
}

fn severity_from_level(level: &Level) -> Severity {
    match *level {
        Level::TRACE => Severity::Trace,
        Level::DEBUG => Severity::Debug,
        Level::INFO => Severity::Info,
        Level::WARN => Severity::Warn,
        Level::ERROR => Severity::Error,
    }
}

fn should_skip_target(target: &str) -> bool {
    matches_target_prefix(
        target,
        &[
            "opentelemetry",
            "opentelemetry_sdk",
            "opentelemetry_otlp",
            "tracing_opentelemetry",
            "reqwest",
            "hyper",
            "hyper_util",
            "h2",
            "tower",
        ],
    )
}

fn matches_target_prefix(target: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|prefix| target.starts_with(prefix))
}

fn any_value_to_string(value: &opentelemetry::logs::AnyValue) -> String {
    match value {
        opentelemetry::logs::AnyValue::Int(value) => value.to_string(),
        opentelemetry::logs::AnyValue::Double(value) => value.to_string(),
        opentelemetry::logs::AnyValue::String(value) => value.to_string(),
        opentelemetry::logs::AnyValue::Boolean(value) => value.to_string(),
        opentelemetry::logs::AnyValue::Bytes(value) => format!("{value:?}"),
        opentelemetry::logs::AnyValue::ListAny(value) => format!("{value:?}"),
        opentelemetry::logs::AnyValue::Map(value) => format!("{value:?}"),
        _ => format!("{value:?}"),
    }
}
