//! System handlers.

use daemon_ipc::{
    error_codes, DaemonVersionInfo, DesktopCompatibilityRange, IpcServer, Method, Response,
    IPC_PROTOCOL_VERSION,
};
use tracing::info;

/// Register system handlers.
pub async fn register(server: &IpcServer, _state: crate::app::DaemonState) {
    server
        .register_handler(Method::SystemCheckDependencies, |req| async move {
            match runtime_capability_detector::check_all().await {
                Ok(result) => Response::success(&req.id, serde_json::to_value(&result).unwrap()),
                Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
            }
        })
        .await;

    server
        .register_handler(Method::SystemVersion, |req| async move {
            let daemon_version = env!("CARGO_PKG_VERSION").to_string();
            let version_info = DaemonVersionInfo {
                daemon_version: daemon_version.clone(),
                protocol_version: IPC_PROTOCOL_VERSION,
                desktop_compatibility: DesktopCompatibilityRange {
                    min_version: daemon_version.clone(),
                    max_version: daemon_version,
                    strict: true,
                },
            };

            Response::success(&req.id, serde_json::to_value(&version_info).unwrap())
        })
        .await;

    info!("Registered system handlers");
}
