//! Falco sidecar process management utilities.

use daemon_config_and_utils::Paths;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tokio::net::UnixStream;
use tracing::{debug, info, warn};

const ENV_ABLY_SOCKET: &str = "UNBOUND_ABLY_SOCKET";

/// Builds the list of Falco binary candidates in lookup order.
pub fn falco_binary_candidates() -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    // Environment variable override (highest priority).
    if let Ok(override_path) = std::env::var("FALCO_BINARY") {
        candidates.push(PathBuf::from(override_path));
    }

    if let Ok(current_exe) = std::env::current_exe() {
        if let Some(parent) = current_exe.parent() {
            // Prefer monorepo package binary in local dev to avoid stale leftovers
            // in apps/daemon/target/debug.
            if let Some(repo_root) = infer_repo_root(parent) {
                candidates.push(
                    repo_root
                        .join("packages")
                        .join("daemon-falco")
                        .join("falco"),
                );
            }

            // Primary production path: helper binary shipped next to daemon.
            candidates.push(parent.join("falco"));

            // macOS app bundle conventions:
            // <App>.app/Contents/MacOS/unbound-daemon
            // -> <App>.app/Contents/Helpers/falco
            // -> <App>.app/Contents/Resources/falco
            if parent.file_name().and_then(|v| v.to_str()) == Some("MacOS") {
                if let Some(contents_dir) = parent.parent() {
                    candidates.push(contents_dir.join("Helpers").join("falco"));
                    candidates.push(contents_dir.join("Resources").join("falco"));
                }
            }
        }
    }

    // Preserve order while removing duplicates.
    let mut unique = Vec::with_capacity(candidates.len());
    for candidate in candidates {
        if !unique.iter().any(|existing| existing == &candidate) {
            unique.push(candidate);
        }
    }

    unique
}

/// Walk up ancestor directories to find the repo root.
fn infer_repo_root(exe_parent: &Path) -> Option<PathBuf> {
    exe_parent
        .ancestors()
        .find(|path| path.join("packages").join("daemon-falco").exists())
        .map(Path::to_path_buf)
}

/// Spawns Falco using known candidate binary locations.
pub fn spawn_falco_process(
    paths: &Paths,
    device_id: &str,
    daemon_log_level: &str,
    source: &str,
) -> Result<Child, String> {
    let candidates = falco_binary_candidates();
    let mut attempted = Vec::new();
    let socket_path = paths.falco_socket_file();
    let ably_socket_path = paths.ably_socket_file();

    if candidates.is_empty() {
        return Err(
            "failed to resolve falco binary location from current daemon executable path"
                .to_string(),
        );
    }

    debug!(
        source = source,
        socket = %socket_path.display(),
        candidate_count = candidates.len(),
        "Attempting to spawn Falco sidecar"
    );

    for binary in candidates {
        attempted.push(binary.display().to_string());
        debug!(
            source = source,
            binary = %binary.display(),
            "Trying Falco binary candidate"
        );

        let mut command = Command::new(&binary);
        command
            .arg("--device-id")
            .arg(device_id)
            .env(ENV_ABLY_SOCKET, &ably_socket_path)
            .env("FALCO_SOCKET", &socket_path)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        if daemon_log_level.eq_ignore_ascii_case("debug")
            || daemon_log_level.eq_ignore_ascii_case("trace")
        {
            command.arg("--debug");
        }

        match command.spawn() {
            Ok(child) => {
                info!(
                    source = source,
                    pid = child.id(),
                    binary = %binary.display(),
                    socket = %socket_path.display(),
                    "Spawned Falco sidecar process"
                );
                return Ok(child);
            }
            Err(err) if err.kind() == ErrorKind::NotFound => continue,
            Err(err) => {
                warn!(
                    source = source,
                    binary = %binary.display(),
                    error = %err,
                    "Falco candidate failed to spawn"
                );
                return Err(format!(
                    "failed to spawn falco binary {}: {}",
                    binary.display(),
                    err
                ));
            }
        }
    }

    Err(format!(
        "failed to locate falco binary (tried: {})",
        attempted.join(", ")
    ))
}

/// Waits for Falco socket file to appear and verifies the process is still alive.
pub async fn wait_for_falco_socket(
    socket_path: &Path,
    child: &mut Child,
    timeout: Duration,
    source: &str,
) -> Result<(), String> {
    debug!(
        source = source,
        pid = child.id(),
        socket = %socket_path.display(),
        timeout_ms = timeout.as_millis(),
        "Waiting for Falco socket readiness"
    );
    let deadline = Instant::now() + timeout;
    let started_at = Instant::now();
    loop {
        if socket_path.exists() {
            info!(
                source = source,
                pid = child.id(),
                socket = %socket_path.display(),
                waited_ms = started_at.elapsed().as_millis(),
                "Falco socket became ready"
            );
            return Ok(());
        }

        match child.try_wait() {
            Ok(Some(status)) => {
                let stderr = read_startup_stderr(child);
                if stderr.is_empty() {
                    return Err(format!(
                        "falco exited before socket became ready (status: {})",
                        status
                    ));
                }
                return Err(format!(
                    "falco exited before socket became ready (status: {}): {}",
                    status, stderr
                ));
            }
            Ok(None) => {}
            Err(err) => return Err(format!("failed to check falco process state: {}", err)),
        }

        if Instant::now() >= deadline {
            return Err(format!(
                "timed out waiting for falco socket {}",
                socket_path.display()
            ));
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

/// Spawns Falco and waits for its socket to become available.
pub async fn start_falco_sidecar(
    paths: &Paths,
    device_id: &str,
    daemon_log_level: &str,
    timeout: Duration,
    source: &str,
) -> Result<Child, String> {
    let mut child = spawn_falco_process(paths, device_id, daemon_log_level, source)?;
    let socket_path = paths.falco_socket_file();
    if let Err(err) = wait_for_falco_socket(&socket_path, &mut child, timeout, source).await {
        terminate_child(&mut child, "falco");
        return Err(err);
    }
    Ok(child)
}

/// Returns an error if Falco socket exists but cannot be connected to.
pub async fn ensure_socket_connectable(socket_path: &Path) -> Result<(), String> {
    UnixStream::connect(socket_path).await.map_err(|err| {
        format!(
            "failed to connect to falco socket {}: {}",
            socket_path.display(),
            err
        )
    })?;
    Ok(())
}

/// Best-effort sidecar process termination.
pub fn terminate_child(child: &mut Child, process_name: &str) {
    match child.try_wait() {
        Ok(Some(status)) => {
            debug!(
                process = process_name,
                status = %status,
                "Sidecar process already exited"
            );
        }
        Ok(None) => {
            if let Err(err) = child.kill() {
                warn!(
                    process = process_name,
                    error = %err,
                    "Failed to terminate sidecar process"
                );
            }
            if let Err(err) = child.wait() {
                warn!(
                    process = process_name,
                    error = %err,
                    "Failed to reap sidecar process"
                );
            }
        }
        Err(err) => {
            warn!(
                process = process_name,
                error = %err,
                "Failed to inspect sidecar process state"
            );
        }
    }
}

fn read_startup_stderr(child: &mut Child) -> String {
    let Some(mut stderr) = child.stderr.take() else {
        return String::new();
    };

    let mut output = String::new();
    if stderr.read_to_string(&mut output).is_err() {
        return String::new();
    }
    output.trim().to_string()
}
