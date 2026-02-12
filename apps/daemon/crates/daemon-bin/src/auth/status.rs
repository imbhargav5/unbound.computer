//! Authentication status handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use ymir::AuthSnapshot;

fn auth_status_payload(snapshot: &AuthSnapshot) -> serde_json::Value {
    // Keep compatibility aliases (`logged_in`, `authenticated`) pinned to
    // canonical `session_valid` semantics.
    let session_valid = snapshot.session_valid;
    serde_json::json!({
        "logged_in": session_valid,
        "authenticated": session_valid,
        "session_valid": session_valid,
        "has_stored_session": snapshot.has_stored_session,
        "state": snapshot.state,
        "user_id": snapshot.user_id,
        "email": snapshot.email,
        "expires_at": snapshot.expires_at,
    })
}

/// Register the auth status handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthStatus, move |req| {
            let state = state.clone();
            async move {
                match state.auth_runtime.status().await {
                    Ok(snapshot) => Response::success(&req.id, auth_status_payload(&snapshot)),
                    Err(error) => {
                        Response::error(&req.id, error_codes::INTERNAL_ERROR, &error.to_string())
                    }
                }
            }
        })
        .await;
}

#[cfg(test)]
mod tests {
    use super::auth_status_payload;
    use ymir::{AuthSnapshot, AuthState};

    #[test]
    fn auth_status_payload_includes_new_contract_fields() {
        let snapshot = AuthSnapshot {
            state: AuthState::PendingValidation,
            has_stored_session: true,
            session_valid: false,
            authenticated: false,
            user_id: Some("user-123".to_string()),
            email: Some("user@example.com".to_string()),
            expires_at: Some("2030-01-01T00:00:00Z".to_string()),
        };

        let payload = auth_status_payload(&snapshot);
        assert_eq!(
            payload.get("state").and_then(|v| v.as_str()),
            Some("pending_validation")
        );
        assert_eq!(
            payload.get("has_stored_session").and_then(|v| v.as_bool()),
            Some(true)
        );
        assert_eq!(
            payload.get("session_valid").and_then(|v| v.as_bool()),
            Some(false)
        );
    }

    #[test]
    fn auth_status_payload_keeps_authenticated_alias_equal_to_session_valid() {
        // Intentionally inconsistent snapshot to prove payload contract.
        let snapshot = AuthSnapshot {
            state: AuthState::LoggedIn,
            has_stored_session: true,
            session_valid: false,
            authenticated: true,
            user_id: Some("user-456".to_string()),
            email: Some("user@example.com".to_string()),
            expires_at: Some("2030-01-01T00:00:00Z".to_string()),
        };

        let payload = auth_status_payload(&snapshot);
        assert_eq!(
            payload.get("authenticated").and_then(|v| v.as_bool()),
            Some(false)
        );
        assert_eq!(
            payload.get("session_valid").and_then(|v| v.as_bool()),
            Some(false)
        );
        assert_eq!(
            payload.get("logged_in").and_then(|v| v.as_bool()),
            Some(false)
        );
    }
}
