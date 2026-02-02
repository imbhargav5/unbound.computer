//! Logging initialization for the daemon.
//!
//! This module re-exports the observability crate's initialization functions.
//! All daemon services use a centralized logging system that writes structured
//! JSONL to `~/.unbound/logs/dev.jsonl`.

// Re-exports for direct access if needed
#[allow(unused_imports)]
pub use observability::{init, init_with_config, LogConfig};

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
    observability::init_with_config(observability::LogConfig {
        service_name: "daemon".into(),
        default_level: level.into(),
        also_stderr: true, // Show logs on stderr for foreground mode
        ..Default::default()
    });
}

/// Initialize logging with a custom service name.
///
/// Use this when you need to distinguish between different daemon components
/// in the central log stream.
#[allow(dead_code)]
pub fn init_logging_for_service(service_name: &str, level: &str) {
    observability::init_with_config(observability::LogConfig {
        service_name: service_name.into(),
        default_level: level.into(),
        also_stderr: true,
        ..Default::default()
    });
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
