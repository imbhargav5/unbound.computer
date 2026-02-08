//! Authentication logout handler.

use crate::app::DaemonState;
use crate::auth::common::clear_login_side_effects;
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register the auth logout handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthLogout, move |req| {
            let state = state.clone();
            async move {
                match state.auth_runtime.logout() {
                    Ok(()) => {
                        clear_login_side_effects(&state).await;
                        Response::success(&req.id, serde_json::json!({ "status": "logged_out" }))
                    }
                    Err(error) => {
                        Response::error(&req.id, error_codes::INTERNAL_ERROR, &error.to_string())
                    }
                }
            }
        })
        .await;
}
