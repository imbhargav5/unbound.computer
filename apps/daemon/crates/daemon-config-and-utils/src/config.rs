//! Configuration management for the daemon.

use crate::{CoreError, CoreResult, Paths};
use serde::{Deserialize, Serialize};
use std::path::Path;
use url::Url;

/// Supabase URL from compile time (via SUPABASE_URL env var during build).
/// Empty if not set — `Config::validate()` will reject it.
pub const DEFAULT_SUPABASE_URL: &str = match option_env!("SUPABASE_URL") {
    Some(url) => url,
    None => "",
};

/// Supabase publishable key from compile time (via SUPABASE_PUBLISHABLE_KEY env var during build).
/// Empty if not set — `Config::validate()` will reject it.
pub const DEFAULT_SUPABASE_PUBLISHABLE_KEY: &str = match option_env!("SUPABASE_PUBLISHABLE_KEY") {
    Some(key) => key,
    None => "",
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
/// Default runtime environment (`dev` or `prod`).
pub const DEFAULT_ENVIRONMENT: &str = "dev";
/// Default OTEL sampler.
pub const DEFAULT_OTEL_SAMPLER: &str = "always_on";
/// Default OTEL sampler argument.
pub const DEFAULT_OTEL_SAMPLER_ARG: f64 = 1.0;

/// Main daemon configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Log level (trace, debug, info, warn, error).
    pub log_level: String,
    /// Runtime environment (`dev` or `prod`).
    #[serde(default = "default_environment")]
    pub environment: String,
    /// Optional OTLP traces endpoint.
    #[serde(default)]
    pub otel_endpoint: Option<String>,
    /// Optional OTLP headers encoded as `k=v,k2=v2`.
    #[serde(default)]
    pub otel_headers: Option<String>,
    /// OTEL sampler (`always_on`, `parentbased_traceidratio`).
    #[serde(default = "default_otel_sampler")]
    pub otel_sampler: String,
    /// OTEL trace sampler argument (ratio for ratio-based samplers).
    #[serde(default = "default_otel_sampler_arg")]
    pub otel_sampler_arg: f64,
    /// Supabase project URL.
    #[serde(default = "default_supabase_url")]
    pub supabase_url: String,
    /// Supabase publishable API key (public, safe to expose).
    #[serde(default = "default_supabase_publishable_key")]
    pub supabase_publishable_key: String,
    /// Web app URL used for social login, Ably token requests, and billing.
    #[serde(default = "default_web_app_url")]
    pub web_app_url: String,
    /// Presence DO heartbeat URL.
    #[serde(default)]
    pub presence_do_heartbeat_url: Option<String>,
    /// Presence DO bearer token.
    #[serde(default)]
    pub presence_do_token: Option<String>,
    /// Presence DO TTL in milliseconds.
    #[serde(default)]
    pub presence_do_ttl_ms: Option<String>,
}

fn default_supabase_url() -> String {
    DEFAULT_SUPABASE_URL.to_string()
}

fn default_supabase_publishable_key() -> String {
    DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string()
}

fn default_environment() -> String {
    DEFAULT_ENVIRONMENT.to_string()
}

fn default_otel_sampler() -> String {
    DEFAULT_OTEL_SAMPLER.to_string()
}

fn default_otel_sampler_arg() -> f64 {
    DEFAULT_OTEL_SAMPLER_ARG
}

fn default_web_app_url() -> String {
    normalize_web_app_url(DEFAULT_WEB_APP_URL)
}

fn default_presence_do_heartbeat_url() -> Option<String> {
    PRESENCE_DO_HEARTBEAT_URL.map(String::from)
}

fn default_presence_do_token() -> Option<String> {
    PRESENCE_DO_TOKEN.map(String::from)
}

fn default_presence_do_ttl_ms() -> Option<String> {
    PRESENCE_DO_TTL_MS.map(String::from)
}

/// Normalize a web app URL: trim whitespace and trailing slashes.
fn normalize_web_app_url(raw: &str) -> String {
    let normalized = raw.trim().trim_end_matches('/');
    if normalized.is_empty() {
        "http://localhost:3000".to_string()
    } else {
        normalized.to_string()
    }
}

/// Resolve the web app URL, checking runtime env first, then compile-time default.
/// Provided for backward compatibility with callers not yet migrated to Config.
pub fn compile_time_web_app_url() -> String {
    if let Ok(val) = std::env::var("UNBOUND_WEB_APP_URL") {
        let trimmed = val.trim().trim_end_matches('/');
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    normalize_web_app_url(DEFAULT_WEB_APP_URL)
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_level: DEFAULT_LOG_LEVEL.to_string(),
            environment: DEFAULT_ENVIRONMENT.to_string(),
            otel_endpoint: None,
            otel_headers: None,
            otel_sampler: DEFAULT_OTEL_SAMPLER.to_string(),
            otel_sampler_arg: DEFAULT_OTEL_SAMPLER_ARG,
            supabase_url: DEFAULT_SUPABASE_URL.to_string(),
            supabase_publishable_key: DEFAULT_SUPABASE_PUBLISHABLE_KEY.to_string(),
            web_app_url: default_web_app_url(),
            presence_do_heartbeat_url: default_presence_do_heartbeat_url(),
            presence_do_token: default_presence_do_token(),
            presence_do_ttl_ms: default_presence_do_ttl_ms(),
        }
    }
}

impl Config {
    /// Create a new Config with default values, then override from environment.
    pub fn new() -> CoreResult<Self> {
        let mut config = Self::default();
        config.load_from_env();
        config.validate()?;
        Ok(config)
    }

    /// Load configuration from a file, falling back to defaults.
    ///
    /// Precedence (highest wins):
    /// 1. Runtime env var (set by DaemonLauncher or shell)
    /// 2. Config file (`~/.unbound-dev/config.json`)
    /// 3. Compile-time default (`option_env!()` baked into binary)
    /// 4. Hardcoded fallback
    pub fn load(paths: &Paths) -> CoreResult<Self> {
        let config_path = paths.config_file();

        let mut config = if config_path.exists() {
            Self::load_from_file(&config_path)?
        } else {
            Self::default()
        };

        // Runtime environment variables override everything.
        config.load_from_env();
        config.validate()?;

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
    ///
    /// Runtime env vars have the highest precedence, overriding both
    /// config file values and compile-time defaults.
    fn load_from_env(&mut self) {
        if let Ok(log_level) = std::env::var("UNBOUND_LOG_LEVEL") {
            self.log_level = log_level;
        }

        if let Ok(environment) = std::env::var("UNBOUND_ENV") {
            let mode = environment.trim().to_ascii_lowercase();
            if mode == "dev" || mode == "prod" || mode == "production" {
                self.environment = if mode == "production" {
                    "prod".to_string()
                } else {
                    mode
                };
            }
        }

        if let Ok(endpoint) = std::env::var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT") {
            let trimmed = endpoint.trim();
            if !trimmed.is_empty() {
                self.otel_endpoint = Some(trimmed.to_string());
            }
        }

        if let Ok(headers) = std::env::var("UNBOUND_OTEL_HEADERS") {
            let trimmed = headers.trim();
            if !trimmed.is_empty() {
                self.otel_headers = Some(trimmed.to_string());
            }
        }

        if let Ok(sampler) = std::env::var("UNBOUND_OTEL_SAMPLER") {
            let trimmed = sampler.trim().to_ascii_lowercase();
            if !trimmed.is_empty() {
                self.otel_sampler = trimmed;
            }
        }

        if let Ok(sampler_arg) = std::env::var("UNBOUND_OTEL_TRACES_SAMPLER_ARG") {
            if let Ok(parsed) = sampler_arg.trim().parse::<f64>() {
                self.otel_sampler_arg = parsed.clamp(0.0, 1.0);
            }
        }

        // Supabase config
        if let Ok(url) = std::env::var("SUPABASE_URL") {
            let trimmed = url.trim();
            if !trimmed.is_empty() {
                self.supabase_url = trimmed.to_string();
            }
        }

        if let Ok(key) = std::env::var("SUPABASE_PUBLISHABLE_KEY") {
            let trimmed = key.trim();
            if !trimmed.is_empty() {
                self.supabase_publishable_key = trimmed.to_string();
            }
        }

        // Web app URL
        if let Ok(url) = std::env::var("UNBOUND_WEB_APP_URL") {
            let normalized = url.trim().trim_end_matches('/');
            if !normalized.is_empty() {
                self.web_app_url = normalized.to_string();
            }
        }

        // Presence DO config
        if let Ok(url) = std::env::var("UNBOUND_PRESENCE_DO_HEARTBEAT_URL") {
            let trimmed = url.trim();
            if !trimmed.is_empty() {
                self.presence_do_heartbeat_url = Some(trimmed.to_string());
            }
        }

        if let Ok(token) = std::env::var("UNBOUND_PRESENCE_DO_TOKEN") {
            let trimmed = token.trim();
            if !trimmed.is_empty() {
                self.presence_do_token = Some(trimmed.to_string());
            }
        }

        if let Ok(ttl) = std::env::var("UNBOUND_PRESENCE_DO_TTL_MS") {
            let trimmed = ttl.trim();
            if !trimmed.is_empty() {
                self.presence_do_ttl_ms = Some(trimmed.to_string());
            }
        }
    }

    /// Fail fast if required config values are missing.
    fn validate(&self) -> CoreResult<()> {
        if self.supabase_url.is_empty() {
            return Err(CoreError::Config(
                "SUPABASE_URL is not set. Provide it via env var, .env.local, or config file."
                    .into(),
            ));
        }
        if self.supabase_publishable_key.is_empty() {
            return Err(CoreError::Config(
                "SUPABASE_PUBLISHABLE_KEY is not set. Provide it via env var, .env.local, or config file."
                    .into(),
            ));
        }
        Ok(())
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

    fn valid_config() -> Config {
        Config {
            supabase_url: "https://test.supabase.co".to_string(),
            supabase_publishable_key: "test-key".to_string(),
            ..Config::default()
        }
    }

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.log_level, DEFAULT_LOG_LEVEL);
        assert_eq!(config.environment, DEFAULT_ENVIRONMENT);
        assert!(config.otel_endpoint.is_none());
        assert!(config.otel_headers.is_none());
        assert_eq!(config.otel_sampler, DEFAULT_OTEL_SAMPLER);
        assert_eq!(config.otel_sampler_arg, DEFAULT_OTEL_SAMPLER_ARG);
        assert_eq!(config.web_app_url, normalize_web_app_url(DEFAULT_WEB_APP_URL));
    }

    #[test]
    fn test_config_load_from_file() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("config.json");

        let config_json = r#"{
            "log_level": "debug",
            "environment": "prod",
            "supabase_url": "https://real.supabase.co",
            "supabase_publishable_key": "real-key",
            "otel_endpoint": "http://localhost:4318/v1/traces",
            "otel_sampler": "parentbased_traceidratio",
            "otel_sampler_arg": 0.2
        }"#;

        std::fs::write(&config_path, config_json).unwrap();

        let config = Config::load_from_file(&config_path).unwrap();
        assert_eq!(config.log_level, "debug");
        assert_eq!(config.environment, "prod");
        assert_eq!(config.supabase_url, "https://real.supabase.co");
        assert_eq!(config.supabase_publishable_key, "real-key");
        assert_eq!(
            config.otel_endpoint.as_deref(),
            Some("http://localhost:4318/v1/traces")
        );
        assert_eq!(config.otel_sampler, "parentbased_traceidratio");
        assert_eq!(config.otel_sampler_arg, 0.2);
    }

    #[test]
    fn test_config_save_and_roundtrip() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        let mut config = valid_config();
        config.log_level = "trace".to_string();
        config.environment = "prod".to_string();
        config.otel_endpoint = Some("https://otel.example/v1/traces".to_string());
        config.otel_sampler = "parentbased_traceidratio".to_string();
        config.otel_sampler_arg = 0.1;

        config.save(&paths).unwrap();

        let loaded = Config::load_from_file(&paths.config_file()).unwrap();
        assert_eq!(loaded.log_level, "trace");
        assert_eq!(loaded.environment, "prod");
        assert_eq!(loaded.supabase_url, "https://test.supabase.co");
        assert_eq!(
            loaded.otel_endpoint.as_deref(),
            Some("https://otel.example/v1/traces")
        );
    }

    #[test]
    fn test_validate_rejects_empty_supabase_url() {
        let mut config = valid_config();
        config.supabase_url = String::new();

        let result = config.validate();
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("SUPABASE_URL"));
    }

    #[test]
    fn test_validate_rejects_empty_supabase_key() {
        let mut config = valid_config();
        config.supabase_publishable_key = String::new();

        let result = config.validate();
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("SUPABASE_PUBLISHABLE_KEY"));
    }

    #[test]
    fn test_validate_passes_with_valid_config() {
        let config = valid_config();
        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_normalize_web_app_url() {
        assert_eq!(normalize_web_app_url("https://example.com/"), "https://example.com");
        assert_eq!(normalize_web_app_url("  https://example.com  "), "https://example.com");
        assert_eq!(normalize_web_app_url(""), "http://localhost:3000");
        assert_eq!(normalize_web_app_url("  "), "http://localhost:3000");
    }

    #[test]
    fn test_compile_time_web_app_url_fallback() {
        // When no env var is set, falls back to compile-time default
        std::env::remove_var("UNBOUND_WEB_APP_URL");
        let url = compile_time_web_app_url();
        assert!(!url.is_empty());
        assert!(!url.ends_with('/'));
    }
}
