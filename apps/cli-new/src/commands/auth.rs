//! Authentication commands.

use super::{is_daemon_running, require_daemon};
use crate::output::{self, OutputFormat};
use anyhow::Result;
use daemon_ipc::Method;
use serde_json::Value;
use std::process::Command;

/// Authenticate GitHub CLI.
pub async fn login(format: &OutputFormat) -> Result<()> {
    if let Some(result) = fetch_gh_auth_status().await? {
        if gh_authenticated(&result) {
            let identity =
                active_host_identity(&result).unwrap_or_else(|| "GitHub CLI".to_string());
            output::print_success(&format!("Already authenticated as {}", identity), format);
            return Ok(());
        }
    }

    match Command::new("gh").args(["auth", "login"]).status() {
        Ok(status) if status.success() => {
            output::print_success("GitHub CLI authentication completed", format);
        }
        Ok(status) => {
            output::print_error(
                &format!("gh auth login exited with status {}", status),
                format,
            );
        }
        Err(error) => {
            output::print_error(
                &format!("Failed to launch gh auth login: {}", error),
                format,
            );
        }
    }

    Ok(())
}

/// Logout from GitHub CLI.
pub async fn logout(format: &OutputFormat) -> Result<()> {
    match Command::new("gh").args(["auth", "logout"]).status() {
        Ok(status) if status.success() => {
            output::print_success("GitHub CLI logout completed", format);
        }
        Ok(status) => {
            output::print_error(
                &format!("gh auth logout exited with status {}", status),
                format,
            );
        }
        Err(error) => {
            output::print_error(
                &format!("Failed to launch gh auth logout: {}", error),
                format,
            );
        }
    }

    Ok(())
}

/// Check GitHub authentication status.
pub async fn status(format: &OutputFormat) -> Result<()> {
    if !is_daemon_running().await {
        match format {
            OutputFormat::Text => {
                println!("Daemon:   not running");
                println!("GitHub:   unknown");
            }
            OutputFormat::Json => {
                println!(r#"{{"daemon_running":false,"authenticated":null}}"#);
            }
        }
        return Ok(());
    }

    let result = match fetch_gh_auth_status().await? {
        Some(result) => result,
        None => {
            output::print_error("No auth status returned from daemon", format);
            return Ok(());
        }
    };

    let authenticated = gh_authenticated(&result);

    match format {
        OutputFormat::Text => {
            println!("Daemon:   running");
            println!(
                "GitHub:   {}",
                if authenticated {
                    "authenticated"
                } else {
                    "not authenticated"
                }
            );
            if let Some(identity) = active_host_identity(&result) {
                println!("Account:  {}", identity);
            }
            if let Some(host_count) = result
                .get("authenticated_host_count")
                .and_then(|value| value.as_u64())
            {
                println!("Hosts:    {}", host_count);
            }
        }
        OutputFormat::Json => {
            let json = serde_json::json!({
                "daemon_running": true,
                "authenticated": authenticated,
                "auth_status": result,
            });
            println!("{}", serde_json::to_string_pretty(&json)?);
        }
    }

    Ok(())
}

async fn fetch_gh_auth_status() -> Result<Option<Value>> {
    let client = require_daemon().await?;
    let response = client.call_method(Method::GhAuthStatus).await?;
    if let Some(error) = &response.error {
        anyhow::bail!(error.message.clone());
    }
    Ok(response.result)
}

fn gh_authenticated(result: &Value) -> bool {
    result
        .get("authenticated_host_count")
        .and_then(|value| value.as_u64())
        .unwrap_or(0)
        > 0
}

fn active_host_identity(result: &Value) -> Option<String> {
    let hosts = result.get("hosts")?.as_array()?;
    let active = hosts.iter().find(|host| {
        host.get("active")
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
            && host
                .get("state")
                .and_then(|value| value.as_str())
                .map(|state| state == "logged_in")
                .unwrap_or(false)
    })?;
    let login = active.get("login").and_then(|value| value.as_str());
    let host = active.get("host").and_then(|value| value.as_str());
    match (login, host) {
        (Some(login), Some(host)) => Some(format!("{} @ {}", login, host)),
        (Some(login), None) => Some(login.to_string()),
        (None, Some(host)) => Some(host.to_string()),
        (None, None) => None,
    }
}
