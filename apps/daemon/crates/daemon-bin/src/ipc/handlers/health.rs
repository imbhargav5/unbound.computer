//! Health and shutdown handlers.

use daemon_ipc::{IpcServer, Method, Response};
use tracing::info;

/// Register health and shutdown handlers.
pub async fn register(server: &IpcServer) {
    // Health check
    server
        .register_handler(Method::Health, |req| async move {
            Response::success(
                &req.id,
                serde_json::json!({
                    "status": "ok",
                    "version": env!("CARGO_PKG_VERSION"),
                }),
            )
        })
        .await;

    // Shutdown
    let shutdown_tx = server.shutdown_sender();
    server
        .register_handler(Method::Shutdown, move |req| {
            let tx = shutdown_tx.clone();
            async move {
                // Send shutdown signal
                let _ = tx.send(());
                Response::success(&req.id, serde_json::json!({ "status": "shutting_down" }))
            }
        })
        .await;

    // Outbox status
    server
        .register_handler(Method::OutboxStatus, |req| async move {
            Response::success(
                &req.id,
                serde_json::json!({
                    "status": "ok",
                    "queues": 0,
                }),
            )
        })
        .await;

    info!("Registered health handlers");
}
