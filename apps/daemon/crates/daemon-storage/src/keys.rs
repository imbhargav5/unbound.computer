//! Storage key constants.

/// Storage keys used by the daemon
pub struct StorageKeys;

impl StorageKeys {
    /// Device ID
    pub const DEVICE_ID: &'static str = "device_id";

    /// Device private key
    pub const DEVICE_PRIVATE_KEY: &'static str = "device_private_key";

    /// API key (Unkey token)
    pub const API_KEY: &'static str = "api_key";
}
