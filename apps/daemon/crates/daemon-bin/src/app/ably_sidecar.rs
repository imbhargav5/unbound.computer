//! daemon-ably sidecar process management utilities.

use crate::app::falco_sidecar::terminate_child;
use daemon_config_and_utils::Paths;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tokio::net::UnixStream;
use tracing::{debug, info, warn};

const ENV_DAEMON_ABLY_BINARY: &str = "DAEMON_ABLY_BINARY";
const ENV_ABLY_BROKER_SOCKET: &str = "UNBOUND_ABLY_BROKER_SOCKET";
const ENV_ABLY_BROKER_TOKEN_FALCO: &str = "UNBOUND_ABLY_BROKER_TOKEN_FALCO";
const ENV_ABLY_BROKER_TOKEN_NAGATO: &str = "UNBOUND_ABLY_BROKER_TOKEN_NAGATO";
const ENV_ABLY_SOCKET: &str = "UNBOUND_ABLY_SOCKET";

/// Builds the list of daemon-ably binary candidates in lookup order.
pub fn daemon_ably_binary_candidates() -> Vec<PathBuf> {
    let current_exe = std::env::current_exe().ok();
    let env_override = std::env::var(ENV_DAEMON_ABLY_BINARY)
        .ok()
        .map(|raw| raw.trim().to_string())
        .filter(|raw| !raw.is_empty())
        .map(PathBuf::from);

    build_daemon_ably_binary_candidates(current_exe.as_deref(), env_override.as_deref())
}

/// Spawns daemon-ably using known candidate binary locations.
pub fn spawn_daemon_ably_process(
    paths: &Paths,
    user_id: &str,
    device_id: &str,
    falco_broker_token: &str,
    nagato_broker_token: &str,
    daemon_log_level: &str,
    source: &str,
) -> Result<Child, String> {
    let candidates = daemon_ably_binary_candidates();
    let mut attempted = Vec::new();
    let socket_path = paths.ably_socket_file();
    let broker_socket_path = paths.ably_auth_socket_file();

    if candidates.is_empty() {
        return Err("failed to resolve daemon-ably binary location".to_string());
    }

    debug!(
        source = source,
        socket = %socket_path.display(),
        candidate_count = candidates.len(),
        "Attempting to spawn daemon-ably sidecar"
    );

    for binary in candidates {
        attempted.push(binary.display().to_string());
        debug!(
            source = source,
            binary = %binary.display(),
            "Trying daemon-ably binary candidate"
        );

        let mut command = Command::new(&binary);
        command
            .arg("--device-id")
            .arg(device_id)
            .arg("--user-id")
            .arg(user_id)
            .env(ENV_ABLY_BROKER_SOCKET, &broker_socket_path)
            .env(ENV_ABLY_BROKER_TOKEN_FALCO, falco_broker_token)
            .env(ENV_ABLY_BROKER_TOKEN_NAGATO, nagato_broker_token)
            .env(ENV_ABLY_SOCKET, &socket_path)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());

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
                    "Spawned daemon-ably sidecar process"
                );
                return Ok(child);
            }
            Err(err) if err.kind() == ErrorKind::NotFound => continue,
            Err(err) => {
                warn!(
                    source = source,
                    binary = %binary.display(),
                    error = %err,
                    "daemon-ably candidate failed to spawn"
                );
                return Err(format!(
                    "failed to spawn daemon-ably binary {}: {}",
                    binary.display(),
                    err
                ));
            }
        }
    }

    Err(format!(
        "failed to locate daemon-ably binary (tried: {}). Build with `cd packages/daemon-ably && go build -o daemon-ably ./cmd/daemon-ably`",
        attempted.join(", ")
    ))
}

/// Waits for daemon-ably socket file to appear and verifies the process is still alive.
pub async fn wait_for_daemon_ably_socket(
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
        "Waiting for daemon-ably socket readiness"
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
                "daemon-ably socket became ready"
            );
            return Ok(());
        }

        match child.try_wait() {
            Ok(Some(status)) => {
                return Err(format!(
                    "daemon-ably exited before socket became ready (status: {})",
                    status
                ));
            }
            Ok(None) => {}
            Err(err) => return Err(format!("failed to check daemon-ably process state: {}", err)),
        }

        if Instant::now() >= deadline {
            return Err(format!(
                "timed out waiting for daemon-ably socket {}",
                socket_path.display()
            ));
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

/// Spawns daemon-ably and waits for its socket to become available.
pub async fn start_daemon_ably_sidecar(
    paths: &Paths,
    user_id: &str,
    device_id: &str,
    falco_broker_token: &str,
    nagato_broker_token: &str,
    daemon_log_level: &str,
    timeout: Duration,
    source: &str,
) -> Result<Child, String> {
    let mut child = spawn_daemon_ably_process(
        paths,
        user_id,
        device_id,
        falco_broker_token,
        nagato_broker_token,
        daemon_log_level,
        source,
    )?;
    let socket_path = paths.ably_socket_file();
    if let Err(err) = wait_for_daemon_ably_socket(&socket_path, &mut child, timeout, source).await {
        terminate_child(&mut child, "daemon-ably");
        return Err(err);
    }
    Ok(child)
}

/// Returns an error if daemon-ably socket exists but cannot be connected to.
pub async fn ensure_daemon_ably_socket_connectable(socket_path: &Path) -> Result<(), String> {
    UnixStream::connect(socket_path).await.map_err(|err| {
        format!(
            "failed to connect to daemon-ably socket {}: {}",
            socket_path.display(),
            err
        )
    })?;
    Ok(())
}

fn build_daemon_ably_binary_candidates(
    current_exe: Option<&Path>,
    env_override: Option<&Path>,
) -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    if let Some(override_path) = env_override {
        candidates.push(override_path.to_path_buf());
    }

    if let Some(current_exe) = current_exe {
        if let Some(parent) = current_exe.parent() {
            // Primary production path: helper binary shipped next to daemon.
            candidates.push(parent.join("daemon-ably"));

            // macOS app bundle conventions:
            // <App>.app/Contents/MacOS/unbound-daemon
            // -> <App>.app/Contents/Helpers/daemon-ably
            // -> <App>.app/Contents/Resources/daemon-ably
            if parent.file_name().and_then(|v| v.to_str()) == Some("MacOS") {
                if let Some(contents_dir) = parent.parent() {
                    candidates.push(contents_dir.join("Helpers").join("daemon-ably"));
                    candidates.push(contents_dir.join("Resources").join("daemon-ably"));
                }
            }

            // Best-effort local-dev fallback to monorepo package binary.
            if let Some(repo_root) = infer_repo_root(parent) {
                candidates.push(
                    repo_root
                        .join("packages")
                        .join("daemon-ably")
                        .join("daemon-ably"),
                );
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

fn infer_repo_root(exe_parent: &Path) -> Option<PathBuf> {
    exe_parent
        .ancestors()
        .find(|path| path.join("packages").join("daemon-ably").exists())
        .map(Path::to_path_buf)
}
