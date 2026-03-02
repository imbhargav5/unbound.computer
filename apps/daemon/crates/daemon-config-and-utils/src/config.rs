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

/// Resolve the compile-time configured web app URL with runtime normalization.
pub fn compile_time_web_app_url() -> String {
    let normalized = DEFAULT_WEB_APP_URL.trim().trim_end_matches('/');
    if normalized.is_empty() {
        "http://localhost:3000".to_string()
    } else {
        normalized.to_string()
    }
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
        assert_eq!(config.environment, DEFAULT_ENVIRONMENT);
        assert!(config.otel_endpoint.is_none());
        assert!(config.otel_headers.is_none());
        assert_eq!(config.otel_sampler, DEFAULT_OTEL_SAMPLER);
        assert_eq!(config.otel_sampler_arg, DEFAULT_OTEL_SAMPLER_ARG);
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
            "environment": "prod",
            "otel_endpoint": "http://localhost:4318/v1/traces",
            "otel_sampler": "parentbased_traceidratio",
            "otel_sampler_arg": 0.2
        }"#;

        std::fs::write(&config_path, config_json).unwrap();

        let config = Config::load_from_file(&config_path).unwrap();
        assert_eq!(config.log_level, "debug");
        assert_eq!(config.environment, "prod");
        assert_eq!(
            config.otel_endpoint.as_deref(),
            Some("http://localhost:4318/v1/traces")
        );
        assert_eq!(config.otel_sampler, "parentbased_traceidratio");
        assert_eq!(config.otel_sampler_arg, 0.2);
    }

    #[test]
    fn test_config_save_and_load() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        let mut config = Config::default();
        config.log_level = "trace".to_string();
        config.environment = "prod".to_string();
        config.otel_endpoint = Some("https://otel.example/v1/traces".to_string());
        config.otel_sampler = "parentbased_traceidratio".to_string();
        config.otel_sampler_arg = 0.1;

        config.save(&paths).unwrap();

        let loaded = Config::load(&paths).unwrap();
        assert_eq!(loaded.log_level, "trace");
        assert_eq!(loaded.environment, "prod");
        assert_eq!(
            loaded.otel_endpoint.as_deref(),
            Some("https://otel.example/v1/traces")
        );
        assert_eq!(loaded.otel_sampler, "parentbased_traceidratio");
        assert_eq!(loaded.otel_sampler_arg, 0.1);
    }

    #[test]
    fn test_environment_override() {
        std::env::remove_var("UNBOUND_ENV");
        std::env::remove_var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT");
        std::env::remove_var("UNBOUND_OTEL_HEADERS");
        std::env::remove_var("UNBOUND_OTEL_SAMPLER");
        std::env::remove_var("UNBOUND_OTEL_TRACES_SAMPLER_ARG");

        let config = Config::new();
        assert_eq!(config.environment, DEFAULT_ENVIRONMENT);

        std::env::set_var("UNBOUND_ENV", "prod");
        std::env::set_var(
            "UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT",
            "https://otel.example/v1/traces",
        );
        std::env::set_var("UNBOUND_OTEL_HEADERS", "authorization=Bearer token");
        std::env::set_var("UNBOUND_OTEL_SAMPLER", "parentbased_traceidratio");
        std::env::set_var("UNBOUND_OTEL_TRACES_SAMPLER_ARG", "0.42");

        let config = Config::new();
        assert_eq!(config.environment, "prod");
        assert_eq!(
            config.otel_endpoint.as_deref(),
            Some("https://otel.example/v1/traces")
        );
        assert_eq!(
            config.otel_headers.as_deref(),
            Some("authorization=Bearer token")
        );
        assert_eq!(config.otel_sampler, "parentbased_traceidratio");
        assert_eq!(config.otel_sampler_arg, 0.42);

        std::env::remove_var("UNBOUND_ENV");
        std::env::remove_var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT");
        std::env::remove_var("UNBOUND_OTEL_HEADERS");
        std::env::remove_var("UNBOUND_OTEL_SAMPLER");
        std::env::remove_var("UNBOUND_OTEL_TRACES_SAMPLER_ARG");
    }
}
