//! Nagato sidecar process management utilities.

use crate::app::falco_sidecar::terminate_child;
use daemon_config_and_utils::Paths;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};
use tokio::time::sleep;
use tracing::{debug, info, warn};

const ENV_NAGATO_BINARY: &str = "NAGATO_BINARY";
const ENV_ABLY_SOCKET: &str = "UNBOUND_ABLY_SOCKET";

/// Builds the list of Nagato binary candidates in lookup order.
pub fn nagato_binary_candidates() -> Vec<PathBuf> {
    let current_exe = std::env::current_exe().ok();
    let env_override = std::env::var(ENV_NAGATO_BINARY)
        .ok()
        .map(|raw| raw.trim().to_string())
        .filter(|raw| !raw.is_empty())
        .map(PathBuf::from);

    build_nagato_binary_candidates(current_exe.as_deref(), env_override.as_deref())
}

/// Spawns Nagato using known candidate binary locations.
pub fn spawn_nagato_process(
    paths: &Paths,
    device_id: &str,
    daemon_log_level: &str,
    source: &str,
) -> Result<Child, String> {
    let candidates = nagato_binary_candidates();
    let mut attempted = Vec::new();
    let socket_path = paths.nagato_socket_file();
    let ably_socket_path = paths.ably_socket_file();

    if candidates.is_empty() {
        return Err("failed to resolve nagato binary location".to_string());
    }

    debug!(
        source = source,
        socket = %socket_path.display(),
        candidate_count = candidates.len(),
        "Attempting to spawn Nagato sidecar"
    );

    for binary in candidates {
        attempted.push(binary.display().to_string());
        debug!(
            source = source,
            binary = %binary.display(),
            "Trying Nagato binary candidate"
        );

        let mut command = Command::new(&binary);
        command
            .arg("--device-id")
            .arg(device_id)
            .env(ENV_ABLY_SOCKET, &ably_socket_path)
            .env("NAGATO_SOCKET", &socket_path)
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
                    "Spawned Nagato sidecar process"
                );
                return Ok(child);
            }
            Err(err) if err.kind() == ErrorKind::NotFound => continue,
            Err(err) => {
                warn!(
                    source = source,
                    binary = %binary.display(),
                    error = %err,
                    "Nagato candidate failed to spawn"
                );
                return Err(format!(
                    "failed to spawn nagato binary {}: {}",
                    binary.display(),
                    err
                ));
            }
        }
    }

    Err(format!(
        "failed to locate nagato binary (tried: {}). Build with `cd packages/daemon-nagato && go build -o nagato ./cmd/nagato`",
        attempted.join(", ")
    ))
}

/// Waits for Nagato process to stay alive for a short readiness window.
pub async fn wait_for_nagato_ready(
    child: &mut Child,
    timeout: Duration,
    source: &str,
) -> Result<(), String> {
    debug!(
        source = source,
        pid = child.id(),
        timeout_ms = timeout.as_millis(),
        "Waiting for Nagato sidecar readiness"
    );
    let deadline = Instant::now() + timeout;
    let started_at = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let stderr = read_startup_stderr(child);
                if stderr.is_empty() {
                    return Err(format!(
                        "nagato exited before readiness check completed (status: {})",
                        status
                    ));
                }
                return Err(format!(
                    "nagato exited before readiness check completed (status: {}): {}",
                    status, stderr
                ));
            }
            Ok(None) => {}
            Err(err) => {
                return Err(format!("failed to check nagato process state: {}", err));
            }
        }

        if Instant::now() >= deadline {
            info!(
                source = source,
                pid = child.id(),
                waited_ms = started_at.elapsed().as_millis(),
                "Nagato sidecar passed readiness window"
            );
            return Ok(());
        }

        sleep(Duration::from_millis(100)).await;
    }
}

/// Spawns Nagato and waits for readiness.
pub async fn start_nagato_sidecar(
    paths: &Paths,
    device_id: &str,
    daemon_log_level: &str,
    timeout: Duration,
    source: &str,
) -> Result<Child, String> {
    let mut child = spawn_nagato_process(paths, device_id, daemon_log_level, source)?;
    if let Err(err) = wait_for_nagato_ready(&mut child, timeout, source).await {
        terminate_child(&mut child, "nagato");
        return Err(err);
    }
    Ok(child)
}

fn build_nagato_binary_candidates(
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
            candidates.push(parent.join("nagato"));

            // macOS app bundle conventions:
            // <App>.app/Contents/MacOS/unbound-daemon
            // -> <App>.app/Contents/Helpers/nagato
            // -> <App>.app/Contents/Resources/nagato
            if parent.file_name().and_then(|v| v.to_str()) == Some("MacOS") {
                if let Some(contents_dir) = parent.parent() {
                    candidates.push(contents_dir.join("Helpers").join("nagato"));
                    candidates.push(contents_dir.join("Resources").join("nagato"));
                }
            }

            // Best-effort local-dev fallback to monorepo package binary.
            if let Some(repo_root) = infer_repo_root(parent) {
                candidates.push(
                    repo_root
                        .join("packages")
                        .join("daemon-nagato")
                        .join("nagato"),
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
        .find(|path| path.join("packages").join("daemon-nagato").exists())
        .map(Path::to_path_buf)
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

#[cfg(test)]
mod tests {
    use super::build_nagato_binary_candidates;
    use std::path::{Path, PathBuf};

    #[test]
    fn env_override_has_priority() {
        let candidates = build_nagato_binary_candidates(
            Some(Path::new("/tmp/app/Contents/MacOS/unbound-daemon")),
            Some(Path::new("/custom/nagato")),
        );

        assert_eq!(candidates[0], PathBuf::from("/custom/nagato"));
        assert_eq!(
            candidates[1],
            PathBuf::from("/tmp/app/Contents/MacOS/nagato")
        );
    }

    #[test]
    fn dedupes_candidates_while_preserving_order() {
        let candidates = build_nagato_binary_candidates(
            Some(Path::new("/tmp/debug/unbound-daemon")),
            Some(Path::new("/tmp/debug/nagato")),
        );

        assert_eq!(candidates[0], PathBuf::from("/tmp/debug/nagato"));
        assert_eq!(candidates.len(), 1);
    }

    #[test]
    fn includes_app_bundle_paths() {
        let candidates = build_nagato_binary_candidates(
            Some(Path::new(
                "/Applications/Unbound.app/Contents/MacOS/unbound-daemon",
            )),
            None,
        );

        assert!(candidates.contains(&PathBuf::from(
            "/Applications/Unbound.app/Contents/MacOS/nagato"
        )));
        assert!(candidates.contains(&PathBuf::from(
            "/Applications/Unbound.app/Contents/Helpers/nagato"
        )));
        assert!(candidates.contains(&PathBuf::from(
            "/Applications/Unbound.app/Contents/Resources/nagato"
        )));
    }
}
