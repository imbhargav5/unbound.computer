//! # Observability
//!
//! Centralized observability layer for the Unbound monorepo.
//!
//! ## Design Philosophy
//!
//! Services are **log producers**, not log consumers or streamers. They call
//! `observability::init()` once at startup and use standard `tracing` macros
//! throughout their code. They have zero knowledge of:
//!
//! - Where logs go (file, stdout, network)
//! - Who consumes logs (CLI tools, dashboards, aggregators)
//! - How logs are streamed (pull via tail, push via network)
//!
//! ## Dev Mode
//!
//! All services write structured JSONL to a single central file:
//! `~/.unbound/logs/dev.jsonl`
//!
//! This enables:
//! - `tail -f ~/.unbound/logs/dev.jsonl` for raw streaming
//! - `tail -f ~/.unbound/logs/dev.jsonl | jq` for pretty JSON
//! - `lnav ~/.unbound/logs/dev.jsonl` for interactive exploration
//!
//! Multi-process safety is achieved through append-only writes with
//! per-line flush semantics.
//!
//! ## Usage
//!
//! ```rust,ignore
//! // In your service's main.rs
//! fn main() {
//!     observability::init("daemon");
//!
//!     tracing::info!("service started");
//!     // ... rest of your code
//! }
//! ```
//!
//! Or with configuration:
//!
//! ```rust,ignore
//! fn main() {
//!     observability::init_with_config(observability::LogConfig {
//!         service_name: "daemon".into(),
//!         default_level: "debug".into(),
//!         also_stderr: true,
//!         ..Default::default()
//!     });
//! }
//! ```

#[cfg(feature = "dev")]
mod dev;

mod json_layer;
mod remote;

use std::path::PathBuf;

/// Runtime export policy mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObservabilityMode {
    /// Development mode: include verbose payloads after basic secret redaction.
    DevVerbose,
    /// Production mode: export metadata only (no raw payloads).
    ProdMetadataOnly,
}

impl Default for ObservabilityMode {
    fn default() -> Self {
        Self::DevVerbose
    }
}

/// PostHog sink configuration.
#[derive(Debug, Clone)]
pub struct PosthogConfig {
    /// Project API key.
    pub api_key: String,
    /// PostHog ingest host, e.g. https://us.i.posthog.com.
    pub host: String,
    /// Max events per batch flush.
    pub batch_size: usize,
    /// Internal queue capacity.
    pub queue_capacity: usize,
    /// Flush interval in milliseconds.
    pub flush_interval_ms: u64,
}

/// Sentry sink configuration.
#[derive(Debug, Clone)]
pub struct SentryConfig {
    /// Sentry DSN.
    pub dsn: String,
}

/// Per-level sampling configuration for remote export.
#[derive(Debug, Clone)]
pub struct SamplingConfig {
    /// DEBUG and TRACE sample rate.
    pub debug_rate: f64,
    /// INFO and NOTICE sample rate.
    pub info_rate: f64,
    /// WARN sample rate.
    pub warn_rate: f64,
    /// ERROR sample rate.
    pub error_rate: f64,
}

impl Default for SamplingConfig {
    fn default() -> Self {
        Self {
            debug_rate: 0.0,
            info_rate: 0.1,
            warn_rate: 1.0,
            error_rate: 1.0,
        }
    }
}

/// Configuration for the logging system.
#[derive(Debug, Clone)]
pub struct LogConfig {
    /// Name of the service (e.g., "daemon", "cli", "worker").
    /// Included in every log line for filtering.
    pub service_name: String,

    /// Default log level filter (e.g., "debug", "info", "warn").
    /// Can be overridden by `RUST_LOG` environment variable.
    pub default_level: String,

    /// Optional custom log file path.
    /// Defaults to `~/.unbound/logs/dev.jsonl` in dev mode.
    pub log_path: Option<PathBuf>,

    /// Also emit logs to stderr for immediate feedback.
    /// Defaults to false in dev mode.
    pub also_stderr: bool,

    /// Runtime observability mode.
    pub mode: ObservabilityMode,

    /// Logical environment name written to remote payloads.
    pub environment: String,

    /// Optional PostHog sink configuration.
    pub posthog: Option<PosthogConfig>,

    /// Optional Sentry sink configuration.
    pub sentry: Option<SentryConfig>,

    /// Remote export sampling policy.
    pub sampling: SamplingConfig,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            service_name: "unknown".into(),
            default_level: "info".into(),
            log_path: None,
            also_stderr: false,
            mode: ObservabilityMode::DevVerbose,
            environment: "development".into(),
            posthog: None,
            sentry: None,
            sampling: SamplingConfig::default(),
        }
    }
}

/// Initialize the observability layer with default settings.
///
/// This is the zero-config entry point. Services call this once at startup:
///
/// ```rust,ignore
/// fn main() {
///     observability::init("my-service");
///     tracing::info!("ready");
/// }
/// ```
///
/// # Panics
///
/// Panics if the log file cannot be created or opened.
pub fn init(service_name: &str) {
    init_with_config(LogConfig {
        service_name: service_name.into(),
        ..Default::default()
    });
}

/// Initialize the observability layer with custom configuration.
///
/// Use this when you need to customize logging behavior:
///
/// ```rust,ignore
/// observability::init_with_config(observability::LogConfig {
///     service_name: "daemon".into(),
///     default_level: "debug".into(),
///     also_stderr: true,
///     ..Default::default()
/// });
/// ```
pub fn init_with_config(config: LogConfig) {
    // Set service name as a default span field
    // This ensures every log line includes the service name
    let config = inject_service_context(config);

    #[cfg(feature = "dev")]
    {
        dev::init_dev_subscriber(&config);
        return;
    }

    #[cfg(not(feature = "dev"))]
    {
        use tracing_subscriber::util::SubscriberInitExt;
        tracing_subscriber::fmt()
            .with_env_filter(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(&config.default_level)),
            )
            .with_target(true)
            .compact()
            .init();
    }
}

/// Inject service-level context that will appear in all log lines.
fn inject_service_context(config: LogConfig) -> LogConfig {
    // The service name and PID are injected via spans in the dev module
    config
}

/// Re-export tracing macros for convenience.
/// Services can use `observability::info!()` or `tracing::info!()`.
pub use tracing::{debug, error, info, instrument, trace, warn};

/// Re-export the span macro for structured context.
pub use tracing::span;

/// Re-export Level for advanced filtering.
pub use tracing::Level;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = LogConfig::default();
        assert_eq!(config.service_name, "unknown");
        assert_eq!(config.default_level, "info");
        assert!(config.log_path.is_none());
        assert!(!config.also_stderr);
        assert_eq!(config.mode, ObservabilityMode::DevVerbose);
        assert_eq!(config.environment, "development");
        assert!(config.posthog.is_none());
        assert!(config.sentry.is_none());
        assert_eq!(config.sampling.debug_rate, 0.0);
        assert_eq!(config.sampling.info_rate, 0.1);
        assert_eq!(config.sampling.warn_rate, 1.0);
        assert_eq!(config.sampling.error_rate, 1.0);
    }
}
