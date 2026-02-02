//! Main courier loop orchestration.

use crate::config::FalcoConfig;
use crate::daemon_client::{connect_with_retry, DaemonClient};
use crate::error::{FalcoError, FalcoResult};
use crate::protocol::Decision;
use crate::redis_consumer::RedisConsumer;
use std::time::Duration;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// The main Falco courier.
///
/// Orchestrates the flow of commands from Redis to the daemon.
pub struct Courier {
    config: FalcoConfig,
    redis: RedisConsumer,
    daemon: Option<DaemonClient>,
}

impl Courier {
    /// Create a new Courier.
    pub async fn new(config: FalcoConfig) -> FalcoResult<Self> {
        let redis = RedisConsumer::connect(config.clone()).await?;

        Ok(Self {
            config,
            redis,
            daemon: None,
        })
    }

    /// Run the main courier loop.
    ///
    /// This loop:
    /// 1. Reads one message from Redis (XREADGROUP COUNT=1)
    /// 2. Generates a command_id UUID
    /// 3. Connects to daemon if needed
    /// 4. Sends CommandFrame to daemon
    /// 5. Waits for DaemonDecisionFrame (with timeout)
    /// 6. ACKs Redis if instructed or on timeout
    /// 7. Loops
    pub async fn run(&mut self) -> FalcoResult<()> {
        info!(
            device_id = %self.config.device_id,
            stream = %self.config.stream_key(),
            consumer = %self.config.consumer_name,
            "Starting Falco courier loop"
        );

        loop {
            if let Err(e) = self.process_one().await {
                error!(error = %e, "Error processing message");

                // On certain errors, wait before retrying
                match &e {
                    FalcoError::Redis(_) => {
                        warn!("Redis error, attempting to reconnect...");
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        if let Err(reconnect_err) = self.redis.reconnect().await {
                            error!(error = %reconnect_err, "Failed to reconnect to Redis");
                            tokio::time::sleep(Duration::from_secs(5)).await;
                        }
                    }
                    FalcoError::DaemonConnection(_) => {
                        warn!("Daemon connection error, will retry on next message");
                        self.daemon = None;
                        tokio::time::sleep(Duration::from_millis(500)).await;
                    }
                    _ => {
                        // For other errors, brief pause before continuing
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    }
                }
            }
        }
    }

    /// Process one message from Redis.
    async fn process_one(&mut self) -> FalcoResult<()> {
        // Read the next message from Redis
        let message = match self.redis.read_next().await? {
            Some(msg) => msg,
            None => {
                // Block timeout expired, no messages available
                debug!("No messages available, continuing to poll...");
                return Ok(());
            }
        };

        info!(
            message_id = %message.message_id,
            payload_len = message.encrypted_payload.len(),
            "Processing message"
        );

        // Generate a command ID for correlation
        let command_id = Uuid::new_v4();

        // Ensure daemon connection
        self.ensure_daemon_connection().await?;

        let daemon = self.daemon.as_mut().ok_or_else(|| {
            FalcoError::DaemonConnection("No daemon connection".to_string())
        })?;

        // Send to daemon and wait for decision
        let decision = match daemon
            .send_and_wait(
                command_id,
                message.encrypted_payload.clone(),
                self.config.daemon_timeout,
            )
            .await
        {
            Ok((decision, _result)) => decision,
            Err(FalcoError::Timeout(secs)) => {
                // Fail-open: ACK on timeout to prevent infinite PEL growth
                warn!(
                    message_id = %message.message_id,
                    command_id = %command_id,
                    timeout_secs = secs,
                    "Daemon timeout, applying fail-open ACK"
                );
                Decision::AckRedis
            }
            Err(e) => {
                // Other errors: don't ACK, let Redis redeliver
                error!(
                    message_id = %message.message_id,
                    command_id = %command_id,
                    error = %e,
                    "Error communicating with daemon, leaving message in PEL"
                );
                self.daemon = None; // Force reconnect on next attempt
                return Err(e);
            }
        };

        // Apply the decision
        match decision {
            Decision::AckRedis => {
                self.redis.ack(&message.message_id).await?;
                info!(
                    message_id = %message.message_id,
                    command_id = %command_id,
                    "Message acknowledged"
                );
            }
            Decision::DoNotAck => {
                info!(
                    message_id = %message.message_id,
                    command_id = %command_id,
                    "Message left in PEL (daemon requested no ACK)"
                );
                // Message stays in PEL for redelivery
                // This could be because the daemon wants to retry later
            }
        }

        Ok(())
    }

    /// Ensure we have a connection to the daemon.
    async fn ensure_daemon_connection(&mut self) -> FalcoResult<()> {
        if self.daemon.is_some() {
            return Ok(());
        }

        info!(
            socket = %self.config.socket_path.display(),
            "Connecting to daemon..."
        );

        let client = connect_with_retry(
            &self.config.socket_path,
            3,                            // max retries
            Duration::from_millis(500),   // retry delay
        )
        .await?;

        self.daemon = Some(client);
        info!("Connected to daemon");

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would require a running Redis and daemon
    // Unit tests for Courier are limited since it orchestrates external services

    #[test]
    fn test_config_stream_key() {
        let config = FalcoConfig::new("test-device".to_string()).unwrap();
        assert_eq!(config.stream_key(), "remote:commands:test-device");
    }
}
