//! GitHub CLI handlers.

use crate::app::DaemonState;
use bakugou::{
    auth_status, pr_checks, pr_create, pr_list, pr_merge, pr_view, AuthStatusInput, BakugouError,
    PrChecksInput, PrCreateInput, PrListInput, PrMergeInput, PrViewInput,
};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use sakura_working_dir_resolution::{
    resolve_repository_path, resolve_working_dir_from_str, ResolveError,
};
use serde::de::DeserializeOwned;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct GhCoreError {
    pub code: String,
    pub message: String,
}

/// Register GitHub CLI handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_gh_auth_status(server).await;
    register_gh_pr_create(server, state.clone()).await;
    register_gh_pr_view(server, state.clone()).await;
    register_gh_pr_list(server, state.clone()).await;
    register_gh_pr_checks(server, state.clone()).await;
    register_gh_pr_merge(server, state).await;
}

/// Core logic for gh.auth_status shared between IPC and other call sites.
pub async fn gh_auth_status_core(
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let input: AuthStatusInput = parse_input(params)?;
    let result = auth_status(input).await.map_err(map_bakugou_error)?;
    Ok(serde_json::to_value(result).unwrap())
}

/// Core logic for gh.pr_create shared between IPC and remote command paths.
pub async fn gh_pr_create_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let working_dir = resolve_working_dir(state, params)?;
    let input: PrCreateInput = parse_input(params)?;
    let result = pr_create(Path::new(&working_dir), input)
        .await
        .map_err(map_bakugou_error)?;
    Ok(serde_json::to_value(result).unwrap())
}

/// Core logic for gh.pr_view shared between IPC and remote command paths.
pub async fn gh_pr_view_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let working_dir = resolve_working_dir(state, params)?;
    let input: PrViewInput = parse_input(params)?;
    let pull_request = pr_view(Path::new(&working_dir), input)
        .await
        .map_err(map_bakugou_error)?;

    Ok(serde_json::json!({
        "pull_request": pull_request,
    }))
}

/// Core logic for gh.pr_list shared between IPC and remote command paths.
pub async fn gh_pr_list_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let working_dir = resolve_working_dir(state, params)?;
    let input: PrListInput = parse_input(params)?;
    let result = pr_list(Path::new(&working_dir), input)
        .await
        .map_err(map_bakugou_error)?;

    Ok(serde_json::to_value(result).unwrap())
}

/// Core logic for gh.pr_checks shared between IPC and remote command paths.
pub async fn gh_pr_checks_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let working_dir = resolve_working_dir(state, params)?;
    let input: PrChecksInput = parse_input(params)?;
    let result = pr_checks(Path::new(&working_dir), input)
        .await
        .map_err(map_bakugou_error)?;

    Ok(serde_json::to_value(result).unwrap())
}

/// Core logic for gh.pr_merge shared between IPC and remote command paths.
pub async fn gh_pr_merge_core(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<serde_json::Value, GhCoreError> {
    let working_dir = resolve_working_dir(state, params)?;
    let input: PrMergeInput = parse_input(params)?;
    let result = pr_merge(Path::new(&working_dir), input)
        .await
        .map_err(map_bakugou_error)?;

    Ok(serde_json::to_value(result).unwrap())
}

async fn register_gh_auth_status(server: &IpcServer) {
    server
        .register_handler(Method::GhAuthStatus, move |req| async move {
            let params = req
                .params
                .as_ref()
                .cloned()
                .unwrap_or(serde_json::json!({}));
            match gh_auth_status_core(&params).await {
                Ok(result) => Response::success(&req.id, result),
                Err(err) => gh_core_error_response(&req.id, err),
            }
        })
        .await;
}

async fn register_gh_pr_create(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GhPrCreate, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match gh_pr_create_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => gh_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

async fn register_gh_pr_view(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GhPrView, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match gh_pr_view_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => gh_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

async fn register_gh_pr_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GhPrList, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match gh_pr_list_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => gh_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

async fn register_gh_pr_checks(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GhPrChecks, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match gh_pr_checks_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => gh_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

async fn register_gh_pr_merge(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::GhPrMerge, move |req| {
            let state = state.clone();
            async move {
                let params = req
                    .params
                    .as_ref()
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                match gh_pr_merge_core(&state, &params).await {
                    Ok(result) => Response::success(&req.id, result),
                    Err(err) => gh_core_error_response(&req.id, err),
                }
            }
        })
        .await;
}

fn parse_input<T: DeserializeOwned>(params: &serde_json::Value) -> Result<T, GhCoreError> {
    serde_json::from_value(params.clone()).map_err(|err| GhCoreError {
        code: "invalid_params".to_string(),
        message: format!("invalid parameters: {err}"),
    })
}

fn resolve_working_dir(
    state: &DaemonState,
    params: &serde_json::Value,
) -> Result<String, GhCoreError> {
    if let Some(session_id) = params.get("session_id").and_then(|v| v.as_str()) {
        if session_id.trim().is_empty() {
            return Err(GhCoreError {
                code: "invalid_params".to_string(),
                message: "session_id must not be empty".to_string(),
            });
        }
        return resolve_working_dir_from_str(&*state.armin, session_id)
            .map(|resolved| resolved.working_dir)
            .map_err(map_resolve_error);
    }

    if let Some(repository_id) = params.get("repository_id").and_then(|v| v.as_str()) {
        if repository_id.trim().is_empty() {
            return Err(GhCoreError {
                code: "invalid_params".to_string(),
                message: "repository_id must not be empty".to_string(),
            });
        }
        return resolve_repository_path(&*state.armin, repository_id).map_err(map_resolve_error);
    }

    if let Some(path) = params.get("path").and_then(|v| v.as_str()) {
        if path.trim().is_empty() {
            return Err(GhCoreError {
                code: "invalid_params".to_string(),
                message: "path must not be empty".to_string(),
            });
        }
        return Ok(path.to_string());
    }

    Err(GhCoreError {
        code: "invalid_params".to_string(),
        message: "one of session_id, repository_id, or path is required".to_string(),
    })
}

fn map_resolve_error(err: ResolveError) -> GhCoreError {
    match err {
        ResolveError::SessionNotFound(message) => GhCoreError {
            code: "not_found".to_string(),
            message,
        },
        ResolveError::RepositoryNotFound(message) => GhCoreError {
            code: "not_found".to_string(),
            message,
        },
        ResolveError::LegacyWorktreeUnsupported(message) => GhCoreError {
            code: "legacy_worktree_unsupported".to_string(),
            message,
        },
        ResolveError::Armin(err) => GhCoreError {
            code: "command_failed".to_string(),
            message: format!("failed to resolve working directory: {err}"),
        },
    }
}

fn map_bakugou_error(err: BakugouError) -> GhCoreError {
    GhCoreError {
        code: err.code().to_string(),
        message: err.to_string(),
    }
}

fn gh_core_error_response(id: &str, err: GhCoreError) -> Response {
    Response::error_with_data(
        id,
        map_rpc_code(&err.code),
        &err.message,
        serde_json::json!({
            "code": err.code,
        }),
    )
}

fn map_rpc_code(machine_code: &str) -> i32 {
    match machine_code {
        "invalid_params" => error_codes::INVALID_PARAMS,
        "invalid_repository" | "not_found" => error_codes::NOT_FOUND,
        _ => error_codes::INTERNAL_ERROR,
    }
}

#[cfg(test)]
mod tests {
    use super::{map_resolve_error, map_rpc_code, parse_input, GhCoreError};
    use agent_session_sqlite_persist_core::ArminError;
    use bakugou::PrListInput;
    use daemon_ipc::error_codes;
    use sakura_working_dir_resolution::ResolveError;

    #[test]
    fn parse_input_rejects_invalid_shape() {
        let params = serde_json::json!({
            "state": "open",
            "limit": "twenty"
        });

        let err = parse_input::<PrListInput>(&params).expect_err("expected parse failure");
        assert_eq!(err.code, "invalid_params");
        assert!(err.message.contains("invalid parameters"));
    }

    #[test]
    fn map_rpc_code_uses_expected_json_rpc_codes() {
        assert_eq!(map_rpc_code("invalid_params"), error_codes::INVALID_PARAMS);
        assert_eq!(map_rpc_code("invalid_repository"), error_codes::NOT_FOUND);
        assert_eq!(map_rpc_code("not_found"), error_codes::NOT_FOUND);
        assert_eq!(
            map_rpc_code("legacy_worktree_unsupported"),
            error_codes::INTERNAL_ERROR
        );
        assert_eq!(map_rpc_code("command_failed"), error_codes::INTERNAL_ERROR);
    }

    #[test]
    fn resolve_error_maps_session_and_repo_not_found() {
        let session =
            map_resolve_error(ResolveError::SessionNotFound("missing session".to_string()));
        assert_eq!(session.code, "not_found");
        assert_eq!(session.message, "missing session");

        let repo = map_resolve_error(ResolveError::RepositoryNotFound("missing repo".to_string()));
        assert_eq!(repo.code, "not_found");
        assert_eq!(repo.message, "missing repo");
    }

    #[test]
    fn resolve_error_maps_legacy_worktree_to_machine_code() {
        let err = map_resolve_error(ResolveError::LegacyWorktreeUnsupported(
            "/repo/.unbound-worktrees/sess-1".to_string(),
        ));
        assert_eq!(err.code, "legacy_worktree_unsupported");
        assert!(err.message.contains(".unbound-worktrees"));
    }

    #[test]
    fn resolve_error_maps_armin_to_command_failed() {
        let err = map_resolve_error(ResolveError::Armin(ArminError::SessionNotFound(
            "sess-1".to_string(),
        )));
        assert_eq!(err.code, "command_failed");
        assert!(err.message.contains("failed to resolve working directory"));
    }

    #[test]
    fn gh_core_error_struct_is_stable() {
        let err = GhCoreError {
            code: "timeout".to_string(),
            message: "operation timed out".to_string(),
        };
        assert_eq!(err.code, "timeout");
        assert_eq!(err.message, "operation timed out");
    }
}
