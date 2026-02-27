//! Authentication login handler.

use crate::app::DaemonState;
use crate::auth::common::apply_login_side_effects;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::info;
use auth_engine::AuthError;

/// Register the auth login handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthLogin, move |req| {
            let state = state.clone();
            async move {
                let provider = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("provider"))
                    .and_then(|v| v.as_str())
                    .map(str::trim)
                    .filter(|v| !v.is_empty())
                    .map(String::from);

                // Social-provider bootstrap path.
                if let Some(provider) = provider {
                    return match state.auth_runtime.start_social_login(&provider) {
                        Ok(start) => Response::success(
                            &req.id,
                            serde_json::json!({
                                "status": "social_login_started",
                                "provider": provider,
                                "login_id": start.login_id,
                                "login_url": start.login_url,
                            }),
                        ),
                        Err(error) => auth_error_response(&req.id, error),
                    };
                }

                // Email/password path.
                let email = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("email"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let password = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("password"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let (Some(email), Some(password)) = (email, password) else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "email/password or provider is required",
                    );
                };

                let device_name = hostname::get()
                    .map(|h| h.to_string_lossy().to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                match state
                    .auth_runtime
                    .login_with_password(&email, &password, current_device_type(), &device_name)
                    .await
                {
                    Ok(login) => {
                        apply_login_side_effects(&state, &login).await;

                        info!(
                            user_id = %login.user_id,
                            device_id = %login.device_id,
                            "Password login successful"
                        );

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
        _ => Response::error(request_id, error_codes::INTERNAL_ERROR, &error.to_string()),
    }
}
