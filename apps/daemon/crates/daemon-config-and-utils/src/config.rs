//! Configuration management for the daemon.

use crate::{CoreError, CoreResult, Paths};
use serde::{Deserialize, Serialize};
use std::path::Path;
use url::Url;

/// Default Supabase URL (can be overridden at compile time via SUPABASE_URL env var).
pub const DEFAULT_SUPABASE_URL: &str = match option_env!("SUPABASE_URL") {
    Some(url) => url,
    None => "https://random.supabase.co",
};

/// Default Supabase publishable key (can be overridden at compile time via SUPABASE_PUBLISHABLE_KEY env var).
pub const DEFAULT_SUPABASE_PUBLISHABLE_KEY: &str = match option_env!("SUPABASE_PUBLISHABLE_KEY") {
    Some(key) => key,
    None => "random-key",
};

/// Default Ably API key (can be overridden at compile time via ABLY_API_KEY env var).
pub const DEFAULT_ABLY_API_KEY: Option<&str> = option_env!("ABLY_API_KEY");

/// Default log level.
pub const DEFAULT_LOG_LEVEL: &str = "info";

/// Main daemon configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Log level (trace, debug, info, warn, error).
    pub log_level: String,
    /// Supabase project URL.
    #[serde(default = "default_supabase_url")]
    pub supabase_url: String,
    /// Supabase publishable API key (public, safe to expose).
    #[serde(default = "default_supabase_publishable_key")]
    pub supabase_publishable_key: String,
    /// Ably API key (optional, for realtime messaging).
    #[serde(default = "default_ably_api_key")]
    pub ably_api_key: Option<String>,
}

fn default_supabase_url() -> String {
    DEFAULT_SUPABASE_URL.to_string()
}

fn default_supabase_publishable_key() -> String {
    DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string()
}

fn default_ably_api_key() -> Option<String> {
    DEFAULT_ABLY_API_KEY.map(|s| s.to_string())
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_level: DEFAULT_LOG_LEVEL.to_string(),
            supabase_url: DEFAULT_SUPABASE_URL.to_string(),
            supabase_publishable_key: DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string(),
            ably_api_key: DEFAULT_ABLY_API_KEY.map(|s| s.to_string()),
        }
    }
}

impl Config {
    /// Create a new Config with default values, then override from environment.
    pub fn new() -> Self {
        let mut config = Self::default();
        config.load_from_env();
        config
    }

    /// Load configuration from a file, falling back to defaults.
    /// Note: supabase_url and supabase_publishable_key are
    /// compile-time only and will always use the built-in defaults,
    /// regardless of what's in the config file.
    pub fn load(paths: &Paths) -> CoreResult<Self> {
        let config_path = paths.config_file();

        let mut config = if config_path.exists() {
            Self::load_from_file(&config_path)?
        } else {
            Self::default()
        };

        // Force compile-time values (never from config file)
        config.supabase_url = DEFAULT_SUPABASE_URL.to_string();
        config.supabase_publishable_key = DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string();
        config.ably_api_key = DEFAULT_ABLY_API_KEY.map(|s| s.to_string());

        // Environment variables can only override log_level
        config.load_from_env();

        Ok(config)
    }

    /// Load configuration from a specific file.
    pub fn load_from_file(path: &Path) -> CoreResult<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = serde_json::from_str(&content)?;
        Ok(config)
    }

    /// Save configuration to a file.
    pub fn save(&self, paths: &Paths) -> CoreResult<()> {
        paths.ensure_dirs()?;
        let config_path = paths.config_file();
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(config_path, content)?;
        Ok(())
    }

    /// Override configuration from environment variables.
    /// Note: supabase_url and supabase_publishable_key are compile-time
    /// only (set via env vars during build). Only log_level can be
    /// overridden at runtime.
    fn load_from_env(&mut self) {
        if let Ok(log_level) = std::env::var("UNBOUND_LOG_LEVEL") {
            self.log_level = log_level;
        }
    }

    /// Get the Supabase URL as a parsed URL.
    pub fn supabase_url(&self) -> CoreResult<Url> {
        Url::parse(&self.supabase_url).map_err(CoreError::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.log_level, DEFAULT_LOG_LEVEL);
        assert_eq!(config.supabase_url, DEFAULT_SUPABASE_URL);
        assert_eq!(
            config.supabase_publishable_key,
            DEFAULT_SUPABASE_PUBLISHABLE_KEY
        );
    }

    #[test]
    fn test_config_load_from_file() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("config.json");

        let config_json = r#"{
            "log_level": "debug"
        }"#;

        std::fs::write(&config_path, config_json).unwrap();

        let config = Config::load_from_file(&config_path).unwrap();
        assert_eq!(config.log_level, "debug");
    }

    #[test]
    fn test_config_save_and_load_roundtrip() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        // Note: supabase_url, supabase_publishable_key are compile-time
        // only and will be forced to defaults on load
        let mut config = Config::default();
        config.log_level = "trace".to_string();

        config.save(&paths).unwrap();

        let loaded = Config::load(&paths).unwrap();
        assert_eq!(loaded.log_level, "trace");
    }

    #[test]
    fn test_config_load_nonexistent_uses_defaults() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        let config = Config::load(&paths).unwrap();
        assert_eq!(config.supabase_url, DEFAULT_SUPABASE_URL);
    }

    #[test]
    fn test_config_supabase_url_parse() {
        let config = Config::default();
        let url = config.supabase_url().unwrap();
        assert_eq!(url.scheme(), "https");
        assert!(url.host_str().unwrap().contains("supabase.co"));
    }

    #[test]
    fn test_config_invalid_url() {
        let mut config = Config::default();
        config.supabase_url = "not a valid url".to_string();

        let result = config.supabase_url();
        assert!(result.is_err());
    }

    #[test]
    fn test_config_new_uses_defaults() {
        std::env::remove_var("UNBOUND_LOG_LEVEL");

        let config = Config::new();
        assert_eq!(config.supabase_url, DEFAULT_SUPABASE_URL);
    }

    #[test]
    fn test_default_constants() {
        assert!(!DEFAULT_LOG_LEVEL.is_empty());
        assert!(!DEFAULT_SUPABASE_URL.is_empty());
        assert!(!DEFAULT_SUPABASE_PUBLISHABLE_KEY.is_empty());
        assert!(DEFAULT_SUPABASE_URL.starts_with("https://"));
        // ABLY_API_KEY is optional (None if not set at compile time)
        let _ = DEFAULT_ABLY_API_KEY;
    }
}
