//! Authentication commands.

use super::{is_daemon_running, require_daemon};
use crate::output::{self, OutputFormat};
use anyhow::Result;
use daemon_ipc::Method;
use std::io::{self, Write};

/// Login with email and password.
pub async fn login(format: &OutputFormat) -> Result<()> {
    // Check if daemon is running
    if !is_daemon_running().await {
        output::print_error(
            "Daemon is not running. Start it with 'unbound daemon start'",
            format,
        );
        return Ok(());
    }

    // Check current auth status
    let client = require_daemon().await?;
    let response = client.call_method(Method::AuthStatus).await?;

    if let Some(result) = &response.result {
        if result
            .get("logged_in")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            let email = result
                .get("email")
                .and_then(|v| v.as_str())
                .or_else(|| result.get("user_id").and_then(|v| v.as_str()))
                .unwrap_or("unknown");
            output::print_success(&format!("Already logged in as {}", email), format);
            return Ok(());
        }
    }

    // Prompt for email
    print!("Email: ");
    io::stdout().flush()?;
    let mut email = String::new();
    io::stdin().read_line(&mut email)?;
    let email = email.trim().to_string();

    if email.is_empty() {
        output::print_error("Email is required", format);
        return Ok(());
    }

    // Prompt for password (hidden)
    let password = rpassword::prompt_password("Password: ")?;

    if password.is_empty() {
        output::print_error("Password is required", format);
        return Ok(());
    }

    println!("Logging in...");

    let params = serde_json::json!({
        "email": email,
        "password": password,
    });

    match client
        .call_method_with_params(Method::AuthLogin, params)
        .await
    {
        Ok(response) => {
            if response.is_success() {
                if let Some(result) = &response.result {
                    let email_display = result
                        .get("email")
                        .and_then(|v| v.as_str())
                        .or_else(|| result.get("user_id").and_then(|v| v.as_str()))
                        .unwrap_or("user");
                    output::print_success(&format!("Logged in as {}", email_display), format);
                } else {
                    output::print_success("Logged in successfully", format);
                }
            } else if let Some(error) = &response.error {
                output::print_error(&format!("Login failed: {}", error.message), format);
            }
        }
        Err(e) => {
            output::print_error(&format!("Login failed: {}", e), format);
        }
    }

    Ok(())
}

/// Logout and clear session.
pub async fn logout(format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let response = client.call_method(Method::AuthLogout).await?;

    if response.is_success() {
        output::print_success("Logged out successfully", format);
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// Check authentication status.
pub async fn status(format: &OutputFormat) -> Result<()> {
    // First check if daemon is running
    if !is_daemon_running().await {
        match format {
            OutputFormat::Text => {
                println!("Daemon:   not running");
                println!("Auth:     unknown");
            }
            OutputFormat::Json => {
                println!(r#"{{"daemon_running":false,"logged_in":null}}"#);
            }
        }
        return Ok(());
    }

    let client = require_daemon().await?;
    let response = client.call_method(Method::AuthStatus).await?;

    if let Some(result) = &response.result {
        let logged_in = result
            .get("logged_in")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        match format {
            OutputFormat::Text => {
                println!("Daemon:   running");
                if logged_in {
                    let user_id = result
                        .get("user_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    let expires_at = result
                        .get("expires_at")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    println!("Auth:     logged in");
                    println!("User ID:  {}", user_id);
                    println!("Expires:  {}", expires_at);
                } else {
                    println!("Auth:     not logged in");
                }
            }
            OutputFormat::Json => {
                let json = serde_json::json!({
                    "daemon_running": true,
                    "logged_in": logged_in,
                    "user_id": result.get("user_id"),
                    "expires_at": result.get("expires_at"),
                });
                println!("{}", serde_json::to_string_pretty(&json)?);
            }
        }
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}
