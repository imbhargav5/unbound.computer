//! Daemon management commands.

use super::{get_ipc_client, is_daemon_running};
use crate::output::{self, OutputFormat};
use anyhow::Result;
use daemon_core::Paths;
use daemon_ipc::Method;
use std::process::Command;

/// Start the daemon.
pub async fn daemon_start(foreground: bool) -> Result<()> {
    if is_daemon_running().await {
        println!("Daemon is already running");
        return Ok(());
    }

    println!("Starting daemon...");

    // Find the daemon binary
    // In development, it might be in target/debug or target/release
    // In production, it should be in PATH
    let daemon_bin = find_daemon_binary()?;

    if foreground {
        // Run in foreground (blocking)
        let status = Command::new(&daemon_bin)
            .arg("--foreground")
            .status()?;

        if !status.success() {
            anyhow::bail!("Daemon exited with status: {:?}", status.code());
        }
    } else {
        // Run in background
        let child = Command::new(&daemon_bin)
            .spawn()?;

        println!("Daemon started (PID: {})", child.id());

        // Wait a moment for the daemon to start
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

        if is_daemon_running().await {
            println!("Daemon is now running");
        } else {
            println!("Warning: Daemon may not have started successfully");
        }
    }

    Ok(())
}

/// Stop the daemon.
pub async fn daemon_stop(format: &OutputFormat) -> Result<()> {
    if !is_daemon_running().await {
        output::print_error("Daemon is not running", format);
        return Ok(());
    }

    let client = get_ipc_client()?;
    let response = client.call_method(Method::Shutdown).await?;

    if response.is_success() {
        output::print_success("Daemon shutdown initiated", format);

        // Wait for daemon to stop
        for _ in 0..10 {
            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
            if !is_daemon_running().await {
                output::print_success("Daemon stopped", format);
                return Ok(());
            }
        }

        println!("Warning: Daemon may still be running");
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// Check daemon status.
pub async fn daemon_status(format: &OutputFormat) -> Result<()> {
    let paths = Paths::new()?;
    let socket_path = paths.socket_file();
    let pid_path = paths.pid_file();

    if !is_daemon_running().await {
        match format {
            OutputFormat::Text => {
                println!("Status:   not running");
            }
            OutputFormat::Json => {
                println!(r#"{{"running":false}}"#);
            }
        }
        return Ok(());
    }

    let client = get_ipc_client()?;
    let response = client.call_method(Method::Health).await?;

    if let Some(result) = &response.result {
        let version = result.get("version").and_then(|v| v.as_str()).unwrap_or("unknown");
        let status = result.get("status").and_then(|v| v.as_str()).unwrap_or("unknown");
        let pid = std::fs::read_to_string(&pid_path).ok();

        match format {
            OutputFormat::Text => {
                println!("Status:   running");
                println!("Version:  {}", version);
                if let Some(pid) = &pid {
                    println!("PID:      {}", pid.trim());
                }
                println!("Socket:   {}", socket_path.display());
            }
            OutputFormat::Json => {
                let json = serde_json::json!({
                    "running": true,
                    "version": version,
                    "status": status,
                    "pid": pid.map(|p| p.trim().to_string()),
                    "socket": socket_path.to_string_lossy(),
                });
                println!("{}", serde_json::to_string_pretty(&json)?);
            }
        }
    } else if let Some(error) = &response.error {
        output::print_error(&error.message, format);
    }

    Ok(())
}

/// View daemon logs.
pub async fn daemon_logs(lines: usize, follow: bool) -> Result<()> {
    let paths = Paths::new()?;
    let log_file = paths.daemon_log_file();

    if !log_file.exists() {
        println!("No log file found at: {}", log_file.display());
        return Ok(());
    }

    if follow {
        // Use tail -f
        let status = Command::new("tail")
            .arg("-f")
            .arg("-n")
            .arg(lines.to_string())
            .arg(&log_file)
            .status()?;

        if !status.success() {
            anyhow::bail!("tail command failed");
        }
    } else {
        // Use tail
        let output = Command::new("tail")
            .arg("-n")
            .arg(lines.to_string())
            .arg(&log_file)
            .output()?;

        if output.status.success() {
            print!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            anyhow::bail!("tail command failed");
        }
    }

    Ok(())
}

/// Find the daemon binary.
fn find_daemon_binary() -> Result<String> {
    // Try common locations
    let candidates = [
        "unbound-daemon",
        "./target/debug/unbound-daemon",
        "./target/release/unbound-daemon",
        "../daemon/target/debug/unbound-daemon",
        "../daemon/target/release/unbound-daemon",
    ];

    for candidate in &candidates {
        if std::path::Path::new(candidate).exists() {
            return Ok(candidate.to_string());
        }
    }

    // Try to find in PATH
    if let Ok(output) = Command::new("which").arg("unbound-daemon").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Ok(path);
            }
        }
    }

    anyhow::bail!("Could not find unbound-daemon binary. Make sure it's installed or built.")
}
