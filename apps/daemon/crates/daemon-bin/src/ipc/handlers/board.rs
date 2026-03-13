//! Local board IPC handlers.

use crate::app::DaemonState;
use daemon_board::service;
use daemon_board::{
    AddIssueCommentInput, ApprovalDecisionInput, BoardError, CreateAgentInput, CreateCompanyInput,
    CreateIssueInput, CreateProjectInput, IssueListFilter,
};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use serde::de::DeserializeOwned;
use serde_json::Value;

pub async fn register(server: &IpcServer, state: DaemonState) {
    register_company_handlers(server, state.clone()).await;
    register_agent_handlers(server, state.clone()).await;
    register_goal_handlers(server, state.clone()).await;
    register_project_handlers(server, state.clone()).await;
    register_issue_handlers(server, state.clone()).await;
    register_approval_handlers(server, state.clone()).await;
    register_workspace_handlers(server, state).await;
}

async fn register_company_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::CompanyList, move |req| {
            let db = list_db.clone();
            async move {
                match service::list_companies(&db).await {
                    Ok(companies) => json_response(&req.id, &serde_json::json!({ "companies": companies })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::CompanyGet, move |req| {
            let db = get_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::get_company(&db, &company_id).await {
                    Ok(Some(company)) => json_response(&req.id, &serde_json::json!({ "company": company })),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Company not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let create_db = state.db.clone();
    let create_paths = state.paths.clone();
    server
        .register_handler(Method::CompanyCreate, move |req| {
            let db = create_db.clone();
            let paths = create_paths.clone();
            async move {
                let input = match parse_params::<CreateCompanyInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_company(&db, &paths, input).await {
                    Ok(company) => json_response(&req.id, &serde_json::json!({ "company": company })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_agent_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::AgentList, move |req| {
            let db = list_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::list_agents(&db, &company_id).await {
                    Ok(agents) => json_response(&req.id, &serde_json::json!({ "agents": agents })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::AgentGet, move |req| {
            let db = get_db.clone();
            async move {
                let agent_id = match required_string_param(&req.id, req.params.as_ref(), "agent_id") {
                    Ok(agent_id) => agent_id,
                    Err(response) => return response,
                };
                match service::get_agent(&db, &agent_id).await {
                    Ok(Some(agent)) => json_response(&req.id, &serde_json::json!({ "agent": agent })),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Agent not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let create_db = state.db.clone();
    let create_paths = state.paths.clone();
    server
        .register_handler(Method::AgentCreate, move |req| {
            let db = create_db.clone();
            let paths = create_paths.clone();
            async move {
                let input = match parse_params::<CreateAgentInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_agent(&db, &paths, input).await {
                    Ok(agent) => json_response(&req.id, &serde_json::json!({ "agent": agent })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_goal_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::GoalList, move |req| {
            let db = list_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::list_goals(&db, &company_id).await {
                    Ok(goals) => json_response(&req.id, &serde_json::json!({ "goals": goals })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_project_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::ProjectList, move |req| {
            let db = list_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::list_projects(&db, &company_id).await {
                    Ok(projects) => json_response(&req.id, &serde_json::json!({ "projects": projects })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::ProjectGet, move |req| {
            let db = get_db.clone();
            async move {
                let project_id = match required_string_param(&req.id, req.params.as_ref(), "project_id") {
                    Ok(project_id) => project_id,
                    Err(response) => return response,
                };
                match service::get_project(&db, &project_id).await {
                    Ok(Some(project)) => json_response(&req.id, &serde_json::json!({ "project": project })),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Project not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let create_db = state.db.clone();
    server
        .register_handler(Method::ProjectCreate, move |req| {
            let db = create_db.clone();
            async move {
                let input = match parse_params::<CreateProjectInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_project(&db, input).await {
                    Ok(project) => json_response(&req.id, &serde_json::json!({ "project": project })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_issue_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::IssueList, move |req| {
            let db = list_db.clone();
            async move {
                let filter = match parse_params::<IssueListFilter>(&req.id, req.params.as_ref()) {
                    Ok(filter) => filter,
                    Err(response) => return response,
                };
                match service::list_issues(&db, filter).await {
                    Ok(issues) => json_response(&req.id, &serde_json::json!({ "issues": issues })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::IssueGet, move |req| {
            let db = get_db.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id") {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::get_issue(&db, &issue_id).await {
                    Ok(Some(issue)) => json_response(&req.id, &serde_json::json!({ "issue": issue })),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Issue not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let create_db = state.db.clone();
    server
        .register_handler(Method::IssueCreate, move |req| {
            let db = create_db.clone();
            async move {
                let input = match parse_params::<CreateIssueInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_issue(&db, input).await {
                    Ok(issue) => json_response(&req.id, &serde_json::json!({ "issue": issue })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let comment_list_db = state.db.clone();
    server
        .register_handler(Method::IssueCommentList, move |req| {
            let db = comment_list_db.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id") {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::list_issue_comments(&db, &issue_id).await {
                    Ok(comments) => json_response(&req.id, &serde_json::json!({ "comments": comments })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let comment_add_db = state.db.clone();
    server
        .register_handler(Method::IssueCommentAdd, move |req| {
            let db = comment_add_db.clone();
            async move {
                let input = match parse_params::<AddIssueCommentInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::add_issue_comment(&db, input).await {
                    Ok(comment) => json_response(&req.id, &serde_json::json!({ "comment": comment })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let checkout_db = state.db.clone();
    let checkout_armin = state.armin.clone();
    server
        .register_handler(Method::IssueCheckout, move |req| {
            let db = checkout_db.clone();
            let armin = checkout_armin.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id") {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::start_issue_workspace(&db, armin.as_ref(), &issue_id).await {
                    Ok(workspace) => {
                        json_response(&req.id, &serde_json::json!({ "workspace": workspace }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_approval_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::ApprovalList, move |req| {
            let db = list_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::list_approvals(&db, &company_id).await {
                    Ok(approvals) => {
                        json_response(&req.id, &serde_json::json!({ "approvals": approvals }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::ApprovalGet, move |req| {
            let db = get_db.clone();
            async move {
                let approval_id = match required_string_param(&req.id, req.params.as_ref(), "approval_id") {
                    Ok(approval_id) => approval_id,
                    Err(response) => return response,
                };
                match service::get_approval(&db, &approval_id).await {
                    Ok(Some(approval)) => {
                        json_response(&req.id, &serde_json::json!({ "approval": approval }))
                    }
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Approval not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let approve_db = state.db.clone();
    server
        .register_handler(Method::ApprovalApprove, move |req| {
            let db = approve_db.clone();
            async move {
                let input = match parse_params::<ApprovalDecisionInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::approve_approval(&db, input).await {
                    Ok(approval) => {
                        json_response(&req.id, &serde_json::json!({ "approval": approval }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_workspace_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::WorkspaceList, move |req| {
            let db = list_db.clone();
            async move {
                let company_id = match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                    Ok(company_id) => company_id,
                    Err(response) => return response,
                };
                match service::list_workspaces(&db, &company_id).await {
                    Ok(workspaces) => {
                        json_response(&req.id, &serde_json::json!({ "workspaces": workspaces }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::WorkspaceGet, move |req| {
            let db = get_db.clone();
            async move {
                let session_id = match required_string_param(&req.id, req.params.as_ref(), "session_id") {
                    Ok(session_id) => session_id,
                    Err(response) => return response,
                };
                match service::get_workspace(&db, &session_id).await {
                    Ok(Some(workspace)) => {
                        json_response(&req.id, &serde_json::json!({ "workspace": workspace }))
                    }
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Workspace not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

fn parse_params<T: DeserializeOwned>(request_id: &str, params: Option<&Value>) -> Result<T, Response> {
    let value = params.cloned().unwrap_or(Value::Object(Default::default()));
    serde_json::from_value(value).map_err(|error| {
        Response::error(
            request_id,
            error_codes::INVALID_PARAMS,
            &format!("Invalid request parameters: {error}"),
        )
    })
}

fn required_string_param(request_id: &str, params: Option<&Value>, key: &str) -> Result<String, Response> {
    params
        .and_then(|params| params.get(key))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            Response::error(
                request_id,
                error_codes::INVALID_PARAMS,
                &format!("{key} is required"),
            )
        })
}

fn json_response(request_id: &str, payload: &Value) -> Response {
    Response::success(request_id, payload.clone())
}

fn board_error_response(request_id: &str, error: BoardError) -> Response {
    match error {
        BoardError::Conflict(message) => Response::error(request_id, error_codes::CONFLICT, &message),
        BoardError::InvalidInput(message) => {
            Response::error(request_id, error_codes::INVALID_PARAMS, &message)
        }
        BoardError::NotFound(message) => Response::error(request_id, error_codes::NOT_FOUND, &message),
        BoardError::Database(daemon_database::DatabaseError::NotFound(message)) => {
            Response::error(request_id, error_codes::NOT_FOUND, &message)
        }
        BoardError::Database(daemon_database::DatabaseError::InvalidData(message)) => {
            Response::error(request_id, error_codes::INVALID_PARAMS, &message)
        }
        other => Response::error(request_id, error_codes::INTERNAL_ERROR, &other.to_string()),
    }
}
