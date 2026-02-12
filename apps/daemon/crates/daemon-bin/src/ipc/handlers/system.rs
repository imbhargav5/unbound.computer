//! System handlers.

use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::info;

/// Register system handlers.
pub async fn register(server: &IpcServer) {
    server
        .register_handler(Method::SystemCheckDependencies, |req| async move {
            match tien::check_all().await {
                Ok(result) => Response::success(
                    &req.id,
                    serde_json::to_value(&result).unwrap(),
                ),
                Err(e) => Response::error(
                    &req.id,
                    error_codes::INTERNAL_ERROR,
                    &e.to_string(),
                ),
            }
        })
        .await;

    info!("Registered system handlers");
}
