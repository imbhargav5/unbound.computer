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

use std::path::PathBuf;

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
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            service_name: "unknown".into(),
            default_level: "info".into(),
            log_path: None,
            also_stderr: false,
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
    dev::init_dev_subscriber(&config);

    #[cfg(feature = "prod")]
    compile_error!("prod logging not yet implemented");

    #[cfg(not(any(feature = "dev", feature = "prod")))]
    compile_error!("enable either 'dev' or 'prod' feature");
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
    }
}
