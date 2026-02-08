//! Social-provider auth completion handler.

use crate::app::DaemonState;
use crate::auth::common::apply_login_side_effects;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use std::time::Duration;
use ymir::AuthError;

const DEFAULT_TIMEOUT_SECS: u64 = 180;
const MAX_TIMEOUT_SECS: u64 = 600;

/// Register the social auth completion handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthCompleteSocial, move |req| {
            let state = state.clone();
            async move {
                let login_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("login_id"))
                    .and_then(|v| v.as_str())
                    .map(str::trim)
                    .filter(|v| !v.is_empty())
                    .map(String::from);

                let Some(login_id) = login_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "login_id is required",
                    );
                };

                let timeout_secs = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("timeout_secs"))
                    .and_then(|v| v.as_u64())
                    .unwrap_or(DEFAULT_TIMEOUT_SECS)
                    .min(MAX_TIMEOUT_SECS);

                let device_name = hostname::get()
                    .map(|h| h.to_string_lossy().to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                match state
                    .auth_runtime
                    .complete_social_login(
                        &login_id,
                        Duration::from_secs(timeout_secs),
                        current_device_type(),
                        &device_name,
                    )
                    .await
                {
                    Ok(login) => {
                        apply_login_side_effects(&state, &login).await;

                        Response::success(
                            &req.id,
                            serde_json::json!({
                                "status": "logged_in",
                                "user_id": login.user_id,
                                "email": login.email,
                                "expires_at": login.expires_at,
                                "device_id": login.device_id,
                            }),
                        )
                    }
                    Err(error) => auth_error_response(&req.id, error),
                }
            }
        })
        .await;
}

fn current_device_type() -> &'static str {
    if cfg!(target_os = "macos") {
        "mac-desktop"
    } else if cfg!(target_os = "windows") {
        "win-desktop"
    } else {
        "linux-desktop"
    }
}

fn auth_error_response(request_id: &str, error: AuthError) -> Response {
    match error {
        AuthError::InvalidCredentials(_)
        | AuthError::NotLoggedIn
        | AuthError::SessionExpired
        | AuthError::SessionInvalid(_) => Response::error(
            request_id,
            error_codes::NOT_AUTHENTICATED,
            &error.to_string(),
        ),
        AuthError::Config(_) => {
            Response::error(request_id, error_codes::INVALID_PARAMS, &error.to_string())
        }
        AuthError::Timeout => Response::error(
            request_id,
            error_codes::NOT_AUTHENTICATED,
            "social login timed out",
        ),
        _ => Response::error(request_id, error_codes::INTERNAL_ERROR, &error.to_string()),
    }
}
