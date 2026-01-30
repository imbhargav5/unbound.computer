//! Repository management commands.

use super::require_daemon;
use crate::output::{self, OutputFormat};
use anyhow::Result;
use daemon_ipc::Method;

/// List repositories.
pub async fn repos_list(format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;
    let response = client.call_method(Method::RepositoryList).await?;

    if let Some(result) = &response.result {
        let repos = result.get("repositories").and_then(|v| v.as_array());

        match format {
            OutputFormat::Text => {
                if let Some(repos) = repos {
                    if repos.is_empty() {
                        println!("No repositories found");
                    } else {
                        println!("{:<36} {:<30} {}", "ID", "Name", "Path");
                        println!("{}", "-".repeat(100));
                        for repo in repos {
                            let id = repo.get("id").and_then(|v| v.as_str()).unwrap_or("-");
                            let name = repo.get("name").and_then(|v| v.as_str()).unwrap_or("-");
                            let path = repo.get("path").and_then(|v| v.as_str()).unwrap_or("-");
                            println!("{:<36} {:<30} {}", id, name, path);
                        }
                    }
                } else {
                    println!("No repositories found");
                }
            }
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(result)?);
            }
        }
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// Add a repository.
pub async fn repos_add(path: &str, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    // Resolve to absolute path
    let abs_path = std::fs::canonicalize(path)
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| path.to_string());

    // Extract name from path
    let name = std::path::Path::new(&abs_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unnamed")
        .to_string();

    // Check if it's a git repository
    let is_git = std::path::Path::new(&abs_path).join(".git").exists();

    let params = serde_json::json!({
        "path": abs_path,
        "name": name,
        "is_git_repository": is_git,
    });

    let response = client.call_method_with_params(Method::RepositoryAdd, params).await?;

    if let Some(result) = &response.result {
        match format {
            OutputFormat::Text => {
                if let Some(repo_id) = result.get("id").and_then(|v| v.as_str()) {
                    output::print_success(&format!("Repository added: {}", repo_id), format);
                } else {
                    output::print_success("Repository added", format);
                }
            }
            OutputFormat::Json => {
                println!("{}", serde_json::to_string_pretty(result)?);
            }
        }
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// Remove a repository.
pub async fn repos_remove(id: &str, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let params = serde_json::json!({ "id": id });
    let response = client.call_method_with_params(Method::RepositoryRemove, params).await?;

    if response.is_success() {
        output::print_success(&format!("Repository {} removed", id), format);
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}
