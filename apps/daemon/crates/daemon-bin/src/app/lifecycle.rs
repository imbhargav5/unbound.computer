//! Daemon lifecycle management (stop, status).

use daemon_config_and_utils::Paths;
use daemon_ipc::Method;
use std::path::Path;
use std::process::Command;

fn socket_is_connectable(socket_path: &Path) -> bool {
    std::os::unix::net::UnixStream::connect(socket_path).is_ok()
}

fn cleanup_runtime_files(socket_path: &Path, pid_path: &Path) {
    if socket_path.exists() {
        let _ = std::fs::remove_file(socket_path);
    }
    if pid_path.exists() {
        let _ = std::fs::remove_file(pid_path);
    }
}

fn pid_looks_like_daemon(pid: i32) -> bool {
    let output = match Command::new("ps")
        .arg("-p")
        .arg(pid.to_string())
        .arg("-o")
        .arg("command=")
        .output()
    {
        Ok(output) => output,
        Err(_) => return false,
    };

    if !output.status.success() {
        return false;
    }

    let command = String::from_utf8_lossy(&output.stdout);
    command.contains("unbound-daemon")
}

/// Stop the daemon.
pub async fn stop_daemon(paths: &Paths) -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = paths.socket_file();
    let pid_path = paths.pid_file();

    if !socket_path.exists() {
        println!("Daemon is not running (socket not found)");
        // Clean up stale PID file if it exists
        if pid_path.exists() {
            let _ = std::fs::remove_file(&pid_path);
        }
        return Ok(());
    }

    // Try graceful shutdown first
    let client = daemon_ipc::IpcClient::new(&socket_path.to_string_lossy());

    match client.call_method(Method::Shutdown).await {
        Ok(response) => {
            if response.is_success() {
                println!("Daemon shutdown initiated");
            } else {
                println!("Shutdown failed: {:?}", response.error);
            }
        }
        Err(e) => {
            println!("Failed to connect to daemon: {}", e);
            if !socket_is_connectable(&socket_path) {
                cleanup_runtime_files(&socket_path, &pid_path);
                println!("Cleaned up stale daemon socket/PID files");
                return Ok(());
            }
        }
    }

    // Wait for daemon to stop (up to 3 seconds)
    for _ in 0..30 {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        if !socket_path.exists() {
            println!("Daemon stopped");
            return Ok(());
        }
    }

    // If still running, try to force kill using PID
    if pid_path.exists() {
        if let Ok(pid_str) = std::fs::read_to_string(&pid_path) {
            if let Ok(pid) = pid_str.trim().parse::<i32>() {
                if pid_looks_like_daemon(pid) {
                    println!(
                        "Daemon did not stop gracefully, sending SIGKILL to PID {}",
                        pid
                    );
                    unsafe {
                        libc::kill(pid, libc::SIGKILL);
                    }
                    cleanup_runtime_files(&socket_path, &pid_path);
                    println!("Daemon killed");
                    return Ok(());
                }

                println!(
                    "PID {} does not look like unbound-daemon; skipping SIGKILL and cleaning stale files",
                    pid
                );
                cleanup_runtime_files(&socket_path, &pid_path);
                println!("Cleaned up stale daemon socket/PID files");
                return Ok(());
            }
        }
    }

    // Last resort: clean up socket file
    if socket_path.exists() || pid_path.exists() {
        cleanup_runtime_files(&socket_path, &pid_path);
        println!("Cleaned up stale daemon socket/PID files");
    }

    Ok(())
}

/// Check daemon status.
pub async fn check_status(paths: &Paths) -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = paths.socket_file();
    let pid_path = paths.pid_file();

    if !socket_path.exists() {
        println!("Daemon is not running (socket not found)");
        return Ok(());
    }

    let client = daemon_ipc::IpcClient::new(&socket_path.to_string_lossy());

    match client.call_method(Method::Health).await {
        Ok(response) => {
            if response.is_success() {
                if let Some(result) = response.result {
                    let version = result
                        .get("version")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    let status = result
                        .get("status")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");

                    // Try to read PID
                    let pid = std::fs::read_to_string(&pid_path).ok();

                    println!("Daemon is running");
                    println!("  Status:  {}", status);
                    println!("  Version: {}", version);
                    if let Some(pid) = pid {
                        println!("  PID:     {}", pid.trim());
                    }
                    println!("  Socket:  {}", socket_path.display());
                } else {
                    println!("Daemon is running (no details available)");
                }
            } else {
                println!("Daemon returned error: {:?}", response.error);
            }
        }
        Err(e) => {
            println!("Failed to connect to daemon: {}", e);
            println!("Daemon may not be running or socket may be stale");
        }
    }

    Ok(())
}
