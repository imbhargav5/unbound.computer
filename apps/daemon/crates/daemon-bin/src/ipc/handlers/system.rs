//! System handlers.

use crate::app::{resolve_machine_space_scope, DaemonState};
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
                match load_current_space_scope(&state).await {
                    Ok(details) => Response::success(&req.id, details),
                    Err(message) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &message),
                }
            }
        })
        .await;

    let update_machine_state = state.clone();
    server
        .register_handler(Method::SpaceUpdateCurrentMachineName, move |req| {
            let state = update_machine_state.clone();
            async move {
                let Some(name) = req
                    .params
                    .as_ref()
                    .and_then(|params| params.get("name"))
                    .and_then(|value| value.as_str())
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(str::to_owned)
                else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "name is required",
                    );
                };

                let machine_id = {
                    let guard = state.device_id.lock().unwrap();
                    guard.clone()
                };

                let (machine_id, _) =
                    match resolve_machine_space_scope(&state.db, machine_id, None).await {
                        Ok(scope) => scope,
                        Err(error) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Failed to resolve current machine scope: {error}"),
                            );
                        }
                    };

                let Some(machine_id) = machine_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INTERNAL_ERROR,
                        "Failed to resolve current machine identity",
                    );
                };

                let machine_id_for_db = machine_id.clone();
                let update_result = state
                    .db
                    .call_with_operation("space_scope.update_current_machine_name", move |conn| {
                        Ok(conn.execute(
                            "UPDATE machines SET name = ?1 WHERE id = ?2",
                            params![name, machine_id_for_db],
                        )?)
                    })
                    .await;

                match update_result {
                    Ok(0) => {
                        return Response::error(
                            &req.id,
                            error_codes::NOT_FOUND,
                            "Current machine not found",
                        );
                    }
                    Ok(_) => {}
                    Err(error) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to update current machine name: {error}"),
                        );
                    }
                }

                match load_current_space_scope(&state).await {
                    Ok(details) => Response::success(&req.id, details),
                    Err(message) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &message),
                }
            }
        })
        .await;

    info!("Registered system handlers");
}

async fn load_current_space_scope(state: &DaemonState) -> Result<serde_json::Value, String> {
    let machine_id = {
        let guard = state.device_id.lock().unwrap();
        guard.clone()
    };
    let (machine_id, space_id) = resolve_machine_space_scope(&state.db, machine_id, None)
        .await
        .map_err(|error| format!("Failed to resolve current space scope: {error}"))?;

    let (Some(machine_id), Some(space_id)) = (machine_id, space_id) else {
        return Err("Failed to resolve current machine/space identity".to_string());
    };

    let machine_id_for_db = machine_id.clone();
    let space_id_for_db = space_id.clone();
    state
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
        .map_err(|error| format!("Failed to fetch current space details: {error}"))
}
