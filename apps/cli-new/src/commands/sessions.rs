//! Session management commands.

use super::require_daemon;
use crate::output::{self, OutputFormat};
use anyhow::Result;
use daemon_ipc::Method;

/// List sessions.
pub async fn sessions_list(repository: Option<&str>, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let params = match repository {
        Some(repo_id) => Some(serde_json::json!({ "repository_id": repo_id })),
        None => {
            output::print_error("repository ID is required (use --repository)", format);
            return Ok(());
        }
    };

    let response = if let Some(params) = params {
        client
            .call_method_with_params(Method::SessionList, params)
            .await?
    } else {
        client.call_method(Method::SessionList).await?
    };

    if let Some(result) = &response.result {
        let sessions = result.get("sessions").and_then(|v| v.as_array());

        match format {
            OutputFormat::Text => {
                if let Some(sessions) = sessions {
                    if sessions.is_empty() {
                        println!("No sessions found");
                    } else {
                        println!(
                            "{:<36} {:<30} {:<10} {}",
                            "ID", "Title", "Status", "Last Accessed"
                        );
                        println!("{}", "-".repeat(100));
                        for session in sessions {
                            let id = session.get("id").and_then(|v| v.as_str()).unwrap_or("-");
                            let title =
                                session.get("title").and_then(|v| v.as_str()).unwrap_or("-");
                            let status = session
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or("-");
                            let accessed = session
                                .get("last_accessed_at")
                                .and_then(|v| v.as_str())
                                .unwrap_or("-");
                            println!("{:<36} {:<30} {:<10} {}", id, title, status, accessed);
                        }
                    }
                } else {
                    println!("No sessions found");
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

/// Show session details.
pub async fn sessions_show(id: &str, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let params = serde_json::json!({ "id": id });
    let response = client
        .call_method_with_params(Method::SessionGet, params)
        .await?;

    if let Some(result) = &response.result {
        match format {
            OutputFormat::Text => {
                if let Some(session) = result.get("session") {
                    println!("Session Details");
                    println!("{}", "-".repeat(50));
                    output::print_row(
                        "ID",
                        session.get("id").and_then(|v| v.as_str()).unwrap_or("-"),
                    );
                    output::print_row(
                        "Title",
                        session.get("title").and_then(|v| v.as_str()).unwrap_or("-"),
                    );
                    output::print_row(
                        "Repository",
                        session
                            .get("repository_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("-"),
                    );
                    output::print_row(
                        "Status",
                        session
                            .get("status")
                            .and_then(|v| v.as_str())
                            .unwrap_or("-"),
                    );
                    output::print_row(
                        "Created",
                        session
                            .get("created_at")
                            .and_then(|v| v.as_str())
                            .unwrap_or("-"),
                    );
                    output::print_row(
                        "Accessed",
                        session
                            .get("last_accessed_at")
                            .and_then(|v| v.as_str())
                            .unwrap_or("-"),
                    );
                } else {
                    println!("Session not found");
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

/// Create a new session.
pub async fn sessions_create(
    repository: &str,
    title: Option<&str>,
    format: &OutputFormat,
) -> Result<()> {
    let client = require_daemon().await?;

    let params = serde_json::json!({
        "repository_id": repository,
        "title": title.unwrap_or("New session"),
    });

    let response = client
        .call_method_with_params(Method::SessionCreate, params)
        .await?;

    if let Some(result) = &response.result {
        match format {
            OutputFormat::Text => {
                if let Some(session_id) = result.get("id").and_then(|v| v.as_str()) {
                    output::print_success(&format!("Session created: {}", session_id), format);
                } else {
                    output::print_success("Session created", format);
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

/// Delete a session.
pub async fn sessions_delete(id: &str, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let params = serde_json::json!({ "id": id });
    let response = client
        .call_method_with_params(Method::SessionDelete, params)
        .await?;

    if response.is_success() {
        output::print_success(&format!("Session {} deleted", id), format);
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// List messages in a session.
pub async fn sessions_messages(id: &str, format: &OutputFormat) -> Result<()> {
    let client = require_daemon().await?;

    let params = serde_json::json!({ "session_id": id });
    let response = client
        .call_method_with_params(Method::MessageList, params)
        .await?;

    if let Some(result) = &response.result {
        let messages = result.get("messages").and_then(|v| v.as_array());

        match format {
            OutputFormat::Text => {
                if let Some(messages) = messages {
                    if messages.is_empty() {
                        println!("No messages found");
                    } else {
                        println!("Messages for session {}:", id);
                        println!("{}", "-".repeat(80));
                        for msg in messages {
                            let role = msg
                                .get("role")
                                .and_then(|v| v.as_str())
                                .unwrap_or("unknown");
                            let content = msg.get("content").and_then(|v| v.as_str());
                            let seq = msg
                                .get("sequence_number")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(0);

                            println!(
                                "[{}] {} (seq: {})",
                                role.to_uppercase(),
                                content.unwrap_or("[encrypted/no key]"),
                                seq
                            );
                        }
                    }
                } else {
                    println!("No messages found");
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
