mod dev;
mod otel_logs;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

use dev::{default_log_path, WriterFactory};
use opentelemetry::global;
use opentelemetry::logs::LoggerProvider as _;
use opentelemetry::trace::TracerProvider as _;
use opentelemetry::KeyValue;
use opentelemetry_otlp::LogExporter;
use opentelemetry_otlp::{Protocol, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::logs::log_processor_with_async_runtime::BatchLogProcessor as AsyncBatchLogProcessor;
use opentelemetry_sdk::logs::SdkLoggerProvider;
use opentelemetry_sdk::trace::{BatchSpanProcessor, SdkTracerProvider};
use opentelemetry_sdk::{runtime, trace, Resource};
use otel_logs::OtlpLogLayer;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{fmt, EnvFilter};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ObservabilityMode {
    #[default]
    DevVerbose,
    ProdLight,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LogFormat {
    #[default]
    Pretty,
    Json,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum OtlpSampler {
    AlwaysOn,
    ParentBasedTraceIdRatio,
}

impl Default for OtlpSampler {
    fn default() -> Self {
        Self::AlwaysOn
    }
}

#[derive(Debug, Clone)]
pub struct OtlpConfig {
    pub endpoint: String,
    pub headers: HashMap<String, String>,
    pub sampler: OtlpSampler,
    pub sampler_arg: f64,
}

impl Default for OtlpConfig {
    fn default() -> Self {
        Self {
            endpoint: "http://localhost:4318".to_string(),
            headers: HashMap::new(),
            sampler: OtlpSampler::AlwaysOn,
            sampler_arg: 1.0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct LogConfig {
    pub service_name: String,
    pub default_level: String,
    pub log_path: Option<PathBuf>,
    pub also_stderr: bool,
    pub mode: ObservabilityMode,
    pub log_format: LogFormat,
    pub environment: String,
    pub otlp: Option<OtlpConfig>,
}

static TRACER_PROVIDER: OnceLock<SdkTracerProvider> = OnceLock::new();
static LOGGER_PROVIDER: OnceLock<SdkLoggerProvider> = OnceLock::new();
static OBSERVABILITY_INITIALIZED: AtomicBool = AtomicBool::new(false);
static OBSERVABILITY_DUPLICATE_INIT_WARNED: AtomicBool = AtomicBool::new(false);
static OBSERVABILITY_SHUTDOWN: AtomicBool = AtomicBool::new(false);

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            service_name: "unknown".to_string(),
            default_level: "info".to_string(),
            log_path: None,
            also_stderr: true,
            mode: ObservabilityMode::DevVerbose,
            log_format: LogFormat::Pretty,
            environment: "development".to_string(),
            otlp: None,
        }
    }
}

pub fn init(service_name: &str) {
    init_with_config(LogConfig {
        service_name: service_name.to_string(),
        ..Default::default()
    });
}

pub fn init_with_config(config: LogConfig) {
    if OBSERVABILITY_INITIALIZED.swap(true, Ordering::SeqCst) {
        if !OBSERVABILITY_DUPLICATE_INIT_WARNED.swap(true, Ordering::SeqCst) {
            eprintln!(
                "[observability] init_with_config called more than once; reusing existing providers and subscriber"
            );
        }
        return;
    }
    OBSERVABILITY_SHUTDOWN.store(false, Ordering::SeqCst);

    let has_otlp = config.otlp.is_some();
    let tracer = match config.otlp.as_ref() {
        Some(otlp) => {
            let t = init_otel_tracer(&config, otlp);
            if t.is_some() {
                eprintln!(
                    "[observability] OTLP tracer initialized, endpoint={}",
                    otlp.endpoint
                );
            } else {
                eprintln!("[observability] OTLP tracer FAILED to initialize");
            }
            t
        }
        None => {
            if has_otlp {
                eprintln!("[observability] OTLP config present but tracer returned None");
            }
            None
        }
    };
    let otel_log_layer = match config.otlp.as_ref() {
        Some(otlp) => {
            let layer = init_otel_log_layer(&config, otlp);
            if layer.is_some() {
                eprintln!(
                    "[observability] OTLP log exporter initialized, endpoint={}",
                    otlp.endpoint
                );
            } else {
                eprintln!("[observability] OTLP log exporter FAILED to initialize");
            }
            layer
        }
        None => None,
    };

    let env_filter = build_env_filter(&config.default_level);

    match config.mode {
        ObservabilityMode::DevVerbose => {
            init_dev_subscriber(config, env_filter, tracer, otel_log_layer)
        }
        ObservabilityMode::ProdLight => {
            init_prod_subscriber(config, env_filter, tracer, otel_log_layer)
        }
    }
}

fn build_env_filter(default_level: &str) -> EnvFilter {
    EnvFilter::new(resolve_env_filter_directive(default_level))
}

fn resolve_env_filter_directive(default_level: &str) -> String {
    if let Some(directive) = parse_env_filter_var("UNBOUND_RUST_LOG") {
        return directive;
    }

    if let Some(directive) = parse_env_filter_var("RUST_LOG") {
        return directive;
    }

    default_level.to_string()
}

fn parse_env_filter_var(name: &str) -> Option<String> {
    let raw = std::env::var(name).ok()?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    match EnvFilter::try_new(trimmed) {
        Ok(_) => Some(trimmed.to_string()),
        Err(err) => {
            eprintln!(
                "[observability] ignoring invalid {name} value {trimmed:?}: {err}"
            );
            None
        }
    }
}

fn init_dev_subscriber(
    config: LogConfig,
    env_filter: EnvFilter,
    tracer: Option<opentelemetry_sdk::trace::Tracer>,
    otel_log_layer: Option<OtlpLogLayer>,
) {
    let log_path = config.log_path.clone().unwrap_or_else(default_log_path);
    let writer_factory = WriterFactory::new(&log_path)
        .unwrap_or_else(|e| panic!("failed to initialize log writer at {:?}: {}", log_path, e));
    let otlp_traces_enabled = tracer.is_some();
    let otlp_logs_enabled = otel_log_layer.is_some();
    let otlp_endpoint = config
        .otlp
        .as_ref()
        .map(|otlp| otlp.endpoint.as_str())
        .unwrap_or("");

    let make_file_json_layer = || {
        fmt::layer()
            .json()
            .with_target(true)
            .with_file(true)
            .with_line_number(true)
            .with_current_span(true)
            .with_span_list(true)
            .with_writer(writer_factory.clone())
    };

    match (tracer, config.also_stderr, config.log_format) {
        (Some(tracer), true, LogFormat::Pretty) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
                .with(
                    fmt::layer()
                        .pretty()
                        .with_target(true)
                        .with_file(true)
                        .with_line_number(true)
                        .with_writer(std::io::stderr),
                )
                .with(otel_log_layer.clone())
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        (Some(tracer), true, LogFormat::Json) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
                .with(
                    fmt::layer()
                        .json()
                        .with_target(true)
                        .with_file(true)
                        .with_line_number(true)
                        .with_current_span(true)
                        .with_span_list(true)
                        .with_writer(std::io::stderr),
                )
                .with(otel_log_layer.clone())
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        (Some(tracer), false, _) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
                .with(otel_log_layer.clone())
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        (None, true, LogFormat::Pretty) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
                .with(
                    fmt::layer()
                        .pretty()
                        .with_target(true)
                        .with_file(true)
                        .with_line_number(true)
                        .with_writer(std::io::stderr),
                )
                .with(otel_log_layer.clone())
                .try_init();
        }
        (None, true, LogFormat::Json) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
                .with(
                    fmt::layer()
                        .json()
                        .with_target(true)
                        .with_file(true)
                        .with_line_number(true)
                        .with_current_span(true)
                        .with_span_list(true)
                        .with_writer(std::io::stderr),
                )
                .with(otel_log_layer.clone())
                .try_init();
        }
        (None, false, _) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter)
                .with(make_file_json_layer())
                .with(otel_log_layer)
                .try_init();
        }
    }

    tracing::info!(
        log_path = %log_path.display(),
        mode = "dev_verbose",
        otlp_traces_enabled,
        otlp_logs_enabled,
        otlp_endpoint,
        "observability initialized"
    );
}

fn init_prod_subscriber(
    config: LogConfig,
    env_filter: EnvFilter,
    tracer: Option<opentelemetry_sdk::trace::Tracer>,
    otel_log_layer: Option<OtlpLogLayer>,
) {
    let otlp_traces_enabled = tracer.is_some();
    let otlp_logs_enabled = otel_log_layer.is_some();
    let otlp_endpoint = config
        .otlp
        .as_ref()
        .map(|otlp| otlp.endpoint.as_str())
        .unwrap_or("");
    let make_prod_layer = || {
        fmt::layer()
            .json()
            .with_target(false)
            .with_file(false)
            .with_line_number(false)
            .with_current_span(false)
            .with_span_list(false)
            .with_writer(std::io::stderr)
    };

    match tracer {
        Some(tracer) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_prod_layer())
                .with(otel_log_layer)
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        None => {
            let _ = tracing_subscriber::registry()
                .with(env_filter)
                .with(make_prod_layer())
                .with(otel_log_layer)
                .try_init();
        }
    }

    tracing::info!(
        mode = "prod_light",
        otlp_traces_enabled,
        otlp_logs_enabled,
        otlp_endpoint,
        "observability initialized"
    );
}

fn init_otel_tracer(
    config: &LogConfig,
    otlp: &OtlpConfig,
) -> Option<opentelemetry_sdk::trace::Tracer> {
    let sampler = match otlp.sampler {
        OtlpSampler::AlwaysOn => trace::Sampler::AlwaysOn,
        OtlpSampler::ParentBasedTraceIdRatio => trace::Sampler::ParentBased(Box::new(
            trace::Sampler::TraceIdRatioBased(otlp.sampler_arg.clamp(0.0, 1.0)),
        )),
    };

    let resource = build_resource(config);
    let endpoint = otlp_signal_endpoint(&otlp.endpoint, "traces");

    // The stable BatchSpanProcessor exports on its own background thread.
    // The SDK documents reqwest-blocking-client as the supported HTTP transport
    // for this processor; async reqwest requires the async-runtime variant.
    let http_client = std::thread::spawn(reqwest::blocking::Client::new)
        .join()
        .unwrap_or_else(|_| reqwest::blocking::Client::new());
    let mut exporter_builder = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_http_client(http_client)
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(endpoint);

    if !otlp.headers.is_empty() {
        exporter_builder = exporter_builder.with_headers(otlp.headers.clone());
    }

    let exporter = match exporter_builder.build() {
        Ok(exporter) => exporter,
        Err(err) => {
            eprintln!("failed to build OTLP exporter: {err}");
            return None;
        }
    };

    let batch_processor = BatchSpanProcessor::builder(exporter).build();

    let provider = SdkTracerProvider::builder()
        .with_span_processor(batch_processor)
        .with_sampler(sampler)
        .with_resource(resource)
        .build();

    let _ = TRACER_PROVIDER.set(provider.clone());
    global::set_tracer_provider(provider.clone());

    Some(provider.tracer(config.service_name.clone()))
}

fn init_otel_log_layer(config: &LogConfig, otlp: &OtlpConfig) -> Option<OtlpLogLayer> {
    let resource = build_resource(config);
    let endpoint = otlp_signal_endpoint(&otlp.endpoint, "logs");

    let http_client = reqwest::Client::new();
    let mut exporter_builder = LogExporter::builder()
        .with_http()
        .with_http_client(http_client)
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(endpoint);

    if !otlp.headers.is_empty() {
        exporter_builder = exporter_builder.with_headers(otlp.headers.clone());
    }

    let exporter = match exporter_builder.build() {
        Ok(exporter) => exporter,
        Err(err) => {
            eprintln!("failed to build OTLP log exporter: {err}");
            return None;
        }
    };

    let batch_processor = AsyncBatchLogProcessor::builder(exporter, runtime::Tokio).build();

    let provider = SdkLoggerProvider::builder()
        .with_log_processor(batch_processor)
        .with_resource(resource)
        .build();

    let _ = LOGGER_PROVIDER.set(provider.clone());

    Some(OtlpLogLayer::new(
        provider.logger(config.service_name.clone()),
    ))
}

fn build_resource(config: &LogConfig) -> Resource {
    Resource::builder()
        .with_attributes(vec![
            KeyValue::new("service.name", config.service_name.clone()),
            KeyValue::new("deployment.environment", config.environment.clone()),
            KeyValue::new("service.namespace", "unbound"),
            KeyValue::new("telemetry.sdk.language", "rust"),
        ])
        .build()
}

fn otlp_signal_endpoint(endpoint: &str, signal: &str) -> String {
    let trimmed = endpoint.trim_end_matches('/');
    for known_signal in ["traces", "logs", "metrics"] {
        let suffix = format!("/v1/{known_signal}");
        if let Some(base) = trimmed.strip_suffix(&suffix) {
            return format!("{base}/v1/{signal}");
        }
    }

    format!("{trimmed}/v1/{signal}")
}

pub fn shutdown() {
    if !OBSERVABILITY_INITIALIZED.load(Ordering::SeqCst)
        || OBSERVABILITY_SHUTDOWN.swap(true, Ordering::SeqCst)
    {
        return;
    }

    force_flush();

    if let Some(provider) = LOGGER_PROVIDER.get() {
        if let Err(err) = provider.shutdown() {
            eprintln!("[observability] logger provider shutdown failed: {err}");
        }
    }
    if let Some(provider) = TRACER_PROVIDER.get() {
        if let Err(err) = provider.shutdown() {
            eprintln!("[observability] tracer provider shutdown failed: {err}");
        }
    }
}

pub fn force_flush() {
    if !OBSERVABILITY_INITIALIZED.load(Ordering::SeqCst)
        || OBSERVABILITY_SHUTDOWN.load(Ordering::SeqCst)
    {
        return;
    }

    if let Some(provider) = LOGGER_PROVIDER.get() {
        if let Err(err) = provider.force_flush() {
            eprintln!("[observability] logger provider force_flush failed: {err}");
        }
    }
    if let Some(provider) = TRACER_PROVIDER.get() {
        if let Err(err) = provider.force_flush() {
            eprintln!("[observability] tracer provider force_flush failed: {err}");
        }
    }
}

pub use tracing::{debug, error, info, instrument, span, trace, warn, Level};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_is_dev_verbose() {
        let config = LogConfig::default();
        assert_eq!(config.service_name, "unknown");
        assert_eq!(config.default_level, "info");
        assert_eq!(config.mode, ObservabilityMode::DevVerbose);
        assert_eq!(config.log_format, LogFormat::Pretty);
        assert!(config.otlp.is_none());
    }

    #[test]
    fn default_otlp_config_is_safe_for_local_dev() {
        let cfg = OtlpConfig::default();
        assert_eq!(cfg.endpoint, "http://localhost:4318");
        assert_eq!(cfg.sampler, OtlpSampler::AlwaysOn);
        assert_eq!(cfg.sampler_arg, 1.0);
    }

    #[test]
    fn signal_endpoint_rewrites_existing_signal_paths() {
        assert_eq!(
            otlp_signal_endpoint("http://localhost:4318/v1/traces", "logs"),
            "http://localhost:4318/v1/logs"
        );
        assert_eq!(
            otlp_signal_endpoint("http://localhost:4318/v1/logs", "traces"),
            "http://localhost:4318/v1/traces"
        );
        assert_eq!(
            otlp_signal_endpoint("http://localhost:4318", "logs"),
            "http://localhost:4318/v1/logs"
        );
    }

    #[test]
    fn unbound_rust_log_takes_precedence_over_rust_log() {
        std::env::set_var("RUST_LOG", "warn");
        std::env::set_var("UNBOUND_RUST_LOG", "debug");

        assert_eq!(resolve_env_filter_directive("info"), "debug");

        std::env::remove_var("UNBOUND_RUST_LOG");
        std::env::remove_var("RUST_LOG");
    }

    #[test]
    fn lifecycle_operations_are_idempotent() {
        init_with_config(LogConfig {
            service_name: "observability-test".to_string(),
            ..Default::default()
        });
        init_with_config(LogConfig {
            service_name: "observability-test".to_string(),
            ..Default::default()
        });

        force_flush();
        force_flush();
        shutdown();
        shutdown();
    }
}
