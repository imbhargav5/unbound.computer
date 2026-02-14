//! Dependency checking operations.
//!
//! Pure async functions that detect whether system dependencies are installed
//! by spawning a login shell and running `which <name>`.

use crate::error::TienError;
use crate::types::{
    Capabilities, CapabilitiesMetadata, CliCapabilities, DependencyCheckResult, DependencyInfo,
    ToolCapabilities,
};
use chrono::{SecondsFormat, Utc};
use tracing::debug;

/// Check whether a single dependency is installed.
///
/// Runs `/bin/zsh -l -c "which <name>"` to resolve the dependency path
/// through the user's login shell (picking up PATH from .zprofile/.zshrc).
pub async fn check_dependency(name: &str) -> Result<DependencyInfo, TienError> {
    debug!("Checking dependency: {}", name);

    let output = tokio::process::Command::new("/bin/zsh")
        .args(["-l", "-c", &format!("which {}", name)])
        .output()
        .await?;

    let installed = output.status.success();
    let path = if installed {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    };

    debug!(
        "Dependency '{}': installed={}, path={:?}",
        name, installed, path
    );

    Ok(DependencyInfo {
        name: name.to_string(),
        installed,
        path,
    })
}

/// Check all required system dependencies concurrently.
///
/// Returns the status of both `claude` (required) and `gh` (optional).
pub async fn check_all() -> Result<DependencyCheckResult, TienError> {
    let (claude, gh) = tokio::join!(check_dependency("claude"), check_dependency("gh"));

    Ok(DependencyCheckResult {
        claude: claude?,
        gh: gh?,
    })
}

/// Collect the canonical capabilities payload for syncing to Supabase.
pub async fn collect_capabilities() -> Result<Capabilities, TienError> {
    let (claude, gh, codex, ollama) = tokio::join!(
        check_dependency("claude"),
        check_dependency("gh"),
        check_dependency("codex"),
        check_dependency("ollama")
    );

    let claude = claude?;
    let gh = gh?;
    let codex = codex?;
    let ollama = ollama?;

    let claude_models = if claude.installed {
        read_claude_models().await
    } else {
        None
    };

    Ok(Capabilities {
        cli: CliCapabilities {
            claude: ToolCapabilities {
                installed: claude.installed,
                path: claude.path,
                models: claude_models,
            },
            gh: ToolCapabilities {
                installed: gh.installed,
                path: gh.path,
                models: None,
            },
            codex: ToolCapabilities {
                installed: codex.installed,
                path: codex.path,
                models: None,
            },
            ollama: ToolCapabilities {
                installed: ollama.installed,
                path: ollama.path,
                models: None,
            },
        },
        metadata: CapabilitiesMetadata {
            schema_version: 1,
            collected_at: Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true),
        },
    })
}

async fn read_claude_models() -> Option<Vec<String>> {
    if let Some(models) = try_claude_models_json().await {
        if !models.is_empty() {
            return Some(models);
        }
    }

    try_claude_models_text().await
}

async fn try_claude_models_json() -> Option<Vec<String>> {
    let output = run_login_shell("claude models --json").await.ok()?;
    if !output.status.success() {
        return None;
    }

    let value: serde_json::Value = serde_json::from_slice(&output.stdout).ok()?;
    let mut models = Vec::new();

    match value {
        serde_json::Value::Array(entries) => {
            for entry in entries {
                match entry {
                    serde_json::Value::String(model) => models.push(model),
                    serde_json::Value::Object(map) => {
                        if let Some(serde_json::Value::String(model)) =
                            map.get("id").or_else(|| map.get("name"))
                        {
                            models.push(model.clone());
                        }
                    }
                    _ => {}
                }
            }
        }
        serde_json::Value::Object(map) => {
            if let Some(serde_json::Value::Array(entries)) = map.get("models") {
                for entry in entries {
                    if let serde_json::Value::String(model) = entry {
                        models.push(model.clone());
                    }
                }
            }
        }
        _ => {}
    }

    normalize_models(models)
}

async fn try_claude_models_text() -> Option<Vec<String>> {
    let output = run_login_shell("claude models").await.ok()?;
    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut models = Vec::new();

    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let lower = trimmed.to_lowercase();
        if lower.starts_with("available")
            || lower.starts_with("models")
            || lower.starts_with("model")
            || trimmed.starts_with('-')
        {
            continue;
        }

        if let Some(token) = trimmed.split_whitespace().next() {
            if !token.is_empty() {
                models.push(token.to_string());
            }
        }
    }

    normalize_models(models)
}

async fn run_login_shell(command: &str) -> Result<std::process::Output, TienError> {
    Ok(tokio::process::Command::new("/bin/zsh")
        .args(["-l", "-c", command])
        .output()
        .await?)
}

fn normalize_models(models: Vec<String>) -> Option<Vec<String>> {
    let mut seen = std::collections::HashSet::new();
    let mut unique = Vec::new();
    for model in models {
        if seen.insert(model.clone()) {
            unique.push(model);
        }
    }

    if unique.is_empty() {
        None
    } else {
        Some(unique)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn check_dependency_finds_zsh() {
        // zsh should always be available on macOS
        let result = check_dependency("zsh").await.expect("check should succeed");
        assert_eq!(result.name, "zsh");
        assert!(result.installed);
        assert!(result.path.is_some());
    }

    #[tokio::test]
    async fn check_dependency_missing_binary() {
        let result = check_dependency("this_binary_does_not_exist_9999")
            .await
            .expect("check should succeed even for missing binary");
        assert_eq!(result.name, "this_binary_does_not_exist_9999");
        assert!(!result.installed);
        assert!(result.path.is_none());
    }

    #[tokio::test]
    async fn check_all_returns_both() {
        let result = check_all().await.expect("check_all should succeed");
        assert_eq!(result.claude.name, "claude");
        assert_eq!(result.gh.name, "gh");
    }

    #[test]
    fn normalize_models_dedupes() {
        let models = normalize_models(vec![
            "claude-opus".to_string(),
            "claude-opus".to_string(),
            "claude-sonnet".to_string(),
        ])
        .expect("models");

        assert_eq!(models.len(), 2);
    }
}
