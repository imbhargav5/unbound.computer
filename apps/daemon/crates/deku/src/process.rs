//! Claude CLI process management.

use crate::config::ClaudeConfig;
use crate::error::DekuResult;
use crate::stream::ClaudeEventStream;
use std::process::Stdio;
use tokio::process::Command;
use tokio::sync::broadcast;
use tracing::{debug, info};

/// A handle to a running Claude CLI process.
pub struct ClaudeProcess {
    /// Stop signal sender.
    stop_tx: broadcast::Sender<()>,
    /// The event stream (taken on first call to take_stream).
    stream: Option<ClaudeEventStream>,
    /// Process ID if available.
    pid: Option<u32>,
}

impl ClaudeProcess {
    /// Spawn a new Claude CLI process.
    ///
    /// # Arguments
    ///
    /// * `config` - Configuration for the Claude process.
    ///
    /// # Returns
    ///
    /// A `ClaudeProcess` handle that can be used to control the process
    /// and receive events.
    pub async fn spawn(config: ClaudeConfig) -> DekuResult<Self> {
        let command = config.build_command();

        info!(
            working_dir = %config.working_dir,
            has_resume = config.resume_session_id.is_some(),
            "Spawning Claude CLI process"
        );
        debug!(command = %command, "Claude command");

        // Spawn the process via shell
        let child = Command::new("zsh")
            .args(["-l", "-c", &command])
            .current_dir(&config.working_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        let pid = child.id();
        info!(pid = ?pid, "Claude process spawned");

        // Create stop channel
        let (stop_tx, stop_rx) = broadcast::channel::<()>(1);

        // Create the event stream
        let stream = ClaudeEventStream::new(child, stop_rx)?;

        Ok(Self {
            stop_tx,
            stream: Some(stream),
            pid,
        })
    }

    /// Take the event stream from this process handle.
    ///
    /// This can only be called once. Subsequent calls will return `None`.
    pub fn take_stream(&mut self) -> Option<ClaudeEventStream> {
        self.stream.take()
    }

    /// Get a clone of the stop signal sender.
    ///
    /// This can be used to stop the process from another task.
    pub fn stop_sender(&self) -> broadcast::Sender<()> {
        self.stop_tx.clone()
    }

    /// Send a stop signal to the process.
    ///
    /// This will cause the process to be killed and the event stream
    /// to emit a `Stopped` event.
    pub fn stop(&self) {
        info!(pid = ?self.pid, "Sending stop signal to Claude process");
        let _ = self.stop_tx.send(());
    }

    /// Get the process ID if available.
    pub fn pid(&self) -> Option<u32> {
        self.pid
    }

    /// Check if the stream has been taken.
    pub fn stream_taken(&self) -> bool {
        self.stream.is_none()
    }
}

impl std::fmt::Debug for ClaudeProcess {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ClaudeProcess")
            .field("pid", &self.pid)
            .field("stream_taken", &self.stream.is_none())
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: These tests require the Claude CLI to be installed.
    // They are marked as ignored by default.

    #[tokio::test]
    #[ignore = "requires Claude CLI"]
    async fn test_spawn_and_stop() {
        let config = ClaudeConfig::new("Say hello", "/tmp");
        let mut process = ClaudeProcess::spawn(config).await.unwrap();

        assert!(process.pid().is_some());

        let stream = process.take_stream();
        assert!(stream.is_some());
        assert!(process.stream_taken());

        // Stop the process
        process.stop();
    }
}
