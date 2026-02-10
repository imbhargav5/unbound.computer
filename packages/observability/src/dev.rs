//! Dev-mode logging configuration.
//!
//! Writes structured JSONL logs to a central file that can be tailed
//! by external tools. Multi-process safe via append-only semantics.

use crate::json_layer::JsonLayer;
use crate::LogConfig;
use parking_lot::Mutex;
use std::fs::{File, OpenOptions};
use std::io::{self, BufWriter};
use std::path::PathBuf;
use std::sync::Arc;
use tracing_subscriber::fmt::MakeWriter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::{EnvFilter, Layer};

/// Central log file location for all dev services.
/// Uses `~/.unbound/logs/dev.jsonl` by default.
fn default_log_path() -> PathBuf {
    dirs::home_dir()
        .expect("home directory must exist")
        .join(".unbound")
        .join("logs")
        .join("dev.jsonl")
}

/// Non-blocking file writer that appends to the central log file.
/// Uses line-buffered writes for multi-process safety.
#[derive(Clone)]
pub struct CentralLogWriter {
    inner: Arc<Mutex<BufWriter<File>>>,
}

impl CentralLogWriter {
    pub fn new(path: &PathBuf) -> io::Result<Self> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Open file in append mode for multi-process safety
        let file = OpenOptions::new().create(true).append(true).open(path)?;

        Ok(Self {
            inner: Arc::new(Mutex::new(BufWriter::with_capacity(8192, file))),
        })
    }
}

impl io::Write for CentralLogWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let mut guard = self.inner.lock();
        let result = guard.write(buf);
        // Flush after each write to ensure multi-process visibility
        // Each log line is atomic at the filesystem level (for reasonable line lengths)
        guard.flush()?;
        result
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner.lock().flush()
    }
}

/// MakeWriter implementation for tracing-subscriber
#[derive(Clone)]
pub struct WriterFactory {
    writer: CentralLogWriter,
}

impl<'a> MakeWriter<'a> for WriterFactory {
    type Writer = CentralLogWriter;

    fn make_writer(&'a self) -> Self::Writer {
        self.writer.clone()
    }
}

/// Initialize the dev subscriber with central JSONL file output.
pub fn init_dev_subscriber(config: &LogConfig) {
    let log_path = config.log_path.clone().unwrap_or_else(default_log_path);

    let writer = CentralLogWriter::new(&log_path)
        .unwrap_or_else(|e| panic!("failed to open log file {:?}: {}", log_path, e));

    let writer_factory = WriterFactory { writer };

    // Build the custom JSON logging layer
    let json_layer = JsonLayer::new(config.service_name.clone(), writer_factory);

    // Optional: stderr layer for immediate feedback during dev
    let stderr_layer = if config.also_stderr {
        Some(
            tracing_subscriber::fmt::layer()
                .with_target(true)
                .with_file(false)
                .with_line_number(false)
                .compact()
                .with_writer(io::stderr)
                .with_ansi(true),
        )
    } else {
        None
    };

    // Build env filter from RUST_LOG or default
    let env_filter =
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(&config.default_level));

    // Compose and install
    tracing_subscriber::registry()
        .with(json_layer.with_filter(env_filter.clone()))
        .with(stderr_layer.map(|l| {
            l.with_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
            )
        }))
        .init();

    // Log startup info to the central stream
    tracing::info!(
        log_path = %log_path.display(),
        "observability initialized"
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use tempfile::tempdir;

    #[test]
    fn test_central_log_writer_creates_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("logs").join("test.jsonl");

        let mut writer = CentralLogWriter::new(&path).unwrap();
        writer.write_all(b"test line\n").unwrap();

        let mut content = String::new();
        File::open(&path)
            .unwrap()
            .read_to_string(&mut content)
            .unwrap();
        assert_eq!(content, "test line\n");
    }

    #[test]
    fn test_writer_creates_parent_dirs() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("deeply").join("nested").join("test.jsonl");

        let writer = CentralLogWriter::new(&path);
        assert!(writer.is_ok());
        assert!(path.parent().unwrap().exists());
    }
}
