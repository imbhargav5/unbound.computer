//! Custom JSON layer for structured logging.
//!
//! Produces clean JSONL output with all required fields:
//! - timestamp (RFC 3339)
//! - level (DEBUG, INFO, WARN, ERROR)
//! - service (from LogConfig)
//! - pid (process ID)
//! - target (module path)
//! - message
//! - fields (structured key-value pairs)

use chrono::Utc;
use serde::Serialize;
use std::collections::HashMap;
use std::fmt;
use std::io::Write;
use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::fmt::MakeWriter;
use tracing_subscriber::layer::Context;
use tracing_subscriber::registry::LookupSpan;
use tracing_subscriber::Layer;

use crate::remote::RemoteExporter;

/// A single structured log entry.
#[derive(Debug, Clone, Serialize)]
pub struct LogEntry {
    /// RFC 3339 timestamp
    pub timestamp: String,
    /// Log level
    pub level: String,
    /// Service name
    pub service: String,
    /// Process ID
    pub pid: u32,
    /// Target/subsystem (module path)
    pub target: String,
    /// Log message
    pub message: String,
    /// Structured fields
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub fields: HashMap<String, serde_json::Value>,
    /// Span context (if any)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub span: Option<String>,
    /// Source file
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    /// Source line
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<u32>,
}

/// Visitor that extracts fields from tracing events.
struct FieldVisitor {
    fields: HashMap<String, serde_json::Value>,
    message: Option<String>,
}

impl FieldVisitor {
    fn new() -> Self {
        Self {
            fields: HashMap::new(),
            message: None,
        }
    }
}

impl Visit for FieldVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn fmt::Debug) {
        let value_str = format!("{:?}", value);
        if field.name() == "message" {
            self.message = Some(value_str);
        } else {
            self.fields.insert(
                field.name().to_string(),
                serde_json::Value::String(value_str),
            );
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            self.message = Some(value.to_string());
        } else {
            self.fields.insert(
                field.name().to_string(),
                serde_json::Value::String(value.to_string()),
            );
        }
    }

    fn record_i64(&mut self, field: &Field, value: i64) {
        self.fields.insert(
            field.name().to_string(),
            serde_json::Value::Number(value.into()),
        );
    }

    fn record_u64(&mut self, field: &Field, value: u64) {
        self.fields.insert(
            field.name().to_string(),
            serde_json::Value::Number(value.into()),
        );
    }

    fn record_bool(&mut self, field: &Field, value: bool) {
        self.fields
            .insert(field.name().to_string(), serde_json::Value::Bool(value));
    }

    fn record_f64(&mut self, field: &Field, value: f64) {
        if let Some(n) = serde_json::Number::from_f64(value) {
            self.fields
                .insert(field.name().to_string(), serde_json::Value::Number(n));
        } else {
            self.fields.insert(
                field.name().to_string(),
                serde_json::Value::String(value.to_string()),
            );
        }
    }

    fn record_error(&mut self, field: &Field, value: &(dyn std::error::Error + 'static)) {
        self.fields.insert(
            field.name().to_string(),
            serde_json::Value::String(value.to_string()),
        );
    }
}

/// Custom JSON layer that produces clean JSONL output.
pub struct JsonLayer<W> {
    service_name: String,
    pid: u32,
    make_writer: W,
    remote_exporter: Option<RemoteExporter>,
}

impl<W> JsonLayer<W> {
    pub fn new(
        service_name: String,
        make_writer: W,
        remote_exporter: Option<RemoteExporter>,
    ) -> Self {
        Self {
            service_name,
            pid: std::process::id(),
            make_writer,
            remote_exporter,
        }
    }
}

impl<S, W> Layer<S> for JsonLayer<W>
where
    S: Subscriber + for<'a> LookupSpan<'a>,
    W: for<'writer> MakeWriter<'writer> + 'static,
{
    fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>) {
        // Extract fields and message
        let mut visitor = FieldVisitor::new();
        event.record(&mut visitor);

        // Get span context
        let span_name = ctx.event_span(event).map(|s| s.name().to_string());

        // Get metadata
        let metadata = event.metadata();

        // Build log entry
        let entry = LogEntry {
            timestamp: Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
            level: level_to_string(*metadata.level()),
            service: self.service_name.clone(),
            pid: self.pid,
            target: metadata.target().to_string(),
            message: visitor.message.unwrap_or_default(),
            fields: visitor.fields,
            span: span_name,
            file: metadata.file().map(|s| s.to_string()),
            line: metadata.line(),
        };

        // Serialize and write
        if let Ok(json) = serde_json::to_string(&entry) {
            let mut writer = self.make_writer.make_writer();
            let _ = writeln!(writer, "{}", json);
        }

        if let Some(exporter) = &self.remote_exporter {
            exporter.export(&entry);
        }
    }
}

fn level_to_string(level: Level) -> String {
    match level {
        Level::TRACE => "TRACE",
        Level::DEBUG => "DEBUG",
        Level::INFO => "INFO",
        Level::WARN => "WARN",
        Level::ERROR => "ERROR",
    }
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_entry_serialization() {
        let entry = LogEntry {
            timestamp: "2024-01-15T10:30:00.000000Z".to_string(),
            level: "INFO".to_string(),
            service: "daemon".to_string(),
            pid: 12345,
            target: "daemon_relay::connection".to_string(),
            message: "connected to relay".to_string(),
            fields: HashMap::new(),
            span: None,
            file: Some("src/connection.rs".to_string()),
            line: Some(42),
        };

        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"service\":\"daemon\""));
        assert!(json.contains("\"pid\":12345"));
    }
}
