use crate::compatibility;
use std::collections::HashMap;
use std::future::Future;
use tauri::async_runtime::JoinHandle;
use tracing::Instrument;
use uuid::Uuid;

use ::observability::{
    force_flush as otel_force_flush, init_with_config, shutdown as otel_shutdown, LogConfig,
    LogFormat, ObservabilityMode, OtlpConfig, OtlpSampler,
};

const DEFAULT_DEV_TRACE_RATIO: f64 = 1.0;
const DEFAULT_PROD_TRACE_RATIO: f64 = 0.05;
const SERVICE_NAME: &str = "desktop";

pub fn init() {
    let mode = parse_mode_from_env();
    let default_sampler = match mode {
        ObservabilityMode::DevVerbose => OtlpSampler::AlwaysOn,
        ObservabilityMode::ProdLight => OtlpSampler::ParentBasedTraceIdRatio,
    };
    let default_ratio = match mode {
        ObservabilityMode::DevVerbose => DEFAULT_DEV_TRACE_RATIO,
        ObservabilityMode::ProdLight => DEFAULT_PROD_TRACE_RATIO,
    };

    let otlp = std::env::var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT")
        .ok()
        .and_then(non_empty)
        .map(|endpoint| OtlpConfig {
            endpoint,
            headers: parse_headers_from_env(),
            sampler: parse_sampler_from_env().unwrap_or(default_sampler),
            sampler_arg: parse_ratio_from_env("UNBOUND_OTEL_TRACES_SAMPLER_ARG", default_ratio),
        });

    let log_format = parse_log_format_from_env().unwrap_or_else(|| match mode {
        ObservabilityMode::DevVerbose => LogFormat::Pretty,
        ObservabilityMode::ProdLight => LogFormat::Json,
    });

    let environment = match mode {
        ObservabilityMode::DevVerbose => "development".to_string(),
        ObservabilityMode::ProdLight => "production".to_string(),
    };

    let runtime_paths = compatibility::resolve_runtime_paths();
    init_with_config(LogConfig {
        service_name: SERVICE_NAME.to_string(),
        default_level: default_level().to_string(),
        log_path: Some(runtime_paths.base_dir.join("logs").join("desktop.jsonl")),
        also_stderr: true,
        mode,
        log_format,
        environment,
        otlp,
        ..Default::default()
    });

    tracing::info!(
        service = SERVICE_NAME,
        base_dir = %runtime_paths.base_dir.display(),
        socket_path = %runtime_paths.socket_path.display(),
        app_version = env!("CARGO_PKG_VERSION"),
        "desktop observability bootstrapped"
    );
}

pub fn shutdown() {
    force_flush();
    otel_shutdown();
}

pub fn force_flush() {
    otel_force_flush();
}

pub fn command_span(operation: &str, session_id: Option<&str>) -> tracing::Span {
    let request_id = Uuid::new_v4().to_string();
    let feature = feature_for_operation(operation);
    let span = tracing::info_span!(
        "desktop.command",
        operation = %operation,
        feature = %feature,
        request.id = %request_id,
        session.id = tracing::field::Empty,
        result = tracing::field::Empty
    );

    if let Some(session_id) = session_id.filter(|value| !value.is_empty()) {
        span.record("session.id", &tracing::field::display(session_id));
    }

    span
}

pub async fn in_command_span<T, F>(
    operation: &str,
    session_id: Option<&str>,
    future: F,
) -> Result<T, String>
where
    F: Future<Output = Result<T, String>>,
{
    let operation = operation.to_string();
    let span = command_span(operation.as_str(), session_id);
    let operation_for_log = operation.clone();
    async move {
        let result = future.await;
        match &result {
            Ok(_) => {
                tracing::Span::current().record("result", &tracing::field::display("ok"));
            }
            Err(error) => {
                tracing::Span::current().record("result", &tracing::field::display("error"));
                tracing::error!(
                    error = %error,
                    operation = %operation_for_log,
                    "desktop command failed"
                );
            }
        }
        result
    }
    .instrument(span)
    .await
}

pub fn spawn_in_current_span<F>(future: F) -> JoinHandle<F::Output>
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    tauri::async_runtime::spawn(future.instrument(tracing::Span::current()))
}

fn default_level() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "info"
    }
}

fn feature_for_operation(operation: &str) -> String {
    operation
        .split('.')
        .next()
        .filter(|value| !value.is_empty())
        .unwrap_or("desktop")
        .to_string()
}

fn parse_mode_from_env() -> ObservabilityMode {
    let value = std::env::var("UNBOUND_ENV")
        .ok()
        .and_then(non_empty)
        .unwrap_or_else(|| "dev".to_string())
        .to_ascii_lowercase();

    match value.as_str() {
        "prod" | "production" => ObservabilityMode::ProdLight,
        _ => ObservabilityMode::DevVerbose,
    }
}

fn parse_log_format_from_env() -> Option<LogFormat> {
    let value = std::env::var("UNBOUND_LOG_FORMAT")
        .ok()
        .and_then(non_empty)?
        .to_ascii_lowercase();

    match value.as_str() {
        "pretty" => Some(LogFormat::Pretty),
        "json" => Some(LogFormat::Json),
        _ => None,
    }
}

fn parse_sampler_from_env() -> Option<OtlpSampler> {
    let value = std::env::var("UNBOUND_OTEL_SAMPLER")
        .ok()
        .and_then(non_empty)?
        .to_ascii_lowercase();

    match value.as_str() {
        "always_on" => Some(OtlpSampler::AlwaysOn),
        "parentbased_traceidratio" => Some(OtlpSampler::ParentBasedTraceIdRatio),
        _ => None,
    }
}

fn parse_headers_from_env() -> HashMap<String, String> {
    let mut headers = HashMap::new();

    let Some(raw) = std::env::var("UNBOUND_OTEL_HEADERS")
        .ok()
        .and_then(non_empty)
    else {
        return headers;
    };

    for pair in raw.split(',') {
        let mut parts = pair.splitn(2, '=');
        let key = parts.next().map(str::trim).unwrap_or_default();
        let value = parts.next().map(str::trim).unwrap_or_default();

        if !key.is_empty() && !value.is_empty() {
            headers.insert(key.to_string(), value.to_string());
        }
    }

    headers
}

fn parse_ratio_from_env(name: &str, fallback: f64) -> f64 {
    std::env::var(name)
        .ok()
        .and_then(non_empty)
        .and_then(|raw| raw.parse::<f64>().ok())
        .map(|ratio| ratio.clamp(0.0, 1.0))
        .unwrap_or(fallback)
}

fn non_empty(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}
