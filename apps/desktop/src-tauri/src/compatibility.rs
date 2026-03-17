use daemon_ipc::{DaemonVersionInfo, IpcClient, Method, IPC_PROTOCOL_VERSION};
use semver::Version;
use serde::Serialize;
use std::collections::HashSet;
use std::env;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;
use tokio::time::{sleep, Duration};
use tracing::{info, warn};

const DEV_BASE_DIR_NAME: &str = ".unbound-dev";
const PROD_BASE_DIR_NAME: &str = ".unbound";
const DAEMON_NAMES: [&str; 2] = ["unbound-daemon", "daemon-bin"];
const STARTUP_WAIT_ATTEMPTS: usize = 160;
const STARTUP_WAIT_INTERVAL_MS: u64 = 250;

#[derive(Debug, Clone)]
pub struct RuntimePaths {
    pub base_dir: PathBuf,
    pub socket_path: PathBuf,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct DesktopBootstrapStatus {
    pub state: BootstrapState,
    pub message: String,
    pub expected_app_version: String,
    pub base_dir: String,
    pub socket_path: String,
    pub searched_paths: Vec<String>,
    pub resolved_daemon_path: Option<String>,
    pub daemon_info: Option<DaemonVersionInfo>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BootstrapState {
    Ready,
    MissingDaemon,
    IncompatibleDaemon,
    DaemonUnavailable,
}

pub fn resolve_runtime_paths() -> RuntimePaths {
    let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
    let configured_base_dir = env::var("UNBOUND_BASE_DIR")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    let base_dir = match configured_base_dir {
        Some(path) if Path::new(&path).is_absolute() => PathBuf::from(path),
        Some(path) => home_dir.join(path),
        None if cfg!(debug_assertions) => home_dir.join(DEV_BASE_DIR_NAME),
        None => home_dir.join(PROD_BASE_DIR_NAME),
    };

    let socket_path = base_dir.join("daemon.sock");
    RuntimePaths {
        base_dir,
        socket_path,
    }
}

pub async fn bootstrap(app_version: &str) -> DesktopBootstrapStatus {
    let runtime_paths = resolve_runtime_paths();
    let socket_path = runtime_paths.socket_path.display().to_string();
    let base_dir = runtime_paths.base_dir.display().to_string();
    let (resolved_daemon_path, searched_paths) = find_installed_daemon();

    info!(
        app_version,
        base_dir,
        socket_path,
        daemon_found = resolved_daemon_path.is_some(),
        "starting desktop compatibility bootstrap"
    );

    if ensure_daemon_available(&runtime_paths, resolved_daemon_path.as_deref())
        .await
        .is_err()
    {
        return match resolved_daemon_path {
            Some(path) => DesktopBootstrapStatus {
                state: BootstrapState::DaemonUnavailable,
                message:
                    "The daemon is installed but unavailable. Check the daemon logs or restart it."
                        .to_string(),
                expected_app_version: app_version.to_string(),
                base_dir,
                socket_path,
                searched_paths,
                resolved_daemon_path: Some(path.display().to_string()),
                daemon_info: None,
            },
            None => DesktopBootstrapStatus {
                state: BootstrapState::MissingDaemon,
                message:
                    "Unbound Desktop requires a separately installed compatible unbound-daemon."
                        .to_string(),
                expected_app_version: app_version.to_string(),
                base_dir,
                socket_path,
                searched_paths,
                resolved_daemon_path: None,
                daemon_info: None,
            },
        };
    }

    let client = ipc_client(&runtime_paths);
    let daemon_info = match fetch_version_info(&client).await {
        Ok(info) => info,
        Err(error) => {
            return DesktopBootstrapStatus {
                state: BootstrapState::DaemonUnavailable,
                message: format!(
                    "The daemon responded to health checks but version lookup failed: {error}"
                ),
                expected_app_version: app_version.to_string(),
                base_dir,
                socket_path,
                searched_paths,
                resolved_daemon_path: resolved_daemon_path
                    .as_ref()
                    .map(|path| path.display().to_string()),
                daemon_info: None,
            };
        }
    };

    match validate_compatibility(app_version, &daemon_info) {
        Ok(()) => DesktopBootstrapStatus {
            state: BootstrapState::Ready,
            message: "Connected to a compatible daemon.".to_string(),
            expected_app_version: app_version.to_string(),
            base_dir,
            socket_path,
            searched_paths,
            resolved_daemon_path: resolved_daemon_path
                .as_ref()
                .map(|path| path.display().to_string()),
            daemon_info: Some(daemon_info),
        },
        Err(message) => DesktopBootstrapStatus {
            state: BootstrapState::IncompatibleDaemon,
            message,
            expected_app_version: app_version.to_string(),
            base_dir,
            socket_path,
            searched_paths,
            resolved_daemon_path: resolved_daemon_path
                .as_ref()
                .map(|path| path.display().to_string()),
            daemon_info: Some(daemon_info),
        },
    }
}

pub fn ipc_client(runtime_paths: &RuntimePaths) -> IpcClient {
    IpcClient::new(runtime_paths.socket_path.to_string_lossy().as_ref())
}

async fn ensure_daemon_available(
    runtime_paths: &RuntimePaths,
    daemon_path: Option<&Path>,
) -> Result<(), String> {
    let client = ipc_client(runtime_paths);
    if client.call_method(Method::Health).await.is_ok() {
        return Ok(());
    }

    if runtime_paths.socket_path.exists() {
        return Err(
            "daemon socket exists but health checks failed; refusing to replace the running daemon"
                .to_string(),
        );
    }

    let daemon_path = daemon_path.ok_or_else(|| "daemon not found".to_string())?;
    std::fs::create_dir_all(&runtime_paths.base_dir)
        .map_err(|error| format!("failed to create runtime directory: {error}"))?;

    start_daemon(daemon_path, &runtime_paths.base_dir).await?;
    wait_for_daemon(runtime_paths).await
}

async fn start_daemon(daemon_path: &Path, base_dir: &Path) -> Result<(), String> {
    info!(
        daemon_path = %daemon_path.display(),
        base_dir = %base_dir.display(),
        "starting daemon from desktop bootstrap"
    );

    let mut command = Command::new(daemon_path);
    command
        .arg("start")
        .arg("--base-dir")
        .arg(base_dir)
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    command
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("failed to start daemon: {error}"))
}

async fn wait_for_daemon(runtime_paths: &RuntimePaths) -> Result<(), String> {
    for _ in 0..STARTUP_WAIT_ATTEMPTS {
        if runtime_paths.socket_path.exists() {
            let client = ipc_client(runtime_paths);
            if client.call_method(Method::Health).await.is_ok() {
                info!(
                    socket_path = %runtime_paths.socket_path.display(),
                    "daemon passed desktop health checks"
                );
                return Ok(());
            }
        }

        sleep(Duration::from_millis(STARTUP_WAIT_INTERVAL_MS)).await;
    }

    warn!(
        socket_path = %runtime_paths.socket_path.display(),
        attempts = STARTUP_WAIT_ATTEMPTS,
        "timed out waiting for daemon startup"
    );
    Err("timed out waiting for daemon startup".to_string())
}

async fn fetch_version_info(client: &IpcClient) -> Result<DaemonVersionInfo, String> {
    let response = client
        .call_method(Method::SystemVersion)
        .await
        .map_err(|error| format!("system.version IPC call failed: {error}"))?;

    if let Some(error) = response.error {
        return Err(error.message);
    }

    let result = response
        .result
        .ok_or_else(|| "system.version returned no result".to_string())?;

    serde_json::from_value(result)
        .map_err(|error| format!("invalid system.version payload: {error}"))
}

fn validate_compatibility(
    app_version: &str,
    daemon_info: &DaemonVersionInfo,
) -> Result<(), String> {
    if daemon_info.protocol_version != IPC_PROTOCOL_VERSION {
        return Err(format!(
            "Protocol mismatch. Desktop expects protocol {} but the daemon exposes {}.",
            IPC_PROTOCOL_VERSION, daemon_info.protocol_version
        ));
    }

    let app_version = Version::parse(app_version)
        .map_err(|error| format!("invalid desktop version {app_version}: {error}"))?;
    let min_version = Version::parse(&daemon_info.desktop_compatibility.min_version)
        .map_err(|error| format!("invalid daemon min version: {error}"))?;
    let max_version = Version::parse(&daemon_info.desktop_compatibility.max_version)
        .map_err(|error| format!("invalid daemon max version: {error}"))?;

    if app_version < min_version || app_version > max_version {
        return Err(format!(
            "Daemon {} only supports desktop versions {} through {}.",
            daemon_info.daemon_version,
            daemon_info.desktop_compatibility.min_version,
            daemon_info.desktop_compatibility.max_version
        ));
    }

    Ok(())
}

fn find_installed_daemon() -> (Option<PathBuf>, Vec<String>) {
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();

    for candidate in [
        "/usr/local/bin/unbound-daemon",
        "/opt/homebrew/bin/unbound-daemon",
        "~/.cargo/bin/unbound-daemon",
        "~/.local/bin/unbound-daemon",
        "/usr/local/bin/daemon-bin",
        "/opt/homebrew/bin/daemon-bin",
        "~/.cargo/bin/daemon-bin",
        "~/.local/bin/daemon-bin",
    ] {
        push_candidate(&mut candidates, &mut seen, expand_tilde(candidate));
    }

    if let Some(path_value) = env::var_os("PATH") {
        for directory in env::split_paths(&path_value) {
            for binary_name in DAEMON_NAMES {
                push_candidate(&mut candidates, &mut seen, directory.join(binary_name));
            }
        }
    }

    let resolved = candidates
        .iter()
        .find(|candidate| candidate.is_file() && is_executable(candidate))
        .cloned();

    let searched_paths = candidates
        .into_iter()
        .map(|candidate| candidate.display().to_string())
        .collect();

    (resolved, searched_paths)
}

fn push_candidate(candidates: &mut Vec<PathBuf>, seen: &mut HashSet<String>, path: PathBuf) {
    let key = path.display().to_string();
    if seen.insert(key) {
        candidates.push(path);
    }
}

fn expand_tilde(candidate: &str) -> PathBuf {
    if let Some(stripped) = candidate.strip_prefix("~/") {
        if let Some(home_dir) = dirs::home_dir() {
            return home_dir.join(stripped);
        }
    }
    PathBuf::from(candidate)
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;

    std::fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_runtime_paths_uses_debug_default_in_tests() {
        let runtime_paths = resolve_runtime_paths();
        assert!(runtime_paths.socket_path.ends_with("daemon.sock"));
    }

    #[test]
    fn compatibility_rejects_protocol_mismatch() {
        let daemon_info = DaemonVersionInfo {
            daemon_version: "0.0.19".to_string(),
            protocol_version: IPC_PROTOCOL_VERSION + 1,
            desktop_compatibility: daemon_ipc::DesktopCompatibilityRange {
                min_version: "0.0.19".to_string(),
                max_version: "0.0.19".to_string(),
                strict: true,
            },
        };

        let error = validate_compatibility("0.0.19", &daemon_info).expect_err("must reject");
        assert!(error.contains("Protocol mismatch"));
    }

    #[test]
    fn compatibility_accepts_matching_version_range() {
        let daemon_info = DaemonVersionInfo {
            daemon_version: "0.0.19".to_string(),
            protocol_version: IPC_PROTOCOL_VERSION,
            desktop_compatibility: daemon_ipc::DesktopCompatibilityRange {
                min_version: "0.0.19".to_string(),
                max_version: "0.0.19".to_string(),
                strict: true,
            },
        };

        validate_compatibility("0.0.19", &daemon_info).expect("matching range");
    }
}
