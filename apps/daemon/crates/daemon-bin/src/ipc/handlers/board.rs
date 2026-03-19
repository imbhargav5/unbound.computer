//! Local board IPC handlers.

use crate::app::{ensure_issue_workspace, issue_has_attached_workspace_target, DaemonState};
use daemon_board::service;
use daemon_board::{
    AddIssueAttachmentInput, AddIssueCommentInput, ApprovalDecisionInput, BoardError,
    CreateAgentHireInput, CreateAgentInput, CreateCompanyInput, CreateIssueInput,
    CreateProjectInput, Issue, IssueListFilter, UpdateAgentInput, UpdateIssueInput,
};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use serde::de::DeserializeOwned;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;
use tracing::warn;

pub async fn register(server: &IpcServer, state: DaemonState) {
    register_company_handlers(server, state.clone()).await;
    register_agent_handlers(server, state.clone()).await;
    register_agent_run_handlers(server, state.clone()).await;
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
                    Ok(companies) => {
                        json_response(&req.id, &serde_json::json!({ "companies": companies }))
                    }
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                        Ok(company_id) => company_id,
                        Err(response) => return response,
                    };
                match service::get_company(&db, &company_id).await {
                    Ok(Some(company)) => {
                        json_response(&req.id, &serde_json::json!({ "company": company }))
                    }
                    Ok(None) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Company not found")
                    }
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
                    Ok(company) => {
                        json_response(&req.id, &serde_json::json!({ "company": company }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let update_db = state.db.clone();
    server
        .register_handler(Method::CompanyUpdate, move |req| {
            let db = update_db.clone();
            async move {
                let input = match parse_params::<daemon_board::UpdateCompanyInput>(
                    &req.id,
                    req.params.as_ref(),
                ) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::update_company(&db, input).await {
                    Ok(company) => {
                        json_response(&req.id, &serde_json::json!({ "company": company }))
                    }
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
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
                let agent_id = match required_string_param(&req.id, req.params.as_ref(), "agent_id")
                {
                    Ok(agent_id) => agent_id,
                    Err(response) => return response,
                };
                match service::get_agent(&db, &agent_id).await {
                    Ok(Some(agent)) => {
                        json_response(&req.id, &serde_json::json!({ "agent": agent }))
                    }
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

    let update_db = state.db.clone();
    server
        .register_handler(Method::AgentUpdate, move |req| {
            let db = update_db.clone();
            async move {
                let input = match parse_params::<UpdateAgentInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::update_agent(&db, input).await {
                    Ok(agent) => json_response(&req.id, &serde_json::json!({ "agent": agent })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let hire_db = state.db.clone();
    let hire_paths = state.paths.clone();
    server
        .register_handler(Method::AgentHireCreate, move |req| {
            let db = hire_db.clone();
            let paths = hire_paths.clone();
            async move {
                let input = match parse_params::<CreateAgentHireInput>(&req.id, req.params.as_ref())
                {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_agent_hire(&db, &paths, input).await {
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
                        Ok(company_id) => company_id,
                        Err(response) => return response,
                    };
                match service::list_projects(&db, &company_id).await {
                    Ok(projects) => {
                        json_response(&req.id, &serde_json::json!({ "projects": projects }))
                    }
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
                let project_id =
                    match required_string_param(&req.id, req.params.as_ref(), "project_id") {
                        Ok(project_id) => project_id,
                        Err(response) => return response,
                    };
                match service::get_project(&db, &project_id).await {
                    Ok(Some(project)) => {
                        json_response(&req.id, &serde_json::json!({ "project": project }))
                    }
                    Ok(None) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Project not found")
                    }
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
                    Ok(project) => {
                        json_response(&req.id, &serde_json::json!({ "project": project }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let delete_db = state.db.clone();
    server
        .register_handler(Method::ProjectDelete, move |req| {
            let db = delete_db.clone();
            async move {
                let project_id =
                    match required_string_param(&req.id, req.params.as_ref(), "project_id") {
                        Ok(project_id) => project_id,
                        Err(response) => return response,
                    };
                match service::delete_project(&db, &project_id).await {
                    Ok(project) => {
                        json_response(&req.id, &serde_json::json!({ "project": project }))
                    }
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
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id")
                {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::get_issue(&db, &issue_id).await {
                    Ok(Some(issue)) => {
                        json_response(&req.id, &serde_json::json!({ "issue": issue }))
                    }
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Issue not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let create_db = state.db.clone();
    let create_state = state.clone();
    let create_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::IssueCreate, move |req| {
            let db = create_db.clone();
            let state = create_state.clone();
            let runs = create_runs.clone();
            async move {
                let input = match parse_params::<CreateIssueInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::create_issue(&db, input).await {
                    Ok(issue) => {
                        let issue = prepare_attached_issue_workspace_if_needed(&state, issue).await;
                        if should_wake_assignee_for_todo_issue(&issue) {
                            maybe_enqueue_issue_run(
                                runs.as_ref(),
                                &issue,
                                "assignment",
                                Some("system"),
                                Some("issue_assigned"),
                            )
                            .await;
                        }
                        json_response(&req.id, &serde_json::json!({ "issue": issue }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let update_db = state.db.clone();
    let update_state = state.clone();
    let update_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::IssueUpdate, move |req| {
            let db = update_db.clone();
            let state = update_state.clone();
            let runs = update_runs.clone();
            async move {
                let input = match parse_params::<UpdateIssueInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };

                let previous = match service::get_issue(&db, &input.issue_id).await {
                    Ok(Some(issue)) => issue,
                    Ok(None) => {
                        return Response::error(&req.id, error_codes::NOT_FOUND, "Issue not found")
                    }
                    Err(error) => return board_error_response(&req.id, error),
                };

                match service::update_issue(&db, input).await {
                    Ok(issue) => {
                        let issue = prepare_attached_issue_workspace_if_needed(&state, issue).await;
                        if previous.assignee_agent_id != issue.assignee_agent_id
                            && should_wake_assignee_for_todo_issue(&issue)
                        {
                            maybe_enqueue_issue_run(
                                runs.as_ref(),
                                &issue,
                                "assignment",
                                Some("system"),
                                Some("issue_assigned"),
                            )
                            .await;
                        }
                        if issue_became_todo(&previous, &issue) {
                            maybe_enqueue_issue_run(
                                runs.as_ref(),
                                &issue,
                                "assignment",
                                Some("system"),
                                Some("issue_status_changed"),
                            )
                            .await;
                        }
                        json_response(&req.id, &serde_json::json!({ "issue": issue }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let comment_list_db = state.db.clone();
    let attachment_list_db = state.db.clone();
    let attachment_list_paths = state.paths.clone();
    server
        .register_handler(Method::IssueCommentList, move |req| {
            let db = comment_list_db.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id")
                {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::list_issue_comments(&db, &issue_id).await {
                    Ok(comments) => {
                        json_response(&req.id, &serde_json::json!({ "comments": comments }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    server
        .register_handler(Method::IssueAttachmentList, move |req| {
            let db = attachment_list_db.clone();
            let paths = attachment_list_paths.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id")
                {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match service::list_issue_attachments(&db, &paths, &issue_id).await {
                    Ok(attachments) => {
                        json_response(&req.id, &serde_json::json!({ "attachments": attachments }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let attachment_add_db = state.db.clone();
    let attachment_add_paths = state.paths.clone();
    server
        .register_handler(Method::IssueAttachmentAdd, move |req| {
            let db = attachment_add_db.clone();
            let paths = attachment_add_paths.clone();
            async move {
                let input =
                    match parse_params::<AddIssueAttachmentInput>(&req.id, req.params.as_ref()) {
                        Ok(input) => input,
                        Err(response) => return response,
                    };
                match service::add_issue_attachment(&db, &paths, input).await {
                    Ok(attachment) => {
                        json_response(&req.id, &serde_json::json!({ "attachment": attachment }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let run_list_db = state.db.clone();
    server
        .register_handler(Method::IssueRunList, move |req| {
            let db = run_list_db.clone();
            async move {
                let input = match parse_params::<IssueRunListInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::list_issue_runs(&db, &input.issue_id, input.limit).await {
                    Ok(runs) => json_response(&req.id, &serde_json::json!({ "runs": runs })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let comment_add_db = state.db.clone();
    let comment_add_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::IssueCommentAdd, move |req| {
            let db = comment_add_db.clone();
            let runs = comment_add_runs.clone();
            async move {
                let input = match parse_params::<AddIssueCommentInput>(&req.id, req.params.as_ref())
                {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                let issue_id = input.issue_id.clone();
                let comment_body = input.body.clone();
                let author_agent_id = input.author_agent_id.clone();
                let selected_target_agent_id = input.target_agent_id.clone();
                match service::add_issue_comment(&db, input).await {
                    Ok(comment) => {
                        if let Ok(Some(issue)) = service::get_issue(&db, &issue_id).await {
                            let was_closed = matches!(issue.status.as_str(), "done" | "cancelled");
                            let active_issue = if was_closed {
                                match service::update_issue(
                                    &db,
                                    UpdateIssueInput {
                                        issue_id: issue.id.clone(),
                                        status: Some("todo".to_string()),
                                        ..UpdateIssueInput::default()
                                    },
                                )
                                .await
                                {
                                    Ok(reopened) => reopened,
                                    Err(_) => issue.clone(),
                                }
                            } else {
                                issue.clone()
                            };

                            let mut woke_agent_ids = HashSet::new();
                            let primary_agent_id = comment
                                .target_agent_id
                                .clone()
                                .or(selected_target_agent_id)
                                .or(active_issue.assignee_agent_id.clone());
                            if let Some(agent_id) = primary_agent_id {
                                if author_agent_id.as_deref() != Some(agent_id.as_str()) {
                                    let wake_reason = if was_closed {
                                        "issue_reopened_via_comment"
                                    } else {
                                        "issue_commented"
                                    };
                                    enqueue_issue_comment_run(
                                        runs.as_ref(),
                                        &active_issue,
                                        &agent_id,
                                        &comment.id,
                                        wake_reason,
                                    )
                                    .await;
                                    woke_agent_ids.insert(agent_id);
                                }
                            }

                            if let Ok(agents) =
                                service::list_agents(&db, &active_issue.company_id).await
                            {
                                let mentioned_agent_ids =
                                    extract_mentioned_agent_ids(&comment_body, &agents);
                                for agent_id in mentioned_agent_ids {
                                    if !woke_agent_ids.insert(agent_id.clone())
                                        || author_agent_id.as_deref() == Some(agent_id.as_str())
                                    {
                                        continue;
                                    }
                                    enqueue_issue_comment_run(
                                        runs.as_ref(),
                                        &active_issue,
                                        &agent_id,
                                        &comment.id,
                                        "issue_comment_mentioned",
                                    )
                                    .await;
                                }
                            }
                        }
                        json_response(&req.id, &serde_json::json!({ "comment": comment }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let checkout_runs = state.agent_run_coordinator.clone();
    let checkout_state = state.clone();
    server
        .register_handler(Method::IssueCheckout, move |req| {
            let state = checkout_state.clone();
            let runs = checkout_runs.clone();
            async move {
                let issue_id = match required_string_param(&req.id, req.params.as_ref(), "issue_id")
                {
                    Ok(issue_id) => issue_id,
                    Err(response) => return response,
                };
                match ensure_issue_workspace(
                    &state.db,
                    state.armin.as_ref(),
                    &state.db_encryption_key,
                    &state.session_secret_cache,
                    &issue_id,
                )
                .await
                {
                    Ok(workspace) => {
                        if let Ok(Some(issue)) = service::get_issue(&state.db, &issue_id).await {
                            maybe_enqueue_issue_run(
                                runs.as_ref(),
                                &issue,
                                "assignment",
                                Some("system"),
                                Some("issue_checked_out"),
                            )
                            .await;
                        }
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
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
                let approval_id =
                    match required_string_param(&req.id, req.params.as_ref(), "approval_id") {
                        Ok(approval_id) => approval_id,
                        Err(response) => return response,
                    };
                match service::get_approval(&db, &approval_id).await {
                    Ok(Some(approval)) => {
                        json_response(&req.id, &serde_json::json!({ "approval": approval }))
                    }
                    Ok(None) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Approval not found")
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let approve_db = state.db.clone();
    let approve_paths = state.paths.clone();
    let approve_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::ApprovalApprove, move |req| {
            let db = approve_db.clone();
            let paths = approve_paths.clone();
            let runs = approve_runs.clone();
            async move {
                let input =
                    match parse_params::<ApprovalDecisionInput>(&req.id, req.params.as_ref()) {
                        Ok(input) => input,
                        Err(response) => return response,
                    };
                match service::approve_approval(&db, &paths, input).await {
                    Ok(approval) => {
                        if let Some(agent_id) = approval.requested_by_agent_id.clone() {
                            let _ = runs
                                .enqueue_run(crate::app::AgentRunEnqueueRequest {
                                    agent_id,
                                    company_id: Some(approval.company_id.clone()),
                                    invocation_source: "automation".to_string(),
                                    trigger_detail: Some("system".to_string()),
                                    wake_reason: Some("approval_approved".to_string()),
                                    payload: Some(serde_json::json!({
                                        "approval_id": approval.id,
                                    })),
                                    prompt: None,
                                    requested_by_actor_type: Some("system".to_string()),
                                    requested_by_actor_id: Some(approval.id.clone()),
                                })
                                .await;
                        }
                        json_response(&req.id, &serde_json::json!({ "approval": approval }))
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

async fn register_agent_run_handlers(server: &IpcServer, state: DaemonState) {
    let list_db = state.db.clone();
    server
        .register_handler(Method::AgentRunList, move |req| {
            let db = list_db.clone();
            async move {
                let input = match parse_params::<AgentRunListInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::list_agent_runs(&db, &input.agent_id, input.limit).await {
                    Ok(runs) => json_response(&req.id, &serde_json::json!({ "runs": runs })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let get_db = state.db.clone();
    server
        .register_handler(Method::AgentRunGet, move |req| {
            let db = get_db.clone();
            async move {
                let run_id = match required_string_param(&req.id, req.params.as_ref(), "run_id") {
                    Ok(run_id) => run_id,
                    Err(response) => return response,
                };
                match service::get_agent_run(&db, &run_id).await {
                    Ok(Some(run)) => json_response(&req.id, &serde_json::json!({ "run": run })),
                    Ok(None) => Response::error(&req.id, error_codes::NOT_FOUND, "Run not found"),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let events_db = state.db.clone();
    server
        .register_handler(Method::AgentRunEvents, move |req| {
            let db = events_db.clone();
            async move {
                let input = match parse_params::<AgentRunEventsInput>(&req.id, req.params.as_ref())
                {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match service::list_agent_run_events(
                    &db,
                    &input.run_id,
                    input.after_seq,
                    input.limit,
                )
                .await
                {
                    Ok(events) => json_response(&req.id, &serde_json::json!({ "events": events })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let log_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::AgentRunLog, move |req| {
            let runs = log_runs.clone();
            async move {
                let input = match parse_params::<AgentRunLogInput>(&req.id, req.params.as_ref()) {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match runs
                    .read_log_chunk(
                        &input.run_id,
                        input.offset.unwrap_or(0),
                        input.limit_bytes.unwrap_or(16_384),
                    )
                    .await
                {
                    Ok(chunk) => json_response(
                        &req.id,
                        &serde_json::json!({
                            "content": chunk.content,
                            "next_offset": chunk.next_offset,
                            "done": chunk.done,
                        }),
                    ),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let invoke_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::AgentRunInvoke, move |req| {
            let runs = invoke_runs.clone();
            async move {
                let input = match parse_params::<InvokeAgentRunInput>(&req.id, req.params.as_ref())
                {
                    Ok(input) => input,
                    Err(response) => return response,
                };
                match runs
                    .enqueue_manual_run(&input.agent_id, input.issue_id, input.prompt)
                    .await
                {
                    Ok(run) => json_response(&req.id, &serde_json::json!({ "run": run })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let cancel_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::AgentRunCancel, move |req| {
            let runs = cancel_runs.clone();
            async move {
                let run_id = match required_string_param(&req.id, req.params.as_ref(), "run_id") {
                    Ok(run_id) => run_id,
                    Err(response) => return response,
                };
                match runs.cancel_run(&run_id).await {
                    Ok(run) => json_response(&req.id, &serde_json::json!({ "run": run })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let retry_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::AgentRunRetry, move |req| {
            let runs = retry_runs.clone();
            async move {
                let run_id = match required_string_param(&req.id, req.params.as_ref(), "run_id") {
                    Ok(run_id) => run_id,
                    Err(response) => return response,
                };
                match runs.retry_run(&run_id).await {
                    Ok(run) => json_response(&req.id, &serde_json::json!({ "run": run })),
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;

    let resume_runs = state.agent_run_coordinator.clone();
    server
        .register_handler(Method::AgentRunResume, move |req| {
            let runs = resume_runs.clone();
            async move {
                let run_id = match required_string_param(&req.id, req.params.as_ref(), "run_id") {
                    Ok(run_id) => run_id,
                    Err(response) => return response,
                };
                match runs.resume_run(&run_id).await {
                    Ok(run) => json_response(&req.id, &serde_json::json!({ "run": run })),
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
                let company_id =
                    match required_string_param(&req.id, req.params.as_ref(), "company_id") {
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
                let session_id =
                    match required_string_param(&req.id, req.params.as_ref(), "session_id") {
                        Ok(session_id) => session_id,
                        Err(response) => return response,
                    };
                match service::get_workspace(&db, &session_id).await {
                    Ok(Some(workspace)) => {
                        json_response(&req.id, &serde_json::json!({ "workspace": workspace }))
                    }
                    Ok(None) => {
                        Response::error(&req.id, error_codes::NOT_FOUND, "Workspace not found")
                    }
                    Err(error) => board_error_response(&req.id, error),
                }
            }
        })
        .await;
}

fn parse_params<T: DeserializeOwned>(
    request_id: &str,
    params: Option<&Value>,
) -> Result<T, Response> {
    let value = params.cloned().unwrap_or(Value::Object(Default::default()));
    serde_json::from_value(value).map_err(|error| {
        Response::error(
            request_id,
            error_codes::INVALID_PARAMS,
            &format!("Invalid request parameters: {error}"),
        )
    })
}

fn required_string_param(
    request_id: &str,
    params: Option<&Value>,
    key: &str,
) -> Result<String, Response> {
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
        BoardError::Conflict(message) => {
            Response::error(request_id, error_codes::CONFLICT, &message)
        }
        BoardError::InvalidInput(message) => {
            Response::error(request_id, error_codes::INVALID_PARAMS, &message)
        }
        BoardError::NotFound(message) => {
            Response::error(request_id, error_codes::NOT_FOUND, &message)
        }
        BoardError::Database(daemon_database::DatabaseError::NotFound(message)) => {
            Response::error(request_id, error_codes::NOT_FOUND, &message)
        }
        BoardError::Database(daemon_database::DatabaseError::InvalidData(message)) => {
            Response::error(request_id, error_codes::INVALID_PARAMS, &message)
        }
        other => Response::error(request_id, error_codes::INTERNAL_ERROR, &other.to_string()),
    }
}

fn is_todo_status(status: &str) -> bool {
    status.trim().eq_ignore_ascii_case("todo")
}

fn should_wake_assignee_for_todo_issue(issue: &Issue) -> bool {
    issue
        .assignee_agent_id
        .as_deref()
        .map(|agent_id| !agent_id.trim().is_empty())
        .unwrap_or(false)
        && is_todo_status(&issue.status)
}

fn issue_became_todo(previous: &Issue, next: &Issue) -> bool {
    !is_todo_status(&previous.status) && should_wake_assignee_for_todo_issue(next)
}

async fn enqueue_issue_comment_run(
    coordinator: &crate::app::AgentRunCoordinator,
    issue: &Issue,
    agent_id: &str,
    comment_id: &str,
    wake_reason: &str,
) {
    if let Err(error) = coordinator
        .enqueue_run(crate::app::AgentRunEnqueueRequest {
            agent_id: agent_id.to_string(),
            company_id: Some(issue.company_id.clone()),
            invocation_source: "automation".to_string(),
            trigger_detail: Some("system".to_string()),
            wake_reason: Some(wake_reason.to_string()),
            payload: Some(serde_json::json!({
                "issue_id": issue.id,
                "comment_id": comment_id,
            })),
            prompt: None,
            requested_by_actor_type: Some("system".to_string()),
            requested_by_actor_id: Some(comment_id.to_string()),
        })
        .await
    {
        warn!(
            error = %error,
            issue_id = %issue.id,
            comment_id,
            target_agent_id = agent_id,
            "Failed to enqueue issue comment run"
        );
    }
}

async fn prepare_attached_issue_workspace_if_needed(state: &DaemonState, issue: Issue) -> Issue {
    if !issue_has_attached_workspace_target(&issue) {
        return issue;
    }

    if let Err(error) = ensure_issue_workspace(
        &state.db,
        state.armin.as_ref(),
        &state.db_encryption_key,
        &state.session_secret_cache,
        &issue.id,
    )
    .await
    {
        warn!(
            error = %error,
            issue_id = %issue.id,
            "Failed to prepare attached issue workspace"
        );
        return issue;
    }

    match service::get_issue(&state.db, &issue.id).await {
        Ok(Some(updated_issue)) => updated_issue,
        Ok(None) => issue,
        Err(error) => {
            warn!(
                error = %error,
                issue_id = %issue.id,
                "Failed to reload issue after preparing attached workspace"
            );
            issue
        }
    }
}

async fn maybe_enqueue_issue_run(
    coordinator: &crate::app::AgentRunCoordinator,
    issue: &Issue,
    invocation_source: &str,
    trigger_detail: Option<&str>,
    wake_reason: Option<&str>,
) {
    let Some(agent_id) = issue.assignee_agent_id.clone() else {
        return;
    };

    if let Err(error) = coordinator
        .enqueue_run(crate::app::AgentRunEnqueueRequest {
            agent_id,
            company_id: Some(issue.company_id.clone()),
            invocation_source: invocation_source.to_string(),
            trigger_detail: trigger_detail.map(ToOwned::to_owned),
            wake_reason: wake_reason.map(ToOwned::to_owned),
            payload: Some(serde_json::json!({ "issue_id": issue.id })),
            prompt: None,
            requested_by_actor_type: Some("system".to_string()),
            requested_by_actor_id: Some(issue.id.clone()),
        })
        .await
    {
        warn!(error = %error, issue_id = %issue.id, "Failed to enqueue issue run");
    }
}

fn extract_mentioned_agent_ids(comment_body: &str, agents: &[daemon_board::Agent]) -> Vec<String> {
    let mut mentioned = HashSet::new();
    let lowered = comment_body.to_lowercase();
    for agent in agents {
        let slug_token = format!("@{}", agent.slug.to_lowercase());
        if lowered.contains(&slug_token) {
            mentioned.insert(agent.id.clone());
            continue;
        }

        let name_token = format!("@{}", agent.name.to_lowercase().replace(' ', ""));
        if lowered.contains(&name_token) {
            mentioned.insert(agent.id.clone());
        }
    }
    mentioned.into_iter().collect()
}

#[derive(Debug, Deserialize)]
struct AgentRunListInput {
    agent_id: String,
    limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct IssueRunListInput {
    issue_id: String,
    limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct AgentRunEventsInput {
    run_id: String,
    after_seq: Option<i64>,
    limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct AgentRunLogInput {
    run_id: String,
    offset: Option<u64>,
    limit_bytes: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct InvokeAgentRunInput {
    agent_id: String,
    issue_id: Option<String>,
    prompt: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_issue(status: &str, assignee_agent_id: Option<&str>) -> Issue {
        Issue {
            id: "issue-1".to_string(),
            company_id: "company-1".to_string(),
            project_id: None,
            goal_id: None,
            parent_id: None,
            title: "Test issue".to_string(),
            description: None,
            status: status.to_string(),
            priority: "medium".to_string(),
            assignee_agent_id: assignee_agent_id.map(ToOwned::to_owned),
            assignee_user_id: None,
            checkout_run_id: None,
            execution_run_id: None,
            execution_agent_name_key: None,
            execution_locked_at: None,
            created_by_agent_id: None,
            created_by_user_id: None,
            issue_number: Some(1),
            identifier: Some("TEST-1".to_string()),
            request_depth: 0,
            billing_code: None,
            assignee_adapter_overrides: None,
            execution_workspace_settings: Some(json!({ "mode": "main" })),
            started_at: None,
            completed_at: None,
            cancelled_at: None,
            hidden_at: None,
            workspace_session_id: None,
            created_at: "2026-03-18T00:00:00Z".to_string(),
            updated_at: "2026-03-18T00:00:00Z".to_string(),
        }
    }

    #[test]
    fn only_assigned_todo_issues_wake_immediately() {
        assert!(should_wake_assignee_for_todo_issue(&test_issue(
            "todo",
            Some("agent-1")
        )));
        assert!(!should_wake_assignee_for_todo_issue(&test_issue(
            "backlog",
            Some("agent-1")
        )));
        assert!(!should_wake_assignee_for_todo_issue(&test_issue(
            "todo", None
        )));
    }

    #[test]
    fn issue_became_todo_detects_assignment_ready_transition() {
        assert!(issue_became_todo(
            &test_issue("backlog", Some("agent-1")),
            &test_issue("todo", Some("agent-1"))
        ));
        assert!(!issue_became_todo(
            &test_issue("todo", Some("agent-1")),
            &test_issue("todo", Some("agent-1"))
        ));
    }
}
