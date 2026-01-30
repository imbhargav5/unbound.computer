//! Logging initialization for the daemon.

use tracing::Level;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

/// Initialize the logging system.
///
/// This sets up tracing with:
/// - Console output with timestamps and colors
/// - Log level from the provided string or RUST_LOG env var
/// - File output to the specified path (optional)
pub fn init_logging(level: &str) {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(level));

    let fmt_layer = fmt::layer()
        .with_target(true)
        .with_level(true)
        .with_thread_ids(false)
        .with_thread_names(false)
        .with_ansi(true);  // Enable colored output

    tracing_subscriber::registry()
        .with(filter)
        .with(fmt_layer)
        .init();
}

/// Initialize logging with file output.
///
/// Logs to both console and the specified file.
pub fn init_logging_with_file(level: &str, log_file: &std::path::Path) -> std::io::Result<()> {
    use std::fs::OpenOptions;

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(level));

    // Ensure parent directory exists
    if let Some(parent) = log_file.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)?;

    let file_layer = fmt::layer()
        .with_writer(file)
        .with_target(true)
        .with_level(true)
        .with_ansi(false);

    let console_layer = fmt::layer()
        .with_target(true)
        .with_level(true);

    tracing_subscriber::registry()
        .with(filter)
        .with(console_layer)
        .with(file_layer)
        .init();

    Ok(())
}

/// Parse a log level string into a tracing Level.
pub fn parse_level(level: &str) -> Level {
    match level.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" | "warning" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    }
}
