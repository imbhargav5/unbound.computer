//! Logging and tracing initialization for the daemon.

pub use observability::{
    init_with_config, LogConfig, LogFormat, ObservabilityMode, OtlpConfig, OtlpSampler,
};

const DEFAULT_DEV_TRACE_RATIO: f64 = 1.0;
const DEFAULT_PROD_TRACE_RATIO: f64 = 0.05;

pub fn init_logging(level: &str) {
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

    init_with_config(LogConfig {
        service_name: "daemon".into(),
        default_level: level.into(),
        also_stderr: true,
        mode,
        log_format,
        environment,
        otlp,
        ..Default::default()
    });
}

pub fn shutdown() {
    observability::shutdown();
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

fn parse_headers_from_env() -> std::collections::HashMap<String, String> {
    let mut headers = std::collections::HashMap::new();

    let Some(raw) = std::env::var("UNBOUND_OTEL_HEADERS").ok().and_then(non_empty) else {
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

#[allow(dead_code)]
pub fn parse_level(level: &str) -> tracing::Level {
    match level.to_ascii_lowercase().as_str() {
        "trace" => tracing::Level::TRACE,
        "debug" => tracing::Level::DEBUG,
        "info" => tracing::Level::INFO,
        "warn" | "warning" => tracing::Level::WARN,
        "error" => tracing::Level::ERROR,
        _ => tracing::Level::INFO,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_level_variants() {
        assert_eq!(parse_level("trace"), tracing::Level::TRACE);
        assert_eq!(parse_level("debug"), tracing::Level::DEBUG);
        assert_eq!(parse_level("info"), tracing::Level::INFO);
        assert_eq!(parse_level("warn"), tracing::Level::WARN);
        assert_eq!(parse_level("error"), tracing::Level::ERROR);
        assert_eq!(parse_level("unknown"), tracing::Level::INFO);
    }

    #[test]
    fn parse_ratio_clamps_values() {
        std::env::set_var("TEST_RATIO", "9.9");
        assert_eq!(parse_ratio_from_env("TEST_RATIO", 0.1), 1.0);
        std::env::set_var("TEST_RATIO", "-4");
        assert_eq!(parse_ratio_from_env("TEST_RATIO", 0.1), 0.0);
        std::env::remove_var("TEST_RATIO");
    }
}
