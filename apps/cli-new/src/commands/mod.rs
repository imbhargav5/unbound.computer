//! CLI command implementations.

mod auth;
mod daemon;
mod repos;
mod sessions;

pub use auth::{login, logout, status};
pub use daemon::{daemon_start, daemon_stop, daemon_status, daemon_logs};
pub use repos::{repos_list, repos_add, repos_remove};
pub use sessions::{sessions_list, sessions_show, sessions_create, sessions_delete, sessions_messages};

use anyhow::Result;
use daemon_config_and_utils::Paths;
use daemon_ipc::IpcClient;

/// Get the IPC client for communicating with the daemon.
pub fn get_ipc_client() -> Result<IpcClient> {
    let paths = Paths::new()?;
    Ok(IpcClient::new(&paths.socket_file().to_string_lossy()))
}

/// Get IPC client if daemon is running.
pub async fn get_daemon_client() -> Result<IpcClient> {
    let client = get_ipc_client()?;
    if !client.is_daemon_running().await {
        anyhow::bail!("Daemon is not running");
    }
    Ok(client)
}

/// Check if the daemon is running.
async fn is_daemon_running() -> bool {
    if let Ok(client) = get_ipc_client() {
        client.is_daemon_running().await
    } else {
        false
    }
}

/// Ensure the daemon is running, or print an error.
async fn require_daemon() -> Result<IpcClient> {
    let client = get_ipc_client()?;

    if !client.is_daemon_running().await {
        anyhow::bail!("Daemon is not running. Start it with 'unbound daemon start'");
    }

    Ok(client)
}
