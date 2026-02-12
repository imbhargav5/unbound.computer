//! Dependency checking operations.
//!
//! Pure async functions that detect whether system dependencies are installed
//! by spawning a login shell and running `which <name>`.

use crate::error::TienError;
use crate::types::{DependencyCheckResult, DependencyInfo};
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
}
