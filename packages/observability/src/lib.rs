mod dev;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

use dev::{default_log_path, WriterFactory};
use opentelemetry::global;
use opentelemetry::trace::TracerProvider as _;
use opentelemetry::KeyValue;
use opentelemetry_otlp::{Protocol, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry_sdk::{trace, Resource};
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
            endpoint: "http://localhost:4318/v1/traces".to_string(),
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
    let tracer = match config.otlp.as_ref() {
        Some(otlp) => init_otel_tracer(&config, otlp),
        None => None,
    };

    let env_filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(&config.default_level));

    match config.mode {
        ObservabilityMode::DevVerbose => init_dev_subscriber(config, env_filter, tracer),
        ObservabilityMode::ProdLight => init_prod_subscriber(config, env_filter, tracer),
    }
}

fn init_dev_subscriber(
    config: LogConfig,
    env_filter: EnvFilter,
    tracer: Option<opentelemetry_sdk::trace::Tracer>,
) {
    let log_path = config.log_path.clone().unwrap_or_else(default_log_path);
    let writer_factory = WriterFactory::new(&log_path)
        .unwrap_or_else(|e| panic!("failed to initialize log writer at {:?}: {}", log_path, e));

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
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        (Some(tracer), false, _) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter.clone())
                .with(make_file_json_layer())
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
                .try_init();
        }
        (None, false, _) => {
            let _ = tracing_subscriber::registry()
                .with(env_filter)
                .with(make_file_json_layer())
                .try_init();
        }
    }

    tracing::info!(
        log_path = %log_path.display(),
        mode = "dev_verbose",
        "observability initialized"
    );
}

fn init_prod_subscriber(
    _config: LogConfig,
    env_filter: EnvFilter,
    tracer: Option<opentelemetry_sdk::trace::Tracer>,
) {
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
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .try_init();
        }
        None => {
            let _ = tracing_subscriber::registry()
                .with(env_filter)
                .with(make_prod_layer())
                .try_init();
        }
    }

    tracing::info!(mode = "prod_light", "observability initialized");
}

fn init_otel_tracer(config: &LogConfig, otlp: &OtlpConfig) -> Option<opentelemetry_sdk::trace::Tracer> {
    let sampler = match otlp.sampler {
        OtlpSampler::AlwaysOn => trace::Sampler::AlwaysOn,
        OtlpSampler::ParentBasedTraceIdRatio => {
            trace::Sampler::ParentBased(Box::new(trace::Sampler::TraceIdRatioBased(
                otlp.sampler_arg.clamp(0.0, 1.0),
            )))
        }
    };

    let resource = Resource::builder()
        .with_attributes(vec![
            KeyValue::new("service.name", config.service_name.clone()),
            KeyValue::new("deployment.environment", config.environment.clone()),
            KeyValue::new("service.namespace", "unbound"),
            KeyValue::new("telemetry.sdk.language", "rust"),
        ])
        .build();

    let mut exporter_builder = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(otlp.endpoint.clone());

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

    let provider = SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_sampler(sampler)
        .with_resource(resource)
        .build();

    let _ = TRACER_PROVIDER.set(provider.clone());
    global::set_tracer_provider(provider.clone());

    Some(provider.tracer(config.service_name.clone()))
}

pub fn shutdown() {
    if let Some(provider) = TRACER_PROVIDER.get() {
        let _ = provider.force_flush();
        let _ = provider.shutdown();
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
        assert_eq!(cfg.endpoint, "http://localhost:4318/v1/traces");
        assert_eq!(cfg.sampler, OtlpSampler::AlwaysOn);
        assert_eq!(cfg.sampler_arg, 1.0);
    }
}
