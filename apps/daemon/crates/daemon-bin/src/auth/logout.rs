//! Authentication logout handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register the auth logout handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthLogout, move |req| {
            let secrets = state.secrets.clone();
            let toshinori = state.toshinori.clone();
            let message_sync = state.message_sync.clone();
            async move {
                let result = tokio::task::spawn_blocking(move || {
                    let secrets = secrets.lock().unwrap();
                    secrets.clear_supabase_session()
                })
                .await
                .unwrap();

                match result {
                    Ok(()) => {
                        toshinori.clear_context().await;
                        message_sync.clear_context().await;
                        Response::success(&req.id, serde_json::json!({ "status": "logged_out" }))
                    }
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}
