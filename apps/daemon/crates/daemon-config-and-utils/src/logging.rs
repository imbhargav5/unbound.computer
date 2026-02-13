//! Logging initialization for the daemon.
//!
//! This module re-exports the observability crate's initialization functions.
//! All daemon services use a centralized logging system that writes structured
//! JSONL to `~/.unbound/logs/dev.jsonl`.

// Re-exports for direct access if needed
#[allow(unused_imports)]
pub use observability::{
    init, init_with_config, LogConfig, ObservabilityMode, PosthogConfig, SamplingConfig,
    SentryConfig,
};

const DEFAULT_POSTHOG_HOST: &str = "https://us.i.posthog.com";

/// Initialize the logging system for the daemon.
///
/// This sets up tracing with:
/// - Structured JSONL output to `~/.unbound/logs/dev.jsonl`
/// - Log level from RUST_LOG env var or the provided default
/// - Service name included in every log line
///
/// # Arguments
///
/// * `level` - Default log level (trace, debug, info, warn, error)
///
/// # Example
///
/// ```ignore
/// init_logging("info");
/// tracing::info!("Daemon started");
/// ```
pub fn init_logging(level: &str) {
    let observability_mode = match std::env::var("UNBOUND_OBS_MODE")
        .unwrap_or_else(|_| "dev".to_string())
        .to_ascii_lowercase()
        .as_str()
    {
        "prod" | "production" => ObservabilityMode::ProdMetadataOnly,
        _ => ObservabilityMode::DevVerbose,
    };
    let environment = match observability_mode {
        ObservabilityMode::ProdMetadataOnly => "production".to_string(),
        ObservabilityMode::DevVerbose => "development".to_string(),
    };

    let posthog = std::env::var("UNBOUND_POSTHOG_API_KEY")
        .ok()
        .and_then(non_empty_env)
        .map(|api_key| PosthogConfig {
            api_key,
            host: std::env::var("UNBOUND_POSTHOG_HOST")
                .ok()
                .and_then(non_empty_env)
                .unwrap_or_else(|| DEFAULT_POSTHOG_HOST.to_string()),
            batch_size: 50,
            queue_capacity: 2_000,
            flush_interval_ms: 2_000,
        });

    let sentry = std::env::var("UNBOUND_SENTRY_DSN")
        .ok()
        .and_then(non_empty_env)
        .map(|dsn| SentryConfig { dsn });

    let sampling = SamplingConfig {
        debug_rate: parse_rate_env("UNBOUND_OBS_DEBUG_SAMPLE_RATE", 0.0),
        info_rate: parse_rate_env("UNBOUND_OBS_INFO_SAMPLE_RATE", 0.10),
        warn_rate: parse_rate_env("UNBOUND_OBS_WARN_SAMPLE_RATE", 1.0),
        error_rate: parse_rate_env("UNBOUND_OBS_ERROR_SAMPLE_RATE", 1.0),
    };

    observability::init_with_config(observability::LogConfig {
        service_name: "daemon".into(),
        default_level: level.into(),
        also_stderr: true, // Show logs on stderr for foreground mode
        mode: observability_mode,
        environment,
        posthog,
        sentry,
        sampling,
        ..Default::default()
    });
}

/// Initialize logging with a custom service name.
///
/// Use this when you need to distinguish between different daemon components
/// in the central log stream.
#[allow(dead_code)]
pub fn init_logging_for_service(service_name: &str, level: &str) {
    let observability_mode = match std::env::var("UNBOUND_OBS_MODE")
        .unwrap_or_else(|_| "dev".to_string())
        .to_ascii_lowercase()
        .as_str()
    {
        "prod" | "production" => ObservabilityMode::ProdMetadataOnly,
        _ => ObservabilityMode::DevVerbose,
    };
    let environment = match observability_mode {
        ObservabilityMode::ProdMetadataOnly => "production".to_string(),
        ObservabilityMode::DevVerbose => "development".to_string(),
    };

    let posthog = std::env::var("UNBOUND_POSTHOG_API_KEY")
        .ok()
        .and_then(non_empty_env)
        .map(|api_key| PosthogConfig {
            api_key,
            host: std::env::var("UNBOUND_POSTHOG_HOST")
                .ok()
                .and_then(non_empty_env)
                .unwrap_or_else(|| DEFAULT_POSTHOG_HOST.to_string()),
            batch_size: 50,
            queue_capacity: 2_000,
            flush_interval_ms: 2_000,
        });

    let sentry = std::env::var("UNBOUND_SENTRY_DSN")
        .ok()
        .and_then(non_empty_env)
        .map(|dsn| SentryConfig { dsn });

    let sampling = SamplingConfig {
        debug_rate: parse_rate_env("UNBOUND_OBS_DEBUG_SAMPLE_RATE", 0.0),
        info_rate: parse_rate_env("UNBOUND_OBS_INFO_SAMPLE_RATE", 0.10),
        warn_rate: parse_rate_env("UNBOUND_OBS_WARN_SAMPLE_RATE", 1.0),
        error_rate: parse_rate_env("UNBOUND_OBS_ERROR_SAMPLE_RATE", 1.0),
    };

    observability::init_with_config(observability::LogConfig {
        service_name: service_name.into(),
        default_level: level.into(),
        also_stderr: true,
        mode: observability_mode,
        environment,
        posthog,
        sentry,
        sampling,
        ..Default::default()
    });
}

fn non_empty_env(raw: String) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn parse_rate_env(name: &str, fallback: f64) -> f64 {
    std::env::var(name)
        .ok()
        .and_then(non_empty_env)
        .and_then(|raw| raw.parse::<f64>().ok())
        .map(|value| value.clamp(0.0, 1.0))
        .unwrap_or(fallback)
}

/// Parse a log level string into a tracing Level.
#[allow(dead_code)]
pub fn parse_level(level: &str) -> tracing::Level {
    match level.to_lowercase().as_str() {
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
    fn parse_level_all_variants() {
        assert_eq!(parse_level("trace"), tracing::Level::TRACE);
        assert_eq!(parse_level("debug"), tracing::Level::DEBUG);
        assert_eq!(parse_level("info"), tracing::Level::INFO);
        assert_eq!(parse_level("warn"), tracing::Level::WARN);
        assert_eq!(parse_level("warning"), tracing::Level::WARN);
        assert_eq!(parse_level("error"), tracing::Level::ERROR);
    }

    #[test]
    fn parse_level_case_insensitive() {
        assert_eq!(parse_level("TRACE"), tracing::Level::TRACE);
        assert_eq!(parse_level("Debug"), tracing::Level::DEBUG);
        assert_eq!(parse_level("INFO"), tracing::Level::INFO);
        assert_eq!(parse_level("WARN"), tracing::Level::WARN);
        assert_eq!(parse_level("WARNING"), tracing::Level::WARN);
        assert_eq!(parse_level("ERROR"), tracing::Level::ERROR);
    }

    #[test]
    fn parse_level_unknown_defaults_to_info() {
        assert_eq!(parse_level(""), tracing::Level::INFO);
        assert_eq!(parse_level("verbose"), tracing::Level::INFO);
        assert_eq!(parse_level("fatal"), tracing::Level::INFO);
        assert_eq!(parse_level("nonsense"), tracing::Level::INFO);
    }
}
