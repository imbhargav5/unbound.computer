//! System handlers.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::info;

/// Register system handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::SystemCheckDependencies, |req| async move {
            match tien::check_all().await {
                Ok(result) => Response::success(&req.id, serde_json::to_value(&result).unwrap()),
                Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
            }
        })
        .await;

    let state_for_refresh = state.clone();
    server
        .register_handler(Method::SystemRefreshCapabilities, move |req| {
            let state = state_for_refresh.clone();
            async move {
                match state.auth_runtime.refresh_device_capabilities().await {
                    Ok(result) => {
                        Response::success(&req.id, serde_json::to_value(&result).unwrap())
                    }
                    Err(e) => {
                        Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string())
                    }
                }
            }
        })
        .await;

    info!("Registered system handlers");
}
