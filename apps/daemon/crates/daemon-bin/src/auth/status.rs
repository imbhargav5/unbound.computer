//! Authentication status handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};

/// Register the auth status handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthStatus, move |req| {
            let state = state.clone();
            async move {
                match state.auth_runtime.status() {
                    Ok(snapshot) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "logged_in": snapshot.authenticated,
                            "authenticated": snapshot.authenticated,
                            "state": snapshot.state,
                            "user_id": snapshot.user_id,
                            "email": snapshot.email,
                            "expires_at": snapshot.expires_at,
                        }),
                    ),
                    Err(error) => {
                        Response::error(&req.id, error_codes::INTERNAL_ERROR, &error.to_string())
                    }
                }
            }
        })
        .await;
}
