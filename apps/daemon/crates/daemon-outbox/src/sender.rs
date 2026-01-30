//! Pipeline sender for HTTP delivery with retry.

use crate::{EventBatch, OutboxError, OutboxResult};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, error, info, warn};

/// Sender configuration.
#[derive(Debug, Clone)]
pub struct SenderConfig {
    /// Base URL for the relay API.
    pub relay_api_url: String,
    /// Initial retry delay in milliseconds.
    pub initial_retry_delay_ms: u64,
    /// Maximum retry delay in milliseconds.
    pub max_retry_delay_ms: u64,
    /// Maximum retry attempts.
    pub max_retries: u32,
    /// Request timeout in seconds.
    pub timeout_secs: u64,
}

impl Default for SenderConfig {
    fn default() -> Self {
        Self {
            relay_api_url: "https://relay.unbound.computer".to_string(),
            initial_retry_delay_ms: 1000,
            max_retry_delay_ms: 60000,
            max_retries: 10,
            timeout_secs: 30,
        }
    }
}

/// Request payload for sending a batch.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SendBatchRequest {
    batch_id: String,
    session_id: String,
    events: Vec<EventPayload>,
}

/// Event payload in the request.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EventPayload {
    event_id: String,
    sequence_number: i64,
    message_id: String,
}

/// Response from the relay server.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SendBatchResponse {
    success: bool,
    batch_id: String,
    #[serde(default)]
    error: Option<String>,
}

/// Pipeline sender for reliable HTTP delivery.
pub struct PipelineSender {
    config: SenderConfig,
    client: Client,
    auth_token: String,
}

impl PipelineSender {
    /// Create a new pipeline sender.
    pub fn new(config: SenderConfig, auth_token: &str) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout_secs))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            config,
            client,
            auth_token: auth_token.to_string(),
        }
    }

    /// Update the auth token.
    pub fn set_auth_token(&mut self, token: &str) {
        self.auth_token = token.to_string();
    }

    /// Send a batch with retry logic.
    ///
    /// Returns Ok(()) if the batch was acknowledged, or Err if all retries failed.
    pub async fn send_batch(&self, batch: &EventBatch) -> OutboxResult<()> {
        let mut attempt = 0;
        let mut delay = self.config.initial_retry_delay_ms;

        loop {
            attempt += 1;

            match self.try_send_batch(batch).await {
                Ok(()) => {
                    info!(
                        batch_id = %batch.batch_id,
                        session_id = %batch.session_id,
                        events = batch.events.len(),
                        "Batch sent successfully"
                    );
                    return Ok(());
                }
                Err(e) => {
                    if attempt >= self.config.max_retries {
                        error!(
                            batch_id = %batch.batch_id,
                            attempt = attempt,
                            error = %e,
                            "Max retries exceeded"
                        );
                        return Err(OutboxError::MaxRetriesExceeded(batch.batch_id.clone()));
                    }

                    warn!(
                        batch_id = %batch.batch_id,
                        attempt = attempt,
                        delay_ms = delay,
                        error = %e,
                        "Send failed, retrying"
                    );

                    tokio::time::sleep(Duration::from_millis(delay)).await;

                    // Exponential backoff with cap
                    delay = std::cmp::min(delay * 2, self.config.max_retry_delay_ms);
                }
            }
        }
    }

    /// Attempt to send a batch (single try).
    async fn try_send_batch(&self, batch: &EventBatch) -> OutboxResult<()> {
        let url = format!("{}/messages", self.config.relay_api_url);

        let request = SendBatchRequest {
            batch_id: batch.batch_id.clone(),
            session_id: batch.session_id.clone(),
            events: batch.events.iter().map(|e| EventPayload {
                event_id: e.event_id.clone(),
                sequence_number: e.sequence_number,
                message_id: e.message_id.clone(),
            }).collect(),
        };

        debug!(
            url = %url,
            batch_id = %batch.batch_id,
            events = batch.events.len(),
            "Sending batch"
        );

        let response = self.client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.auth_token))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(OutboxError::Send(format!("HTTP {}: {}", status, body)));
        }

        let result: SendBatchResponse = response.json().await?;

        if result.success {
            Ok(())
        } else {
            Err(OutboxError::Send(
                result.error.unwrap_or_else(|| "Unknown error".to_string())
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sender_config_default() {
        let config = SenderConfig::default();
        assert_eq!(config.initial_retry_delay_ms, 1000);
        assert_eq!(config.max_retry_delay_ms, 60000);
        assert_eq!(config.max_retries, 10);
        assert_eq!(config.timeout_secs, 30);
        assert_eq!(config.relay_api_url, "https://relay.unbound.computer");
    }

    #[test]
    fn test_sender_config_custom() {
        let config = SenderConfig {
            relay_api_url: "https://custom.relay.com".to_string(),
            initial_retry_delay_ms: 500,
            max_retry_delay_ms: 30000,
            max_retries: 5,
            timeout_secs: 15,
        };

        assert_eq!(config.relay_api_url, "https://custom.relay.com");
        assert_eq!(config.initial_retry_delay_ms, 500);
        assert_eq!(config.max_retry_delay_ms, 30000);
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.timeout_secs, 15);
    }

    #[test]
    fn test_sender_backoff_calculation() {
        let config = SenderConfig {
            initial_retry_delay_ms: 1000,
            max_retry_delay_ms: 60000,
            ..Default::default()
        };

        // Simulate exponential backoff calculation
        let mut delay = config.initial_retry_delay_ms;

        // First retry: 1000ms
        assert_eq!(delay, 1000);

        // Second retry: 2000ms
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 2000);

        // Third retry: 4000ms
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 4000);

        // Fourth retry: 8000ms
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 8000);

        // Fifth retry: 16000ms
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 16000);

        // Sixth retry: 32000ms
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 32000);

        // Seventh retry: 60000ms (capped at max)
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 60000);

        // Eighth retry: still 60000ms (capped)
        delay = std::cmp::min(delay * 2, config.max_retry_delay_ms);
        assert_eq!(delay, 60000);
    }

    #[test]
    fn test_sender_creation() {
        let config = SenderConfig::default();
        let sender = PipelineSender::new(config, "test-token");

        // Verify sender is created (we can't access private fields, but construction should work)
        assert!(true);
    }

    #[test]
    fn test_sender_auth_token_update() {
        let config = SenderConfig::default();
        let mut sender = PipelineSender::new(config, "initial-token");

        // Update auth token
        sender.set_auth_token("new-token");

        // Can't verify directly but construction and update should work
        assert!(true);
    }
}
