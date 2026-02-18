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

/// Default web app URL (can be overridden at compile time via UNBOUND_WEB_APP_URL env var).
pub const DEFAULT_WEB_APP_URL: &str = match option_env!("UNBOUND_WEB_APP_URL") {
    Some(url) => url,
    None => "http://localhost:3000",
};

/// Presence DO heartbeat URL (compile-time via UNBOUND_PRESENCE_DO_HEARTBEAT_URL env var).
pub const PRESENCE_DO_HEARTBEAT_URL: Option<&str> =
    option_env!("UNBOUND_PRESENCE_DO_HEARTBEAT_URL");

/// Presence DO bearer token (compile-time via UNBOUND_PRESENCE_DO_TOKEN env var).
pub const PRESENCE_DO_TOKEN: Option<&str> = option_env!("UNBOUND_PRESENCE_DO_TOKEN");

/// Presence DO TTL in milliseconds (compile-time via UNBOUND_PRESENCE_DO_TTL_MS env var).
pub const PRESENCE_DO_TTL_MS: Option<&str> = option_env!("UNBOUND_PRESENCE_DO_TTL_MS");

/// Default log level.
pub const DEFAULT_LOG_LEVEL: &str = "info";
/// Default observability mode (`dev` or `prod`).
pub const DEFAULT_OBSERVABILITY_MODE: &str = "dev";
/// Default PostHog host.
pub const DEFAULT_POSTHOG_HOST: &str = "https://us.i.posthog.com";
/// Default production INFO sample rate.
pub const DEFAULT_OBS_INFO_SAMPLE_RATE: f64 = 0.10;
/// Default production DEBUG sample rate.
pub const DEFAULT_OBS_DEBUG_SAMPLE_RATE: f64 = 0.0;

/// Main daemon configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Log level (trace, debug, info, warn, error).
    pub log_level: String,
    /// Runtime observability mode (`dev` or `prod`).
    #[serde(default = "default_observability_mode")]
    pub observability_mode: String,
    /// Optional PostHog API key for direct daemon export.
    #[serde(default)]
    pub posthog_api_key: Option<String>,
    /// PostHog ingest host.
    #[serde(default = "default_posthog_host")]
    pub posthog_host: String,
    /// Optional Sentry DSN for direct daemon export.
    #[serde(default)]
    pub sentry_dsn: Option<String>,
    /// Production INFO sample rate for remote export.
    #[serde(default = "default_obs_info_sample_rate")]
    pub obs_info_sample_rate: f64,
    /// Production DEBUG sample rate for remote export.
    #[serde(default = "default_obs_debug_sample_rate")]
    pub obs_debug_sample_rate: f64,
    /// Supabase project URL.
    #[serde(default = "default_supabase_url")]
    pub supabase_url: String,
    /// Supabase publishable API key (public, safe to expose).
    #[serde(default = "default_supabase_publishable_key")]
    pub supabase_publishable_key: String,
}

fn default_supabase_url() -> String {
    DEFAULT_SUPABASE_URL.to_string()
}

fn default_supabase_publishable_key() -> String {
    DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string()
}

/// Resolve the compile-time configured web app URL with runtime normalization.
pub fn compile_time_web_app_url() -> String {
    let normalized = DEFAULT_WEB_APP_URL.trim().trim_end_matches('/');
    if normalized.is_empty() {
        "http://localhost:3000".to_string()
    } else {
        normalized.to_string()
    }
}

fn default_observability_mode() -> String {
    DEFAULT_OBSERVABILITY_MODE.to_string()
}

fn default_posthog_host() -> String {
    DEFAULT_POSTHOG_HOST.to_string()
}

fn default_obs_info_sample_rate() -> f64 {
    DEFAULT_OBS_INFO_SAMPLE_RATE
}

fn default_obs_debug_sample_rate() -> f64 {
    DEFAULT_OBS_DEBUG_SAMPLE_RATE
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_level: DEFAULT_LOG_LEVEL.to_string(),
            observability_mode: DEFAULT_OBSERVABILITY_MODE.to_string(),
            posthog_api_key: None,
            posthog_host: DEFAULT_POSTHOG_HOST.to_string(),
            sentry_dsn: None,
            obs_info_sample_rate: DEFAULT_OBS_INFO_SAMPLE_RATE,
            obs_debug_sample_rate: DEFAULT_OBS_DEBUG_SAMPLE_RATE,
            supabase_url: DEFAULT_SUPABASE_URL.to_string(),
            supabase_publishable_key: DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string(),
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

        // Runtime environment variables can override observability and log level.
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
    /// only (set via env vars during build). Runtime env vars can
    /// override log and observability settings.
    fn load_from_env(&mut self) {
        if let Ok(log_level) = std::env::var("UNBOUND_LOG_LEVEL") {
            self.log_level = log_level;
        }

        if let Ok(mode) = std::env::var("UNBOUND_OBS_MODE") {
            let mode = mode.trim().to_ascii_lowercase();
            if mode == "dev" || mode == "prod" || mode == "production" {
                self.observability_mode = if mode == "production" {
                    "prod".to_string()
                } else {
                    mode
                };
            }
        }

        if let Ok(posthog_api_key) = std::env::var("UNBOUND_POSTHOG_API_KEY") {
            let trimmed = posthog_api_key.trim();
            if !trimmed.is_empty() {
                self.posthog_api_key = Some(trimmed.to_string());
            }
        }

        if let Ok(posthog_host) = std::env::var("UNBOUND_POSTHOG_HOST") {
            let trimmed = posthog_host.trim();
            if !trimmed.is_empty() {
                self.posthog_host = trimmed.to_string();
            }
        }

        if let Ok(sentry_dsn) = std::env::var("UNBOUND_SENTRY_DSN") {
            let trimmed = sentry_dsn.trim();
            if !trimmed.is_empty() {
                self.sentry_dsn = Some(trimmed.to_string());
            }
        }

        if let Ok(info_rate) = std::env::var("UNBOUND_OBS_INFO_SAMPLE_RATE") {
            if let Ok(parsed) = info_rate.trim().parse::<f64>() {
                self.obs_info_sample_rate = parsed.clamp(0.0, 1.0);
            }
        }

        if let Ok(debug_rate) = std::env::var("UNBOUND_OBS_DEBUG_SAMPLE_RATE") {
            if let Ok(parsed) = debug_rate.trim().parse::<f64>() {
                self.obs_debug_sample_rate = parsed.clamp(0.0, 1.0);
            }
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
        assert_eq!(config.observability_mode, DEFAULT_OBSERVABILITY_MODE);
        assert_eq!(config.posthog_host, DEFAULT_POSTHOG_HOST);
        assert!(config.posthog_api_key.is_none());
        assert!(config.sentry_dsn.is_none());
        assert_eq!(config.obs_info_sample_rate, DEFAULT_OBS_INFO_SAMPLE_RATE);
        assert_eq!(config.obs_debug_sample_rate, DEFAULT_OBS_DEBUG_SAMPLE_RATE);
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
            "log_level": "debug",
            "observability_mode": "prod",
            "posthog_host": "https://eu.i.posthog.com",
            "obs_info_sample_rate": 0.2,
            "obs_debug_sample_rate": 0.05
        }"#;

        std::fs::write(&config_path, config_json).unwrap();

        let config = Config::load_from_file(&config_path).unwrap();
        assert_eq!(config.log_level, "debug");
        assert_eq!(config.observability_mode, "prod");
        assert_eq!(config.posthog_host, "https://eu.i.posthog.com");
        assert_eq!(config.obs_info_sample_rate, 0.2);
        assert_eq!(config.obs_debug_sample_rate, 0.05);
    }

    #[test]
    fn test_config_save_and_load_roundtrip() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        // Note: supabase_url, supabase_publishable_key are compile-time
        // only and will be forced to defaults on load.
        let mut config = Config::default();
        config.log_level = "trace".to_string();
        config.observability_mode = "prod".to_string();
        config.posthog_host = "https://eu.i.posthog.com".to_string();
        config.obs_info_sample_rate = 0.25;
        config.obs_debug_sample_rate = 0.02;

        config.save(&paths).unwrap();

        let loaded = Config::load(&paths).unwrap();
        assert_eq!(loaded.log_level, "trace");
        assert_eq!(loaded.observability_mode, "prod");
        assert_eq!(loaded.posthog_host, "https://eu.i.posthog.com");
        assert_eq!(loaded.obs_info_sample_rate, 0.25);
        assert_eq!(loaded.obs_debug_sample_rate, 0.02);
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
        std::env::remove_var("UNBOUND_OBS_MODE");
        std::env::remove_var("UNBOUND_POSTHOG_API_KEY");
        std::env::remove_var("UNBOUND_POSTHOG_HOST");
        std::env::remove_var("UNBOUND_SENTRY_DSN");
        std::env::remove_var("UNBOUND_OBS_INFO_SAMPLE_RATE");
        std::env::remove_var("UNBOUND_OBS_DEBUG_SAMPLE_RATE");

        let config = Config::new();
        assert_eq!(config.supabase_url, DEFAULT_SUPABASE_URL);
        assert_eq!(config.observability_mode, DEFAULT_OBSERVABILITY_MODE);
    }

    #[test]
    fn test_load_from_env_applies_observability_settings() {
        std::env::set_var("UNBOUND_LOG_LEVEL", "debug");
        std::env::set_var("UNBOUND_OBS_MODE", "prod");
        std::env::set_var("UNBOUND_POSTHOG_API_KEY", "phc_test");
        std::env::set_var("UNBOUND_POSTHOG_HOST", "https://eu.i.posthog.com");
        std::env::set_var("UNBOUND_SENTRY_DSN", "https://example@sentry.io/123");
        std::env::set_var("UNBOUND_OBS_INFO_SAMPLE_RATE", "0.42");
        std::env::set_var("UNBOUND_OBS_DEBUG_SAMPLE_RATE", "0.05");

        let config = Config::new();

        assert_eq!(config.log_level, "debug");
        assert_eq!(config.observability_mode, "prod");
        assert_eq!(config.posthog_api_key.as_deref(), Some("phc_test"));
        assert_eq!(config.posthog_host, "https://eu.i.posthog.com");
        assert_eq!(
            config.sentry_dsn.as_deref(),
            Some("https://example@sentry.io/123")
        );
        assert_eq!(config.obs_info_sample_rate, 0.42);
        assert_eq!(config.obs_debug_sample_rate, 0.05);

        std::env::remove_var("UNBOUND_LOG_LEVEL");
        std::env::remove_var("UNBOUND_OBS_MODE");
        std::env::remove_var("UNBOUND_POSTHOG_API_KEY");
        std::env::remove_var("UNBOUND_POSTHOG_HOST");
        std::env::remove_var("UNBOUND_SENTRY_DSN");
        std::env::remove_var("UNBOUND_OBS_INFO_SAMPLE_RATE");
        std::env::remove_var("UNBOUND_OBS_DEBUG_SAMPLE_RATE");
    }

    #[test]
    fn test_default_constants() {
        assert!(!DEFAULT_LOG_LEVEL.is_empty());
        assert!(!DEFAULT_OBSERVABILITY_MODE.is_empty());
        assert!(!DEFAULT_POSTHOG_HOST.is_empty());
        assert!(DEFAULT_OBS_INFO_SAMPLE_RATE >= 0.0);
        assert!(DEFAULT_OBS_DEBUG_SAMPLE_RATE >= 0.0);
        assert!(!DEFAULT_SUPABASE_URL.is_empty());
        assert!(!DEFAULT_SUPABASE_PUBLISHABLE_KEY.is_empty());
        assert!(DEFAULT_SUPABASE_URL.starts_with("https://"));
    }
}
