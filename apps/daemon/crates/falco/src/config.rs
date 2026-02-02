//! Configuration for Falco.

use crate::error::{FalcoError, FalcoResult};
use daemon_core::Paths;
use std::path::PathBuf;
use std::time::Duration;

/// Falco configuration.
#[derive(Debug, Clone)]
pub struct FalcoConfig {
    /// Redis connection URL
    pub redis_url: String,

    /// Device ID for the Redis stream key
    pub device_id: String,

    /// Path to the Falco Unix socket
    pub socket_path: PathBuf,

    /// Timeout for daemon response (fail-open escape hatch)
    pub daemon_timeout: Duration,

    /// XREADGROUP block timeout in milliseconds
    pub block_timeout_ms: u64,

    /// Consumer group name
    pub consumer_group: String,

    /// Consumer name (unique per instance)
    pub consumer_name: String,
}

impl FalcoConfig {
    /// Create a new FalcoConfig with the given device ID.
    ///
    /// Uses default values for other settings, which can be overridden
    /// via environment variables.
    pub fn new(device_id: String) -> FalcoResult<Self> {
        let paths = Paths::new().map_err(|e| FalcoError::Config(e.to_string()))?;

        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

        let socket_path = std::env::var("FALCO_SOCKET")
            .map(PathBuf::from)
            .unwrap_or_else(|_| paths.base_dir().join("falco.sock"));

        let daemon_timeout_secs: u64 = std::env::var("FALCO_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(15);

        let block_timeout_ms: u64 = std::env::var("FALCO_BLOCK_MS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(5000);

        let consumer_name = format!("falco-{}", uuid::Uuid::new_v4());

        Ok(Self {
            redis_url,
            device_id,
            socket_path,
            daemon_timeout: Duration::from_secs(daemon_timeout_secs),
            block_timeout_ms,
            consumer_group: "falco".to_string(),
            consumer_name,
        })
    }

    /// Get the Redis stream key for this device.
    pub fn stream_key(&self) -> String {
        format!("remote:commands:{}", self.device_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let config = FalcoConfig::new("test-device-123".to_string()).unwrap();

        assert_eq!(config.device_id, "test-device-123");
        assert_eq!(config.consumer_group, "falco");
        assert!(config.consumer_name.starts_with("falco-"));
        assert_eq!(config.daemon_timeout, Duration::from_secs(15));
        assert_eq!(config.block_timeout_ms, 5000);
    }

    #[test]
    fn test_stream_key() {
        let config = FalcoConfig::new("device-abc".to_string()).unwrap();
        assert_eq!(config.stream_key(), "remote:commands:device-abc");
    }
}
