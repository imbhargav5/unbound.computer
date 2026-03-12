//! Configuration management for the daemon.

use crate::{CoreResult, Paths};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Default log level.
pub const DEFAULT_LOG_LEVEL: &str = "info";
/// Default runtime environment (`dev` or `prod`).
pub const DEFAULT_ENVIRONMENT: &str = "dev";
/// Default OTEL sampler.
pub const DEFAULT_OTEL_SAMPLER: &str = "always_on";
/// Default OTEL sampler argument.
pub const DEFAULT_OTEL_SAMPLER_ARG: f64 = 1.0;

/// Main daemon configuration for local-only operation.
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

impl Default for Config {
    fn default() -> Self {
        Self {
            log_level: DEFAULT_LOG_LEVEL.to_string(),
            environment: DEFAULT_ENVIRONMENT.to_string(),
            otel_endpoint: None,
            otel_headers: None,
            otel_sampler: DEFAULT_OTEL_SAMPLER.to_string(),
            otel_sampler_arg: DEFAULT_OTEL_SAMPLER_ARG,
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
    pub fn load(paths: &Paths) -> CoreResult<Self> {
        let config_path = paths.config_file();

        let mut config = if config_path.exists() {
            Self::load_from_file(&config_path)?
        } else {
            Self::default()
        };

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
    fn load_from_env(&mut self) {
        if let Ok(log_level) = std::env::var("UNBOUND_LOG_LEVEL") {
            let trimmed = log_level.trim();
            if !trimmed.is_empty() {
                self.log_level = trimmed.to_string();
            }
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

    fn validate(&self) -> CoreResult<()> {
        Ok(())
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
    fn test_config_save_and_roundtrip() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        let config = Config {
            log_level: "trace".to_string(),
            environment: "prod".to_string(),
            otel_endpoint: Some("https://otel.example/v1/traces".to_string()),
            otel_headers: Some("authorization=token".to_string()),
            otel_sampler: "parentbased_traceidratio".to_string(),
            otel_sampler_arg: 0.1,
        };

        config.save(&paths).unwrap();

        let loaded = Config::load_from_file(&paths.config_file()).unwrap();
        assert_eq!(loaded.log_level, "trace");
        assert_eq!(loaded.environment, "prod");
        assert_eq!(
            loaded.otel_endpoint.as_deref(),
            Some("https://otel.example/v1/traces")
        );
        assert_eq!(loaded.otel_headers.as_deref(), Some("authorization=token"));
    }

    #[test]
    fn test_load_from_env_clamps_sampler_ratio() {
        std::env::set_var("UNBOUND_OTEL_TRACES_SAMPLER_ARG", "5.0");
        let config = Config::new().unwrap();
        std::env::remove_var("UNBOUND_OTEL_TRACES_SAMPLER_ARG");

        assert_eq!(config.otel_sampler_arg, 1.0);
    }
}
