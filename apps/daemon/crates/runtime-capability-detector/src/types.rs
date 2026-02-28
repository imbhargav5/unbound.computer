//! Data types for dependency checking.
//!
//! These types are designed for serialization over IPC and match the
//! corresponding Swift types in the macOS application.

use serde::{Deserialize, Serialize};

/// Information about a single system dependency.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DependencyInfo {
    /// The name of the dependency (e.g., "claude", "gh").
    pub name: String,
    /// Whether the dependency is installed and found in PATH.
    pub installed: bool,
    /// The resolved path if installed (e.g., "/usr/local/bin/claude").
    pub path: Option<String>,
}

/// Result of checking all required system dependencies.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DependencyCheckResult {
    /// Claude Code CLI status (required dependency).
    pub claude: DependencyInfo,
    /// GitHub CLI status (optional dependency).
    pub gh: DependencyInfo,
}

/// Canonical capabilities payload for syncing to Supabase.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capabilities {
    pub cli: CliCapabilities,
    pub metadata: CapabilitiesMetadata,
}

/// CLI tool capabilities.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CliCapabilities {
    pub claude: ToolCapabilities,
    pub gh: ToolCapabilities,
    pub codex: ToolCapabilities,
    pub ollama: ToolCapabilities,
}

/// Capability details for a single tool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCapabilities {
    pub installed: bool,
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub models: Option<Vec<String>>,
}

/// Metadata describing the capabilities payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilitiesMetadata {
    pub schema_version: u32,
    pub collected_at: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dependency_info_serde_installed() {
        let info = DependencyInfo {
            name: "claude".to_string(),
            installed: true,
            path: Some("/usr/local/bin/claude".to_string()),
        };

        let json = serde_json::to_string(&info).expect("serialize");
        let deserialized: DependencyInfo = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(deserialized.name, "claude");
        assert!(deserialized.installed);
        assert_eq!(deserialized.path, Some("/usr/local/bin/claude".to_string()));
    }

    #[test]
    fn dependency_info_serde_not_installed() {
        let info = DependencyInfo {
            name: "gh".to_string(),
            installed: false,
            path: None,
        };

        let json = serde_json::to_string(&info).expect("serialize");
        let deserialized: DependencyInfo = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(deserialized.name, "gh");
        assert!(!deserialized.installed);
        assert!(deserialized.path.is_none());
    }

    #[test]
    fn dependency_check_result_serde_roundtrip() {
        let result = DependencyCheckResult {
            claude: DependencyInfo {
                name: "claude".to_string(),
                installed: true,
                path: Some("/usr/local/bin/claude".to_string()),
            },
            gh: DependencyInfo {
                name: "gh".to_string(),
                installed: false,
                path: None,
            },
        };

        let json = serde_json::to_string(&result).expect("serialize");
        let deserialized: DependencyCheckResult = serde_json::from_str(&json).expect("deserialize");

        assert!(deserialized.claude.installed);
        assert!(!deserialized.gh.installed);
    }
}
