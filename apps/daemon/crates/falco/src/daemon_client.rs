//! Unix Domain Socket client for communicating with the daemon.

use crate::error::{FalcoError, FalcoResult};
use crate::protocol::{read_frame, CommandFrame, DaemonDecisionFrame, Decision};
use std::path::Path;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::time::timeout;
use tracing::{debug, warn};
use uuid::Uuid;

/// Client for communicating with the daemon over Unix Domain Socket.
pub struct DaemonClient {
    stream: UnixStream,
    read_buf: Vec<u8>,
}

impl DaemonClient {
    /// Connect to the daemon at the given socket path.
    pub async fn connect(socket_path: &Path) -> FalcoResult<Self> {
        let stream = UnixStream::connect(socket_path).await.map_err(|e| {
            FalcoError::DaemonConnection(format!(
                "Failed to connect to daemon at {}: {}",
                socket_path.display(),
                e
            ))
        })?;

        debug!(path = %socket_path.display(), "Connected to daemon");

        Ok(Self {
            stream,
            read_buf: Vec::with_capacity(4096),
        })
    }

    /// Send a command frame to the daemon and wait for a decision.
    ///
    /// Returns the decision and any result data.
    /// If the timeout expires, returns an error.
    pub async fn send_and_wait(
        &mut self,
        command_id: Uuid,
        encrypted_payload: Vec<u8>,
        timeout_duration: Duration,
    ) -> FalcoResult<(Decision, Vec<u8>)> {
        // Build and send the command frame
        let frame = CommandFrame::new(command_id, encrypted_payload);
        let encoded = frame.encode();

        self.stream.write_all(&encoded).await.map_err(|e| {
            FalcoError::DaemonConnection(format!("Failed to write to daemon: {}", e))
        })?;

        debug!(command_id = %command_id, "Sent command frame to daemon");

        // Wait for response with timeout
        let decision_frame = timeout(timeout_duration, self.read_decision_frame()).await.map_err(
            |_| FalcoError::Timeout(timeout_duration.as_secs()),
        )??;

        // Verify the command ID matches
        if decision_frame.command_id != command_id {
            return Err(FalcoError::Protocol(format!(
                "Decision command_id mismatch: expected {}, got {}",
                command_id, decision_frame.command_id
            )));
        }

        debug!(
            command_id = %command_id,
            decision = ?decision_frame.decision,
            "Received decision from daemon"
        );

        Ok((decision_frame.decision, decision_frame.result))
    }

    /// Read a daemon decision frame from the socket.
    async fn read_decision_frame(&mut self) -> FalcoResult<DaemonDecisionFrame> {
        loop {
            // Try to parse a complete frame from the buffer
            if let Some((frame_data, consumed)) = read_frame(&self.read_buf) {
                let frame = DaemonDecisionFrame::decode(frame_data)?;
                self.read_buf.drain(..consumed);
                return Ok(frame);
            }

            // Need more data
            let mut chunk = [0u8; 4096];
            let n = self.stream.read(&mut chunk).await.map_err(|e| {
                FalcoError::DaemonConnection(format!("Failed to read from daemon: {}", e))
            })?;

            if n == 0 {
                return Err(FalcoError::DaemonConnection(
                    "Daemon closed connection".to_string(),
                ));
            }

            self.read_buf.extend_from_slice(&chunk[..n]);
        }
    }

    /// Check if the connection is still alive by attempting a zero-byte read.
    #[allow(dead_code)]
    pub async fn is_connected(&mut self) -> bool {
        // Try to peek at the socket
        let mut buf = [0u8; 0];
        match self.stream.try_read(&mut buf) {
            Ok(_) => true,
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => true,
            Err(_) => false,
        }
    }
}

/// Attempt to connect to the daemon with retries.
pub async fn connect_with_retry(
    socket_path: &Path,
    max_retries: u32,
    retry_delay: Duration,
) -> FalcoResult<DaemonClient> {
    for attempt in 1..=max_retries {
        match DaemonClient::connect(socket_path).await {
            Ok(client) => return Ok(client),
            Err(e) => {
                if attempt < max_retries {
                    warn!(
                        attempt,
                        max_retries,
                        error = %e,
                        "Failed to connect to daemon, retrying..."
                    );
                    tokio::time::sleep(retry_delay).await;
                } else {
                    return Err(e);
                }
            }
        }
    }

    Err(FalcoError::DaemonConnection(
        "Max retries exceeded".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::UnixListener;

    #[tokio::test]
    async fn test_connect_nonexistent_socket() {
        let result = DaemonClient::connect(Path::new("/nonexistent/socket.sock")).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_send_and_receive() {
        let dir = tempdir().unwrap();
        let socket_path = dir.path().join("test.sock");

        // Start a mock server
        let listener = UnixListener::bind(&socket_path).unwrap();

        let socket_path_clone = socket_path.clone();
        let server_task = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();

            // Read the command frame
            let mut buf = [0u8; 4096];
            let n = stream.read(&mut buf).await.unwrap();
            assert!(n > 0);

            // Parse it to get the command_id
            let (frame_data, _) = read_frame(&buf[..n]).unwrap();
            let cmd = CommandFrame::decode(frame_data).unwrap();

            // Send back a decision
            let decision = DaemonDecisionFrame::new(cmd.command_id, Decision::AckRedis);
            stream.write_all(&decision.encode()).await.unwrap();
        });

        // Connect client
        tokio::time::sleep(Duration::from_millis(50)).await;
        let mut client = DaemonClient::connect(&socket_path_clone).await.unwrap();

        // Send command
        let command_id = Uuid::new_v4();
        let payload = vec![1, 2, 3, 4];
        let (decision, result) = client
            .send_and_wait(command_id, payload, Duration::from_secs(5))
            .await
            .unwrap();

        assert_eq!(decision, Decision::AckRedis);
        assert!(result.is_empty());

        server_task.await.unwrap();
    }

    #[tokio::test]
    async fn test_timeout() {
        let dir = tempdir().unwrap();
        let socket_path = dir.path().join("test.sock");

        // Start a mock server that doesn't respond
        let listener = UnixListener::bind(&socket_path).unwrap();

        let server_task = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            // Just read but never respond
            let mut buf = [0u8; 4096];
            let _ = stream.read(&mut buf).await;
            // Keep connection open for a bit
            tokio::time::sleep(Duration::from_secs(2)).await;
        });

        // Connect client
        tokio::time::sleep(Duration::from_millis(50)).await;
        let mut client = DaemonClient::connect(&socket_path).await.unwrap();

        // Send command with short timeout
        let command_id = Uuid::new_v4();
        let result = client
            .send_and_wait(command_id, vec![], Duration::from_millis(100))
            .await;

        assert!(matches!(result, Err(FalcoError::Timeout(_))));

        server_task.abort();
    }
}
