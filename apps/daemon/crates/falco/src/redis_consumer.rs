//! Redis Streams consumer for Falco.
//!
//! Handles XREADGROUP and XACK operations against the remote commands stream.

use crate::config::FalcoConfig;
use crate::error::{FalcoError, FalcoResult};
use redis::aio::MultiplexedConnection;
use redis::{AsyncCommands, Client, RedisResult};
use tracing::{debug, info, warn};

/// A message read from the Redis stream.
#[derive(Debug, Clone)]
pub struct StreamMessage {
    /// The Redis message ID (e.g., "1234567890-0").
    pub message_id: String,
    /// The encrypted payload bytes.
    pub encrypted_payload: Vec<u8>,
}

/// Redis Streams consumer.
pub struct RedisConsumer {
    client: Client,
    conn: MultiplexedConnection,
    config: FalcoConfig,
}

impl RedisConsumer {
    /// Create a new RedisConsumer and connect to Redis.
    pub async fn connect(config: FalcoConfig) -> FalcoResult<Self> {
        let client = Client::open(config.redis_url.as_str())?;
        let conn = client.get_multiplexed_async_connection().await?;

        let consumer = Self { client, conn, config };

        // Ensure the consumer group exists
        consumer.ensure_consumer_group().await?;

        Ok(consumer)
    }

    /// Ensure the consumer group exists, creating it if necessary.
    async fn ensure_consumer_group(&self) -> FalcoResult<()> {
        let stream_key = self.config.stream_key();

        // Try to create the consumer group
        // XGROUP CREATE key groupname id [MKSTREAM]
        // Use $ to only get new messages, or 0 to replay all
        let result: RedisResult<()> = redis::cmd("XGROUP")
            .arg("CREATE")
            .arg(&stream_key)
            .arg(&self.config.consumer_group)
            .arg("$")
            .arg("MKSTREAM")
            .query_async(&mut self.conn.clone())
            .await;

        match result {
            Ok(()) => {
                info!(
                    stream = %stream_key,
                    group = %self.config.consumer_group,
                    "Created consumer group"
                );
            }
            Err(e) => {
                // BUSYGROUP means the group already exists, which is fine
                if e.to_string().contains("BUSYGROUP") {
                    debug!(
                        stream = %stream_key,
                        group = %self.config.consumer_group,
                        "Consumer group already exists"
                    );
                } else {
                    return Err(e.into());
                }
            }
        }

        Ok(())
    }

    /// Read the next message from the stream.
    ///
    /// This performs a blocking XREADGROUP with COUNT=1.
    /// Returns `None` if the block timeout expires with no messages.
    pub async fn read_next(&mut self) -> FalcoResult<Option<StreamMessage>> {
        let stream_key = self.config.stream_key();

        // XREADGROUP GROUP groupname consumername [COUNT count] [BLOCK milliseconds] STREAMS key [key ...] id [id ...]
        // Using ">" to get only new messages not yet delivered to this consumer
        let result: RedisResult<redis::Value> = redis::cmd("XREADGROUP")
            .arg("GROUP")
            .arg(&self.config.consumer_group)
            .arg(&self.config.consumer_name)
            .arg("COUNT")
            .arg(1)
            .arg("BLOCK")
            .arg(self.config.block_timeout_ms)
            .arg("STREAMS")
            .arg(&stream_key)
            .arg(">")
            .query_async(&mut self.conn)
            .await;

        match result {
            Ok(redis::Value::Nil) => {
                // Block timeout expired, no messages
                Ok(None)
            }
            Ok(value) => {
                // Parse the response
                self.parse_xreadgroup_response(value)
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Parse the XREADGROUP response to extract the message.
    fn parse_xreadgroup_response(&self, value: redis::Value) -> FalcoResult<Option<StreamMessage>> {
        // Response format:
        // [[stream_key, [[message_id, [field1, value1, field2, value2, ...]]]]]

        let streams = match value {
            redis::Value::Array(streams) => streams,
            redis::Value::Nil => return Ok(None),
            _ => {
                return Err(FalcoError::Protocol(format!(
                    "Unexpected XREADGROUP response type: {:?}",
                    value
                )))
            }
        };

        if streams.is_empty() {
            return Ok(None);
        }

        // Get the first stream
        let stream = match &streams[0] {
            redis::Value::Array(s) => s,
            _ => {
                return Err(FalcoError::Protocol(
                    "Expected array for stream entry".to_string(),
                ))
            }
        };

        if stream.len() < 2 {
            return Err(FalcoError::Protocol("Stream entry too short".to_string()));
        }

        // Get messages array
        let messages = match &stream[1] {
            redis::Value::Array(m) => m,
            _ => {
                return Err(FalcoError::Protocol(
                    "Expected array for messages".to_string(),
                ))
            }
        };

        if messages.is_empty() {
            return Ok(None);
        }

        // Get first message
        let message = match &messages[0] {
            redis::Value::Array(m) => m,
            _ => {
                return Err(FalcoError::Protocol(
                    "Expected array for message".to_string(),
                ))
            }
        };

        if message.len() < 2 {
            return Err(FalcoError::Protocol("Message entry too short".to_string()));
        }

        // Extract message ID
        let message_id = match &message[0] {
            redis::Value::BulkString(s) => String::from_utf8_lossy(s).to_string(),
            redis::Value::SimpleString(s) => s.clone(),
            _ => {
                return Err(FalcoError::Protocol(format!(
                    "Expected string for message ID, got {:?}",
                    message[0]
                )))
            }
        };

        // Extract fields
        let fields = match &message[1] {
            redis::Value::Array(f) => f,
            _ => {
                return Err(FalcoError::Protocol(
                    "Expected array for fields".to_string(),
                ))
            }
        };

        // Find the encrypted_payload field
        let mut encrypted_payload = None;
        let mut i = 0;
        while i + 1 < fields.len() {
            let field_name = match &fields[i] {
                redis::Value::BulkString(s) => String::from_utf8_lossy(s).to_string(),
                redis::Value::SimpleString(s) => s.clone(),
                _ => {
                    i += 2;
                    continue;
                }
            };

            if field_name == "encrypted_payload" {
                encrypted_payload = match &fields[i + 1] {
                    redis::Value::BulkString(s) => Some(s.clone()),
                    redis::Value::SimpleString(s) => Some(s.as_bytes().to_vec()),
                    _ => None,
                };
                break;
            }
            i += 2;
        }

        let encrypted_payload = encrypted_payload.ok_or_else(|| {
            FalcoError::Protocol("Message missing encrypted_payload field".to_string())
        })?;

        debug!(
            message_id = %message_id,
            payload_len = encrypted_payload.len(),
            "Read message from stream"
        );

        Ok(Some(StreamMessage {
            message_id,
            encrypted_payload,
        }))
    }

    /// Acknowledge a message, removing it from the PEL.
    pub async fn ack(&mut self, message_id: &str) -> FalcoResult<()> {
        let stream_key = self.config.stream_key();

        let result: i64 = self
            .conn
            .xack(&stream_key, &self.config.consumer_group, &[message_id])
            .await?;

        if result == 1 {
            debug!(
                message_id = %message_id,
                stream = %stream_key,
                "Acknowledged message"
            );
        } else {
            warn!(
                message_id = %message_id,
                stream = %stream_key,
                "XACK returned {}, message may not exist",
                result
            );
        }

        Ok(())
    }

    /// Get the number of pending messages for this consumer.
    #[allow(dead_code)]
    pub async fn pending_count(&mut self) -> FalcoResult<i64> {
        let stream_key = self.config.stream_key();

        // XPENDING key group
        let result: redis::Value = redis::cmd("XPENDING")
            .arg(&stream_key)
            .arg(&self.config.consumer_group)
            .query_async(&mut self.conn)
            .await?;

        // Response is [count, min_id, max_id, [[consumer, count], ...]]
        if let redis::Value::Array(arr) = result {
            if !arr.is_empty() {
                if let redis::Value::Int(count) = arr[0] {
                    return Ok(count);
                }
            }
        }

        Ok(0)
    }

    /// Reconnect to Redis.
    pub async fn reconnect(&mut self) -> FalcoResult<()> {
        info!("Reconnecting to Redis...");
        self.conn = self.client.get_multiplexed_async_connection().await?;
        self.ensure_consumer_group().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stream_message_clone() {
        let msg = StreamMessage {
            message_id: "1234-0".to_string(),
            encrypted_payload: vec![1, 2, 3, 4],
        };

        let cloned = msg.clone();
        assert_eq!(cloned.message_id, msg.message_id);
        assert_eq!(cloned.encrypted_payload, msg.encrypted_payload);
    }
}
