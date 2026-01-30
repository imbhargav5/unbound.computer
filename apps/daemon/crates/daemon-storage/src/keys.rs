//! Storage key constants.

/// Storage keys used by the daemon
pub struct StorageKeys;

impl StorageKeys {
    /// Master key (deprecated - use trusted devices)
    pub const MASTER_KEY: &'static str = "master_key";

    /// Device ID
    pub const DEVICE_ID: &'static str = "device_id";

    /// Device private key
    pub const DEVICE_PRIVATE_KEY: &'static str = "device_private_key";

    /// API key (Unkey token)
    pub const API_KEY: &'static str = "api_key";

    /// Trusted devices (JSON array)
    pub const TRUSTED_DEVICES: &'static str = "trusted_devices";

    /// Supabase access token
    pub const SUPABASE_ACCESS_TOKEN: &'static str = "supabase_access_token";

    /// Supabase refresh token
    pub const SUPABASE_REFRESH_TOKEN: &'static str = "supabase_refresh_token";

    /// Supabase session metadata (JSON)
    pub const SUPABASE_SESSION_META: &'static str = "supabase_session_meta";
}
