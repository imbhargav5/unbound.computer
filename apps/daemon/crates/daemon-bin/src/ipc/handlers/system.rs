//! System handlers.

use crate::app::resolve_machine_space_scope;
use daemon_ipc::{
    error_codes, DaemonVersionInfo, DesktopCompatibilityRange, IpcServer, Method, Response,
    IPC_PROTOCOL_VERSION,
};
use rusqlite::params;
use tracing::info;

/// Register system handlers.
pub async fn register(server: &IpcServer, state: crate::app::DaemonState) {
    server
        .register_handler(Method::SystemCheckDependencies, |req| async move {
            match runtime_capability_detector::collect_capabilities().await {
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

    let scope_state = state.clone();
    server
        .register_handler(Method::SpaceGetCurrent, move |req| {
            let state = scope_state.clone();
            async move {
                let machine_id = {
                    let guard = state.device_id.lock().unwrap();
                    guard.clone()
                };
                let (machine_id, space_id) =
                    match resolve_machine_space_scope(&state.db, machine_id, None).await {
                        Ok(scope) => scope,
                        Err(error) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to resolve current space scope: {error}"),
                            );
                        }
                    };

                let (Some(machine_id), Some(space_id)) = (machine_id, space_id) else {
                    return Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        "Failed to resolve current machine/space identity",
                    );
                };

                let machine_id_for_db = machine_id.clone();
                let space_id_for_db = space_id.clone();
                let details = match state
                    .db
                    .call_with_operation("space_scope.get_current", move |conn| {
                        conn.query_row(
                            "SELECT
                                m.id, m.user_id, m.name,
                                s.id, s.user_id, s.name, s.machine_id, s.color, s.created_at
                             FROM spaces s
                             JOIN machines m ON m.id = s.machine_id
                             WHERE m.id = ?1 AND s.id = ?2",
                            params![machine_id_for_db, space_id_for_db],
                            |row| {
                                Ok(serde_json::json!({
                                    "machine": {
                                        "id": row.get::<_, String>(0)?,
                                        "user_id": row.get::<_, String>(1)?,
                                        "name": row.get::<_, String>(2)?,
                                    },
                                    "space": {
                                        "id": row.get::<_, String>(3)?,
                                        "user_id": row.get::<_, String>(4)?,
                                        "name": row.get::<_, String>(5)?,
                                        "machine_id": row.get::<_, String>(6)?,
                                        "color": row.get::<_, String>(7)?,
                                        "created_at": row.get::<_, String>(8)?,
                                    }
                                }))
                            },
                        )
                        .map_err(Into::into)
                    })
                    .await
                {
                    Ok(value) => value,
                    Err(error) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to fetch current space details: {error}"),
                        );
                    }
                };

                Response::success(&req.id, details)
            }
        })
        .await;

    info!("Registered system handlers");
}
