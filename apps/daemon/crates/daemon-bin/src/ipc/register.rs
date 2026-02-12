//! Handler registration for the IPC server.

use crate::app::DaemonState;
use crate::auth;
use crate::ipc::handlers;
use daemon_ipc::IpcServer;
use tracing::info;

/// Register all IPC handlers.
pub async fn register_handlers(server: &IpcServer, state: DaemonState) {
    // Register all handler modules
    handlers::health::register(server).await;
    auth::register_handlers(server, state.clone()).await;
    handlers::session::register(server, state.clone()).await;
    handlers::repository::register(server, state.clone()).await;
    handlers::message::register(server, state.clone()).await;
    handlers::claude::register(server, state.clone()).await;
    handlers::terminal::register(server, state.clone()).await;
    handlers::git::register(server, state.clone()).await;
    handlers::gh::register(server, state.clone()).await;
    handlers::system::register(server).await;

    // Note: Socket-based subscriptions are deprecated. Clients should use
    // IpcClient::subscribe() which opens shared memory directly for low-latency
    // event streaming (~1-5μs vs ~35-130μs for sockets).

    info!("All IPC handlers registered");
}
