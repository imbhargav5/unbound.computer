//! Authentication module.
//!
//! Handles user authentication, session management, and device identity.

mod login;
mod logout;
mod status;

use crate::app::DaemonState;
use daemon_ipc::IpcServer;

/// Register all authentication handlers.
pub async fn register_handlers(server: &IpcServer, state: DaemonState) {
    status::register(server, state.clone()).await;
    logout::register(server, state.clone()).await;
    login::register(server, state).await;
}
