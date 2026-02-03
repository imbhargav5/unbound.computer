//! Claude event streaming.

use crate::event::ClaudeEvent;
use regex::Regex;
use tokio::io::{AsyncBufReadExt, BufReader, Lines};
use tokio::process::{Child, ChildStderr, ChildStdout};
use tokio::sync::broadcast;
use tracing::{debug, warn};

/// A stream of events from a Claude CLI process.
pub struct ClaudeEventStream {
    /// Buffered stdout reader.
    stdout: Lines<BufReader<ChildStdout>>,
    /// Buffered stderr reader.
    stderr: Option<Lines<BufReader<ChildStderr>>>,
    /// The child process (for waiting).
    child: Child,
    /// Stop signal receiver.
    stop_rx: broadcast::Receiver<()>,
    /// ANSI escape code regex.
    ansi_regex: Regex,
    /// Whether the process has finished.
    finished: bool,
}

impl ClaudeEventStream {
    /// Create a new event stream from a child process.
    pub(crate) fn new(
        mut child: Child,
        stop_rx: broadcast::Receiver<()>,
    ) -> Result<Self, crate::DekuError> {
        let stdout = child.stdout.take().ok_or(crate::DekuError::NoStdout)?;
        let stderr = child.stderr.take();

        let stdout_reader = BufReader::new(stdout).lines();
        let stderr_reader = stderr.map(|s| BufReader::new(s).lines());

        // ANSI escape code regex
        let ansi_regex = Regex::new(r"\x1B(?:\[[0-9;?]*[A-Za-z~]|\][^\x07]*\x07)").unwrap();

        Ok(Self {
            stdout: stdout_reader,
            stderr: stderr_reader,
            child,
            stop_rx,
            ansi_regex,
            finished: false,
        })
    }

    /// Get the next event from the stream.
    ///
    /// Returns `None` when the stream is exhausted (process finished or stopped).
    pub async fn next(&mut self) -> Option<ClaudeEvent> {
        if self.finished {
            return None;
        }

        loop {
            tokio::select! {
                // Check for stop signal
                _ = self.stop_rx.recv() => {
                    debug!("Stop signal received - killing Claude process");
                    let _ = self.child.kill().await;
                    self.finished = true;
                    return Some(ClaudeEvent::Stopped);
                }

                // Read next line from stdout
                line_result = self.stdout.next_line() => {
                    match line_result {
                        Ok(Some(line)) => {
                            if let Some(event) = self.process_line(&line) {
                                return Some(event);
                            }
                            // Continue if line was skipped
                        }
                        Ok(None) => {
                            // EOF - process stdout closed
                            return self.finish_process().await;
                        }
                        Err(e) => {
                            warn!(error = %e, "Error reading Claude stdout");
                            return self.finish_process().await;
                        }
                    }
                }
            }
        }
    }

    /// Process a line from stdout.
    fn process_line(&self, line: &str) -> Option<ClaudeEvent> {
        // Strip ANSI escape codes
        let clean_line = self.ansi_regex.replace_all(line, "").to_string();

        // Skip empty lines
        if clean_line.trim().is_empty() {
            return None;
        }

        // Only process lines that look like JSON
        if !clean_line.trim_start().starts_with('{') {
            debug!(
                line = %if clean_line.len() > 80 { &clean_line[..80] } else { &clean_line },
                "Skipping non-JSON line"
            );
            return None;
        }

        // Try to parse as JSON
        match serde_json::from_str::<serde_json::Value>(&clean_line) {
            Ok(json) => Some(ClaudeEvent::from_json(clean_line, json)),
            Err(e) => {
                warn!(error = %e, "Failed to parse JSON from Claude stdout");
                None
            }
        }
    }

    /// Finish the process and return the final event.
    async fn finish_process(&mut self) -> Option<ClaudeEvent> {
        self.finished = true;

        // Read any remaining stderr
        if let Some(ref mut stderr) = self.stderr {
            while let Ok(Some(line)) = stderr.next_line().await {
                warn!(stderr = %line, "Claude stderr");
            }
        }

        // Wait for process to finish
        match self.child.wait().await {
            Ok(status) => Some(ClaudeEvent::Finished {
                success: status.success(),
                exit_code: status.code(),
            }),
            Err(e) => {
                warn!(error = %e, "Error waiting for Claude process");
                Some(ClaudeEvent::Finished {
                    success: false,
                    exit_code: None,
                })
            }
        }
    }

    /// Check if the stream has finished.
    pub fn is_finished(&self) -> bool {
        self.finished
    }

    /// Get the process ID if available.
    pub fn pid(&self) -> Option<u32> {
        self.child.id()
    }
}

impl std::fmt::Debug for ClaudeEventStream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ClaudeEventStream")
            .field("pid", &self.child.id())
            .field("finished", &self.finished)
            .finish_non_exhaustive()
    }
}
