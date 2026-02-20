//! Supabase session token handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::warn;

/// Register the Supabase session handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthSupabaseSession, move |req| {
            let state = state.clone();
            async move {
                let sync_context = match state.auth_runtime.current_sync_context() {
                    Ok(Some(context)) => context,
                    Ok(None) => {
                        return Response::error(
                            &req.id,
                            error_codes::NOT_AUTHENTICATED,
                            "Not authenticated",
                        )
                    }
                    Err(err) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &err.to_string(),
                        )
                    }
                };

                let expires_at = match state.auth_runtime.status().await {
                    Ok(snapshot) => snapshot.expires_at,
                    Err(err) => {
                        warn!(error = %err, "Failed to read auth status for supabase session");
                        None
                    }
                };

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "access_token": sync_context.access_token,
                        "user_id": sync_context.user_id,
                        "device_id": sync_context.device_id,
                        "expires_at": expires_at,
                    }),
                )
            }
        })
        .await;
}
