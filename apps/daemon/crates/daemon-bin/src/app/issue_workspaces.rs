use crate::app::agent_cli::{detect_agent_cli_kind, AgentCliKind};
use crate::armin_adapter::DaemonArmin;
use crate::ipc::handlers::session::{create_session_core_with_services, SessionCreateCoreError};
use crate::utils::SessionSecretCache;
use agent_session_sqlite_persist_core::{
    NewRepository, Repository, RepositoryId, SessionReader, SessionWriter,
};
use daemon_board::{service, BoardError, Issue, Workspace};
use git_ops::get_branches;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;
use std::path::Path;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum IssueWorkspaceTargetMode {
    #[default]
    Main,
    NewWorktree,
    ExistingWorktree,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct IssueExecutionWorkspaceSettings {
    #[serde(default)]
    mode: IssueWorkspaceTargetMode,
    worktree_branch: Option<String>,
    worktree_name: Option<String>,
    worktree_path: Option<String>,
}

pub async fn ensure_issue_workspace(
    db: &daemon_database::AsyncDatabase,
    armin: &DaemonArmin,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_secret_cache: &SessionSecretCache,
    issue_id: &str,
) -> Result<Workspace, BoardError> {
    let issue = service::get_issue(db, issue_id)
        .await?
        .ok_or_else(|| BoardError::NotFound("Issue not found".to_string()))?;

    if let Some(active_workspace) = service::list_workspaces(db, &issue.company_id)
        .await?
        .into_iter()
        .find(|workspace| {
            workspace.issue_id.as_deref() == Some(issue.id.as_str())
                && workspace.workspace_status == "active"
        })
    {
        return Ok(active_workspace);
    }

    let project_id = issue
        .project_id
        .clone()
        .ok_or_else(|| BoardError::InvalidInput("Issue must belong to a project".to_string()))?;
    let agent_id = issue.assignee_agent_id.clone().ok_or_else(|| {
        BoardError::InvalidInput("Issue must be assigned to an agent".to_string())
    })?;
    let agent = service::get_agent(db, &agent_id)
        .await?
        .ok_or_else(|| BoardError::NotFound("Assigned agent not found".to_string()))?;
    let project = service::get_project(db, &project_id)
        .await?
        .ok_or_else(|| BoardError::NotFound("Project not found".to_string()))?;
    let primary_workspace = project.primary_workspace.ok_or_else(|| {
        BoardError::NotFound("Project main worktree is not configured".to_string())
    })?;
    let repo_path = primary_workspace.cwd.clone().ok_or_else(|| {
        BoardError::InvalidInput("Project main worktree does not have a repo path".to_string())
    })?;
    let repository =
        ensure_workspace_repository(armin, &repo_path, primary_workspace.repo_ref.clone())?;
    let title = issue
        .identifier
        .as_ref()
        .map(|identifier| format!("{identifier}: {}", issue.title))
        .unwrap_or_else(|| issue.title.clone());
    let settings = parse_issue_workspace_settings(&issue);
    let adapter_config = merged_issue_adapter_config(&issue, &agent);

    let mut session_params = json!({
        "repository_id": repository.id.as_str(),
        "title": title,
        "agent_id": agent.id.clone(),
        "agent_name": agent.name.clone(),
        "issue_id": issue.id.clone(),
        "issue_title": issue.title.clone(),
        "provider": issue_workspace_provider(&adapter_config),
    });

    let workspace_branch = match settings.mode {
        IssueWorkspaceTargetMode::Main => primary_workspace
            .repo_ref
            .clone()
            .or(repository.default_branch.clone()),
        IssueWorkspaceTargetMode::NewWorktree => {
            let worktree_name = settings
                .worktree_name
                .clone()
                .unwrap_or_else(|| default_issue_worktree_name(&issue));
            session_params["is_worktree"] = json!(true);
            session_params["worktree_name"] = json!(worktree_name.clone());
            settings
                .worktree_branch
                .clone()
                .or_else(|| Some(format!("unbound/{worktree_name}")))
        }
        IssueWorkspaceTargetMode::ExistingWorktree => {
            let worktree_path = settings.worktree_path.clone().ok_or_else(|| {
                BoardError::InvalidInput(
                    "Issue worktree target is missing worktree_path".to_string(),
                )
            })?;
            session_params["is_worktree"] = json!(true);
            session_params["worktree_path"] = json!(worktree_path.clone());
            settings
                .worktree_branch
                .clone()
                .or_else(|| current_branch_for_path(&worktree_path))
        }
    };

    let session_data = create_session_core_with_services(
        armin,
        db_encryption_key,
        session_secret_cache,
        &session_params,
    )
    .await
    .map_err(map_session_create_error)?;

    let session_id = session_data
        .get("id")
        .and_then(|value| value.as_str())
        .ok_or_else(|| BoardError::Runtime("Session was created without an id".to_string()))?;
    let workspace_repo_path = session_data
        .get("worktree_path")
        .and_then(|value| value.as_str())
        .map(ToOwned::to_owned)
        .unwrap_or(repo_path);

    service::attach_issue_workspace_session(
        db,
        issue_id,
        session_id,
        &workspace_repo_path,
        workspace_branch,
    )
    .await
}

pub(crate) fn issue_has_attached_workspace_target(issue: &Issue) -> bool {
    if issue.workspace_session_id.is_some() {
        return true;
    }

    issue
        .execution_workspace_settings
        .as_ref()
        .and_then(Value::as_object)
        .and_then(|record| record.get("mode"))
        .and_then(Value::as_str)
        .is_some_and(|mode| matches!(mode, "main" | "new_worktree" | "existing_worktree"))
}

pub(crate) fn ensure_workspace_repository(
    armin: &DaemonArmin,
    repo_path: &str,
    default_branch: Option<String>,
) -> Result<Repository, BoardError> {
    if let Some(repository) = armin
        .get_repository_by_path(repo_path)
        .map_err(|error| BoardError::Runtime(error.to_string()))?
    {
        return Ok(repository);
    }

    let repo_name = Path::new(repo_path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("workspace")
        .to_string();

    armin
        .create_repository(NewRepository {
            id: RepositoryId::new(),
            path: repo_path.to_string(),
            name: repo_name,
            is_git_repository: true,
            sessions_path: None,
            default_branch,
            default_remote: None,
        })
        .map_err(|error| BoardError::Runtime(error.to_string()))
}

fn parse_issue_workspace_settings(issue: &Issue) -> IssueExecutionWorkspaceSettings {
    issue
        .execution_workspace_settings
        .clone()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn current_branch_for_path(path: &str) -> Option<String> {
    get_branches(Path::new(path))
        .ok()
        .and_then(|branches| branches.current)
}

fn default_issue_worktree_name(issue: &Issue) -> String {
    let source = issue
        .identifier
        .as_deref()
        .unwrap_or(issue.id.as_str())
        .to_ascii_lowercase();
    let mut sanitized = String::with_capacity(source.len());
    let mut last_was_dash = false;

    for character in source.chars() {
        if character.is_ascii_alphanumeric()
            || character == '.'
            || character == '_'
            || character == '-'
        {
            sanitized.push(character);
            last_was_dash = false;
            continue;
        }

        if !last_was_dash {
            sanitized.push('-');
            last_was_dash = true;
        }
    }

    let trimmed = sanitized.trim_matches('-');
    if trimmed.is_empty() {
        format!("issue-{}", issue.id.chars().take(12).collect::<String>())
    } else {
        trimmed.to_string()
    }
}

fn merged_issue_adapter_config(
    issue: &Issue,
    agent: &daemon_board::Agent,
) -> serde_json::Map<String, Value> {
    let mut adapter_config = agent
        .adapter_config
        .as_object()
        .cloned()
        .unwrap_or_default();
    if let Some(overrides) = issue
        .assignee_adapter_overrides
        .as_ref()
        .and_then(Value::as_object)
    {
        for (key, value) in overrides {
            adapter_config.insert(key.clone(), value.clone());
        }
    }
    adapter_config
}

fn issue_workspace_provider(adapter_config: &serde_json::Map<String, Value>) -> &'static str {
    match detect_agent_cli_kind(
        adapter_config
            .get("command")
            .and_then(|value| value.as_str()),
        adapter_config.get("model").and_then(|value| value.as_str()),
    ) {
        AgentCliKind::Claude => "claude",
        AgentCliKind::Codex => "codex",
    }
}

fn map_session_create_error(error: SessionCreateCoreError) -> BoardError {
    let (code, message, _) = error.into_response_parts();
    match code.as_str() {
        "invalid_params" => BoardError::InvalidInput(message),
        "not_found" => BoardError::NotFound(message),
        _ => BoardError::Runtime(message),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    fn test_issue(
        execution_workspace_settings: Option<Value>,
        workspace_session_id: Option<&str>,
    ) -> Issue {
        Issue {
            id: "issue-1".to_string(),
            company_id: "company-1".to_string(),
            project_id: Some("project-1".to_string()),
            goal_id: None,
            parent_id: None,
            title: "Test issue".to_string(),
            description: None,
            status: "todo".to_string(),
            priority: "medium".to_string(),
            assignee_agent_id: Some("agent-1".to_string()),
            assignee_user_id: None,
            checkout_run_id: None,
            execution_run_id: None,
            execution_agent_name_key: Some("agent-1".to_string()),
            execution_locked_at: None,
            created_by_agent_id: None,
            created_by_user_id: None,
            issue_number: Some(1),
            identifier: Some("TEST-1".to_string()),
            request_depth: 0,
            billing_code: None,
            assignee_adapter_overrides: None,
            execution_workspace_settings,
            started_at: None,
            completed_at: None,
            cancelled_at: None,
            hidden_at: None,
            workspace_session_id: workspace_session_id.map(ToOwned::to_owned),
            created_at: "2026-03-20T00:00:00Z".to_string(),
            updated_at: "2026-03-20T00:00:00Z".to_string(),
        }
    }

    #[test]
    fn attached_workspace_targets_are_detected_for_all_supported_modes() {
        assert!(issue_has_attached_workspace_target(&test_issue(
            Some(json!({ "mode": "main" })),
            None,
        )));
        assert!(issue_has_attached_workspace_target(&test_issue(
            Some(json!({ "mode": "new_worktree" })),
            None,
        )));
        assert!(issue_has_attached_workspace_target(&test_issue(
            Some(json!({
                "mode": "existing_worktree",
                "worktree_path": "/tmp/existing-worktree"
            })),
            None,
        )));
        assert!(issue_has_attached_workspace_target(&test_issue(
            None,
            Some("session-1"),
        )));
        assert!(!issue_has_attached_workspace_target(&test_issue(
            None, None
        )));
    }
}
