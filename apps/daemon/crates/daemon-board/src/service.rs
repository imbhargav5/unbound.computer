use crate::error::{BoardError, BoardResult};
use crate::models::{
    AddIssueCommentInput, Agent, Approval, ApprovalDecisionInput, Company, CreateAgentInput,
    CreateCompanyInput, CreateIssueInput, CreateProjectInput, Goal, Issue, IssueComment,
    IssueListFilter, Project, ProjectWorkspace, Workspace,
};
use agent_session_sqlite_persist_core::{NewSession, RepositoryId, SessionWriter};
use chrono::Utc;
use daemon_config_and_utils::Paths;
use daemon_database::{queries, AsyncDatabase, DatabaseError, DatabaseResult, NewRepository};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use uuid::Uuid;

const LOCAL_BOARD_USER_ID: &str = "local-board";
const LOCAL_BOARD_EMAIL: &str = "local-board@unbound.local";
const LOCAL_BOARD_NAME: &str = "Unbound Local Board";
const DEFAULT_COMPANY_PERMISSIONS: [&str; 6] = [
    "agents:create",
    "users:invite",
    "users:manage_permissions",
    "tasks:assign",
    "tasks:assign_scope",
    "joins:approve",
];

pub async fn list_companies(db: &AsyncDatabase) -> BoardResult<Vec<Company>> {
    Ok(db
        .call_with_operation("board.company.list", move |conn| list_companies_sync(conn))
        .await?)
}

pub async fn get_company(db: &AsyncDatabase, company_id: &str) -> BoardResult<Option<Company>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.company.get", move |conn| {
            get_company_sync(conn, &company_id)
        })
        .await?)
}

pub async fn create_company(
    db: &AsyncDatabase,
    paths: &Paths,
    input: CreateCompanyInput,
) -> BoardResult<Company> {
    let paths = paths.clone();
    let db_paths = paths.clone();
    let name = require_name(&input.name, "company name")?;
    let description = normalize_optional_string(input.description);
    let budget = input.budget_monthly_cents.unwrap_or(0).max(0);
    let require_board_approval = input.require_board_approval_for_new_agents.unwrap_or(true);
    let brand_color = normalize_optional_string(input.brand_color);
    let now = now_rfc3339();

    let creation = db
        .call_with_operation("board.company.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            ensure_local_board_user(&tx, &now)?;

            let company_id = Uuid::new_v4().to_string();
            let ceo_agent_id = Uuid::new_v4().to_string();
            let issue_prefix = unique_issue_prefix(&tx, &name)?;
            let agent_slug = unique_agent_slug(&tx, &company_id, "ceo-agent")?;
            let company_name = name.clone();
            let home_path = db_paths
                .agent_home_dir(&company_id, &agent_slug)
                .to_string_lossy()
                .to_string();
            let instructions_path = db_paths
                .agent_home_dir(&company_id, &agent_slug)
                .join("AGENTS.md")
                .to_string_lossy()
                .to_string();

            tx.execute(
                "INSERT INTO companies (
                    id, name, description, status, issue_prefix, issue_counter,
                    budget_monthly_cents, spent_monthly_cents,
                    require_board_approval_for_new_agents, brand_color, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'active', ?4, 0, ?5, 0, ?6, ?7, ?8, ?8)",
                params![
                    company_id,
                    name,
                    description,
                    issue_prefix,
                    budget,
                    require_board_approval,
                    brand_color,
                    now,
                ],
            )?;

            tx.execute(
                "INSERT INTO agents (
                    id, company_id, name, slug, role, title, icon, status,
                    adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                    spent_monthly_cents, permissions, home_path, instructions_path,
                    created_at, updated_at
                 ) VALUES (
                    ?1, ?2, 'CEO Agent', ?3, 'ceo', 'Chief Executive Officer', 'crown', 'idle',
                    'process', '{}', '{}', 0, 0, ?4, ?5, ?6, ?7, ?7
                 )",
                params![
                    ceo_agent_id,
                    company_id,
                    agent_slug,
                    json!({ "canCreateAgents": true }).to_string(),
                    home_path,
                    instructions_path,
                    now,
                ],
            )?;

            tx.execute(
                "INSERT INTO company_memberships (
                    id, company_id, principal_type, principal_id, status, membership_role, created_at, updated_at
                 ) VALUES (?1, ?2, 'user', ?3, 'active', 'owner', ?4, ?4)",
                params![
                    Uuid::new_v4().to_string(),
                    company_id,
                    LOCAL_BOARD_USER_ID,
                    now,
                ],
            )?;

            for permission_key in DEFAULT_COMPANY_PERMISSIONS {
                tx.execute(
                    "INSERT OR IGNORE INTO principal_permission_grants (
                        id, company_id, principal_type, principal_id, permission_key, scope,
                        granted_by_user_id, created_at, updated_at
                     ) VALUES (?1, ?2, 'user', ?3, ?4, NULL, ?3, ?5, ?5)",
                    params![
                        Uuid::new_v4().to_string(),
                        company_id,
                        LOCAL_BOARD_USER_ID,
                        permission_key,
                        now,
                    ],
                )?;
            }

            insert_activity_sync(
                &tx,
                &company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "company.created",
                "company",
                &company_id,
                None,
                Some(json!({ "name": company_name, "issue_prefix": issue_prefix })),
                &now,
            )?;
            insert_activity_sync(
                &tx,
                &company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "agent.created",
                "agent",
                &ceo_agent_id,
                Some(&ceo_agent_id),
                Some(json!({ "role": "ceo", "slug": agent_slug })),
                &now,
            )?;

            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company missing after insert".to_string()))?;

            tx.commit()?;
            Ok((company, ceo_agent_id, agent_slug))
        })
        .await?;

    if let Err(error) = scaffold_agent_home(
        &paths,
        &creation.0.id,
        "CEO Agent",
        &creation.2,
        &creation.0.name,
        "ceo",
    ) {
        let company_id = creation.0.id.clone();
        db.call_with_operation(
            "board.company.rollback_after_scaffold_failure",
            move |conn| {
                conn.execute("DELETE FROM companies WHERE id = ?1", params![company_id])?;
                Ok(())
            },
        )
        .await?;
        let _ = fs::remove_dir_all(paths.company_root(&creation.0.id));
        return Err(error);
    }

    Ok(creation.0)
}

pub async fn list_agents(db: &AsyncDatabase, company_id: &str) -> BoardResult<Vec<Agent>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.agent.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, name, slug, role, title, icon, status, reports_to, capabilities,
                    adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                    spent_monthly_cents, permissions, last_heartbeat_at, metadata,
                    home_path, instructions_path, created_at, updated_at
                 FROM agents
                 WHERE company_id = ?1
                 ORDER BY created_at ASC",
            )?;
            let rows = stmt
                .query_map(params![company_id], row_to_agent)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .await?)
}

pub async fn get_agent(db: &AsyncDatabase, agent_id: &str) -> BoardResult<Option<Agent>> {
    let agent_id = agent_id.to_string();
    Ok(db
        .call_with_operation("board.agent.get", move |conn| {
            conn.query_row(
                "SELECT
                    id, company_id, name, slug, role, title, icon, status, reports_to, capabilities,
                    adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                    spent_monthly_cents, permissions, last_heartbeat_at, metadata,
                    home_path, instructions_path, created_at, updated_at
                 FROM agents
                 WHERE id = ?1",
                params![agent_id],
                row_to_agent,
            )
            .optional()
            .map_err(Into::into)
        })
        .await?)
}

pub async fn create_agent(
    db: &AsyncDatabase,
    paths: &Paths,
    input: CreateAgentInput,
) -> BoardResult<Agent> {
    let paths = paths.clone();
    let db_paths = paths.clone();
    let company_id = require_name(&input.company_id, "company_id")?;
    let name = require_name(&input.name, "agent name")?;
    let role = input.role.unwrap_or_else(|| "general".to_string());
    let status_requires_approval = get_company(db, &company_id)
        .await?
        .map(|company| company.require_board_approval_for_new_agents)
        .unwrap_or(true);
    let desired_status = if role == "ceo" {
        "idle".to_string()
    } else if status_requires_approval {
        "pending_approval".to_string()
    } else {
        "idle".to_string()
    };
    let now = now_rfc3339();
    let description_title = normalize_optional_string(input.title);
    let icon = normalize_optional_string(input.icon);
    let reports_to = normalize_optional_string(input.reports_to);
    let capabilities = normalize_optional_string(input.capabilities);
    let adapter_type = input.adapter_type.unwrap_or_else(|| "process".to_string());
    let adapter_config = input.adapter_config.unwrap_or_else(|| json!({}));
    let runtime_config = input.runtime_config.unwrap_or_else(|| json!({}));
    let budget = input.budget_monthly_cents.unwrap_or(0).max(0);
    let permissions = input.permissions.unwrap_or_else(|| json!({}));
    let metadata = input.metadata;

    let agent = db
        .call_with_operation("board.agent.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;
            let slug = unique_agent_slug(&tx, &company_id, &name)?;
            let agent_id = Uuid::new_v4().to_string();
            let reports_to = reports_to.or_else(|| find_company_ceo_sync(&tx, &company_id).ok().flatten());
            let home_path = db_paths
                .agent_home_dir(&company_id, &slug)
                .to_string_lossy()
                .to_string();
            let instructions_path = db_paths
                .agent_home_dir(&company_id, &slug)
                .join("AGENTS.md")
                .to_string_lossy()
                .to_string();

            tx.execute(
                "INSERT INTO agents (
                    id, company_id, name, slug, role, title, icon, status, reports_to, capabilities,
                    adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                    spent_monthly_cents, permissions, metadata, home_path, instructions_path,
                    created_at, updated_at
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,
                    ?11, ?12, ?13, ?14, 0, ?15, ?16, ?17, ?18, ?19, ?19
                 )",
                params![
                    agent_id,
                    company_id,
                    name,
                    slug,
                    role,
                    description_title,
                    icon,
                    desired_status,
                    reports_to,
                    capabilities,
                    adapter_type,
                    adapter_config.to_string(),
                    runtime_config.to_string(),
                    budget,
                    permissions.to_string(),
                    metadata.as_ref().map(Value::to_string),
                    home_path,
                    instructions_path,
                    now,
                ],
            )?;

            insert_activity_sync(
                &tx,
                &company.id,
                "system",
                LOCAL_BOARD_USER_ID,
                "agent.created",
                "agent",
                &agent_id,
                Some(&agent_id),
                Some(json!({
                    "name": name,
                    "role": role,
                    "status": desired_status,
                    "slug": slug,
                })),
                &now,
            )?;

            if desired_status == "pending_approval" {
                let approval_id = Uuid::new_v4().to_string();
                tx.execute(
                    "INSERT INTO approvals (
                        id, company_id, type, requested_by_agent_id, requested_by_user_id, status,
                        payload, created_at, updated_at
                     ) VALUES (?1, ?2, 'hire_agent', NULL, ?3, 'pending', ?4, ?5, ?5)",
                    params![
                        approval_id,
                        company_id,
                        LOCAL_BOARD_USER_ID,
                        json!({
                            "agent_id": agent_id,
                            "agent_name": name,
                            "agent_role": role,
                            "agent_slug": slug,
                        })
                        .to_string(),
                        now,
                    ],
                )?;

                insert_activity_sync(
                    &tx,
                    &company.id,
                    "system",
                    LOCAL_BOARD_USER_ID,
                    "approval.requested",
                    "approval",
                    &approval_id,
                    Some(&agent_id),
                    Some(json!({ "type": "hire_agent", "agent_id": agent_id })),
                    &now,
                )?;
            }

            let agent = tx
                .query_row(
                    "SELECT
                        id, company_id, name, slug, role, title, icon, status, reports_to, capabilities,
                        adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                        spent_monthly_cents, permissions, last_heartbeat_at, metadata,
                        home_path, instructions_path, created_at, updated_at
                     FROM agents
                     WHERE id = ?1",
                    params![agent_id],
                    row_to_agent,
                )
                .optional()?
                .ok_or_else(|| DatabaseError::NotFound("Agent missing after insert".to_string()))?;

            tx.commit()?;
            Ok(agent)
        })
        .await?;

    let company_name = get_company(db, &agent.company_id)
        .await?
        .map(|company| company.name)
        .unwrap_or_default();
    if let Err(error) = scaffold_agent_home(
        &paths,
        &agent.company_id,
        &agent.name,
        &agent.slug,
        &company_name,
        &agent.role,
    ) {
        let agent_id = agent.id.clone();
        db.call_with_operation("board.agent.rollback_after_scaffold_failure", move |conn| {
            conn.execute("DELETE FROM agents WHERE id = ?1", params![agent_id])?;
            Ok(())
        })
        .await?;
        let _ = fs::remove_dir_all(paths.agent_home_dir(&agent.company_id, &agent.slug));
        return Err(error);
    }

    Ok(agent)
}

pub async fn list_goals(db: &AsyncDatabase, company_id: &str) -> BoardResult<Vec<Goal>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.goal.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, title, description, level, status, parent_id,
                    owner_agent_id, created_at, updated_at
                 FROM goals
                 WHERE company_id = ?1
                 ORDER BY created_at DESC",
            )?;
            let rows = stmt
                .query_map(params![company_id], row_to_goal)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .await?)
}

pub async fn list_projects(db: &AsyncDatabase, company_id: &str) -> BoardResult<Vec<Project>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.project.list", move |conn| {
            list_projects_sync(conn, &company_id)
        })
        .await?)
}

pub async fn get_project(db: &AsyncDatabase, project_id: &str) -> BoardResult<Option<Project>> {
    let project_id = project_id.to_string();
    Ok(db
        .call_with_operation("board.project.get", move |conn| {
            get_project_sync(conn, &project_id)
        })
        .await?)
}

pub async fn create_project(db: &AsyncDatabase, input: CreateProjectInput) -> BoardResult<Project> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let name = require_name(&input.name, "project name")?;
    let description = normalize_optional_string(input.description);
    let status = input.status.unwrap_or_else(|| "backlog".to_string());
    let lead_agent_id = normalize_optional_string(input.lead_agent_id);
    let target_date = normalize_optional_string(input.target_date);
    let color = normalize_optional_string(input.color);
    let workspace_policy = input.execution_workspace_policy;
    let repo_path = normalize_optional_string(input.repo_path);
    let repo_url = normalize_optional_string(input.repo_url);
    let repo_ref = normalize_optional_string(input.repo_ref);
    let goal_id = normalize_optional_string(input.goal_id);
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.project.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let project_id = Uuid::new_v4().to_string();
            tx.execute(
                "INSERT INTO projects (
                    id, company_id, goal_id, name, description, status, lead_agent_id,
                    target_date, color, execution_workspace_policy, archived_at, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL, ?11, ?11)",
                params![
                    project_id,
                    company_id,
                    goal_id,
                    name,
                    description,
                    status,
                    lead_agent_id,
                    target_date,
                    color,
                    workspace_policy.as_ref().map(Value::to_string),
                    now,
                ],
            )?;

            if let Some(goal_id) = goal_id.as_ref() {
                tx.execute(
                    "INSERT OR IGNORE INTO project_goals (project_id, goal_id, company_id, created_at, updated_at)
                     VALUES (?1, ?2, ?3, ?4, ?4)",
                    params![project_id, goal_id, company_id, now],
                )?;
            }

            if let Some(repo_path) = repo_path.as_ref() {
                ensure_repository_for_project_sync(
                    &tx,
                    repo_path,
                    &name,
                    repo_ref.as_deref(),
                    now.as_str(),
                )?;

                tx.execute(
                    "INSERT INTO project_workspaces (
                        id, company_id, project_id, name, cwd, repo_url, repo_ref, metadata,
                        is_primary, created_at, updated_at
                     ) VALUES (?1, ?2, ?3, 'Primary Workspace', ?4, ?5, ?6, '{}', 1, ?7, ?7)",
                    params![
                        Uuid::new_v4().to_string(),
                        company_id,
                        project_id,
                        repo_path,
                        repo_url,
                        repo_ref,
                        now,
                    ],
                )?;
            }

            insert_activity_sync(
                &tx,
                &company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "project.created",
                "project",
                &project_id,
                lead_agent_id.as_deref(),
                Some(json!({ "name": name })),
                &now,
            )?;

            let project = get_project_sync(&tx, &project_id)?
                .ok_or_else(|| DatabaseError::NotFound("Project missing after insert".to_string()))?;

            tx.commit()?;
            Ok(project)
        })
        .await?)
}

pub async fn list_issues(db: &AsyncDatabase, filter: IssueListFilter) -> BoardResult<Vec<Issue>> {
    Ok(db
        .call_with_operation("board.issue.list", move |conn| {
            list_issues_sync(conn, &filter)
        })
        .await?)
}

pub async fn get_issue(db: &AsyncDatabase, issue_id: &str) -> BoardResult<Option<Issue>> {
    let issue_id = issue_id.to_string();
    Ok(db
        .call_with_operation("board.issue.get", move |conn| {
            get_issue_sync(conn, &issue_id)
        })
        .await?)
}

pub async fn create_issue(db: &AsyncDatabase, input: CreateIssueInput) -> BoardResult<Issue> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let title = require_name(&input.title, "issue title")?;
    let description = normalize_optional_string(input.description);
    let status = input.status.unwrap_or_else(|| "backlog".to_string());
    let priority = input.priority.unwrap_or_else(|| "medium".to_string());
    let project_id = normalize_optional_string(input.project_id);
    let goal_id = normalize_optional_string(input.goal_id);
    let parent_id = normalize_optional_string(input.parent_id);
    let assignee_agent_id = normalize_optional_string(input.assignee_agent_id);
    let assignee_user_id = normalize_optional_string(input.assignee_user_id);
    let created_by_agent_id = normalize_optional_string(input.created_by_agent_id);
    let created_by_user_id = normalize_optional_string(input.created_by_user_id);
    let billing_code = normalize_optional_string(input.billing_code);
    let assignee_adapter_overrides = input.assignee_adapter_overrides;
    let execution_workspace_settings = input.execution_workspace_settings;
    let label_ids = input.label_ids.unwrap_or_default();
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.issue.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;
            let issue_id = Uuid::new_v4().to_string();
            let (issue_number, identifier) = next_issue_identifier(&tx, &company_id, &company.issue_prefix)?;
            let request_depth = if let Some(parent_id) = parent_id.as_ref() {
                tx.query_row(
                    "SELECT COALESCE(request_depth, 0) + 1 FROM issues WHERE id = ?1 AND company_id = ?2",
                    params![parent_id, company_id],
                    |row| row.get::<_, i64>(0),
                )?
            } else {
                0
            };
            let execution_agent_name_key = if let Some(agent_id) = assignee_agent_id.as_ref() {
                tx.query_row(
                    "SELECT slug FROM agents WHERE id = ?1 AND company_id = ?2",
                    params![agent_id, company_id],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
            } else {
                None
            };

            tx.execute(
                "INSERT INTO issues (
                    id, company_id, project_id, goal_id, parent_id, title, description, status, priority,
                    assignee_agent_id, assignee_user_id, checkout_run_id, execution_run_id,
                    execution_agent_name_key, execution_locked_at, created_by_agent_id, created_by_user_id,
                    issue_number, identifier, request_depth, billing_code,
                    assignee_adapter_overrides, execution_workspace_settings,
                    started_at, completed_at, cancelled_at, hidden_at, created_at, updated_at
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
                    ?10, ?11, NULL, NULL,
                    ?12, NULL, ?13, ?14,
                    ?15, ?16, ?17, ?18,
                    ?19, ?20,
                    NULL, NULL, NULL, NULL, ?21, ?21
                 )",
                params![
                    issue_id,
                    company_id,
                    project_id,
                    goal_id,
                    parent_id,
                    title,
                    description,
                    status,
                    priority,
                    assignee_agent_id,
                    assignee_user_id,
                    execution_agent_name_key,
                    created_by_agent_id,
                    created_by_user_id,
                    issue_number,
                    identifier,
                    request_depth,
                    billing_code,
                    assignee_adapter_overrides.as_ref().map(Value::to_string),
                    execution_workspace_settings.as_ref().map(Value::to_string),
                    now,
                ],
            )?;

            for label_id in label_ids {
                tx.execute(
                    "INSERT OR IGNORE INTO issue_labels (issue_id, label_id, company_id, created_at)
                     VALUES (?1, ?2, ?3, ?4)",
                    params![issue_id, label_id, company_id, now],
                )?;
            }

            insert_activity_sync(
                &tx,
                &company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "issue.created",
                "issue",
                &issue_id,
                created_by_agent_id.as_deref(),
                Some(json!({
                    "identifier": identifier,
                    "status": status,
                    "priority": priority,
                    "parent_id": parent_id,
                })),
                &now,
            )?;

            let issue = get_issue_sync(&tx, &issue_id)?
                .ok_or_else(|| DatabaseError::NotFound("Issue missing after insert".to_string()))?;
            tx.commit()?;
            Ok(issue)
        })
        .await?)
}

pub async fn list_issue_comments(
    db: &AsyncDatabase,
    issue_id: &str,
) -> BoardResult<Vec<IssueComment>> {
    let issue_id = issue_id.to_string();
    Ok(db
        .call_with_operation("board.issue.comment.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT id, company_id, issue_id, author_agent_id, author_user_id, body, created_at, updated_at
                 FROM issue_comments
                 WHERE issue_id = ?1
                 ORDER BY created_at ASC",
            )?;
            let comments = stmt
                .query_map(params![issue_id], row_to_issue_comment)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(comments)
        })
        .await?)
}

pub async fn add_issue_comment(
    db: &AsyncDatabase,
    input: AddIssueCommentInput,
) -> BoardResult<IssueComment> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let issue_id = require_name(&input.issue_id, "issue_id")?;
    let body = require_name(&input.body, "comment body")?;
    let author_agent_id = normalize_optional_string(input.author_agent_id);
    let author_user_id = normalize_optional_string(input.author_user_id)
        .or_else(|| Some(LOCAL_BOARD_USER_ID.to_string()));
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.issue.comment.add", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let comment_id = Uuid::new_v4().to_string();
            tx.execute(
                "INSERT INTO issue_comments (
                    id, company_id, issue_id, author_agent_id, author_user_id, body, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)",
                params![
                    comment_id,
                    company_id,
                    issue_id,
                    author_agent_id,
                    author_user_id,
                    body,
                    now,
                ],
            )?;

            insert_activity_sync(
                &tx,
                &company_id,
                if author_agent_id.is_some() { "agent" } else { "user" },
                author_agent_id.as_deref().unwrap_or(LOCAL_BOARD_USER_ID),
                "issue.comment_added",
                "issue_comment",
                &comment_id,
                author_agent_id.as_deref(),
                Some(json!({ "issue_id": issue_id })),
                &now,
            )?;

            let comment = tx
                .query_row(
                    "SELECT id, company_id, issue_id, author_agent_id, author_user_id, body, created_at, updated_at
                     FROM issue_comments
                     WHERE id = ?1",
                    params![comment_id],
                    row_to_issue_comment,
                )
                .optional()?
                .ok_or_else(|| DatabaseError::NotFound("Comment missing after insert".to_string()))?;
            tx.commit()?;
            Ok(comment)
        })
        .await?)
}

pub async fn list_approvals(db: &AsyncDatabase, company_id: &str) -> BoardResult<Vec<Approval>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.approval.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, type, requested_by_agent_id, requested_by_user_id,
                    status, payload, decision_note, decided_by_user_id, decided_at,
                    created_at, updated_at
                 FROM approvals
                 WHERE company_id = ?1
                 ORDER BY created_at DESC",
            )?;
            let approvals = stmt
                .query_map(params![company_id], row_to_approval)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(approvals)
        })
        .await?)
}

pub async fn get_approval(db: &AsyncDatabase, approval_id: &str) -> BoardResult<Option<Approval>> {
    let approval_id = approval_id.to_string();
    Ok(db
        .call_with_operation("board.approval.get", move |conn| {
            conn.query_row(
                "SELECT
                    id, company_id, type, requested_by_agent_id, requested_by_user_id,
                    status, payload, decision_note, decided_by_user_id, decided_at,
                    created_at, updated_at
                 FROM approvals
                 WHERE id = ?1",
                params![approval_id],
                row_to_approval,
            )
            .optional()
            .map_err(Into::into)
        })
        .await?)
}

pub async fn approve_approval(
    db: &AsyncDatabase,
    input: ApprovalDecisionInput,
) -> BoardResult<Approval> {
    let approval_id = require_name(&input.approval_id, "approval_id")?;
    let decided_by_user_id = normalize_optional_string(input.decided_by_user_id)
        .unwrap_or_else(|| LOCAL_BOARD_USER_ID.to_string());
    let decision_note = normalize_optional_string(input.decision_note);
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.approval.approve", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let approval = tx
                .query_row(
                    "SELECT
                        id, company_id, type, requested_by_agent_id, requested_by_user_id,
                        status, payload, decision_note, decided_by_user_id, decided_at,
                        created_at, updated_at
                     FROM approvals
                     WHERE id = ?1",
                    params![approval_id],
                    row_to_approval,
                )
                .optional()?
                .ok_or_else(|| DatabaseError::NotFound("Approval not found".to_string()))?;

            tx.execute(
                "UPDATE approvals
                 SET status = 'approved', decision_note = ?1, decided_by_user_id = ?2, decided_at = ?3, updated_at = ?3
                 WHERE id = ?4",
                params![decision_note, decided_by_user_id, now, approval_id],
            )?;

            if approval.approval_type == "hire_agent" {
                if let Some(agent_id) = approval.payload.get("agent_id").and_then(Value::as_str) {
                    tx.execute(
                        "UPDATE agents SET status = 'idle', updated_at = ?1 WHERE id = ?2",
                        params![now, agent_id],
                    )?;
                }
            }

            insert_activity_sync(
                &tx,
                &approval.company_id,
                "user",
                &decided_by_user_id,
                "approval.approved",
                "approval",
                &approval_id,
                approval.requested_by_agent_id.as_deref(),
                Some(json!({ "type": approval.approval_type })),
                &now,
            )?;

            let approval = tx
                .query_row(
                    "SELECT
                        id, company_id, type, requested_by_agent_id, requested_by_user_id,
                        status, payload, decision_note, decided_by_user_id, decided_at,
                        created_at, updated_at
                     FROM approvals
                     WHERE id = ?1",
                    params![approval_id],
                    row_to_approval,
                )
                .optional()?
                .ok_or_else(|| DatabaseError::NotFound("Approval missing after update".to_string()))?;
            tx.commit()?;
            Ok(approval)
        })
        .await?)
}

pub async fn list_workspaces(db: &AsyncDatabase, company_id: &str) -> BoardResult<Vec<Workspace>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.workspace.list", move |conn| {
            list_workspaces_sync(conn, &company_id)
        })
        .await?)
}

pub async fn get_workspace(db: &AsyncDatabase, session_id: &str) -> BoardResult<Option<Workspace>> {
    let session_id = session_id.to_string();
    Ok(db
        .call_with_operation("board.workspace.get", move |conn| {
            conn.query_row(
                &workspace_select_sql(Some("s.id = ?1")),
                params![session_id],
                row_to_workspace,
            )
            .optional()
            .map_err(Into::into)
        })
        .await?)
}

pub async fn start_issue_workspace<W: SessionWriter + Sync>(
    db: &AsyncDatabase,
    writer: &W,
    issue_id: &str,
) -> BoardResult<Workspace> {
    let issue_id = issue_id.to_string();
    let ctx = db
        .call_with_operation("board.workspace.start.context", move |conn| {
            let issue = get_issue_sync(conn, &issue_id)?
                .ok_or_else(|| DatabaseError::NotFound("Issue not found".to_string()))?;
            let company_id = issue.company_id.clone();
            let assignee_agent_id = issue.assignee_agent_id.clone().ok_or_else(|| {
                DatabaseError::InvalidData("Issue must be assigned to an agent".to_string())
            })?;
            let project_id = issue.project_id.clone().ok_or_else(|| {
                DatabaseError::InvalidData("Issue must belong to a project".to_string())
            })?;

            if let Some(workspace) = find_latest_workspace_for_issue_sync(conn, &issue.id)? {
                if workspace.workspace_status == "active" {
                    return Ok(StartWorkspaceContext::Existing(workspace));
                }
            }

            let primary = get_primary_project_workspace_by_project_sync(conn, &project_id)?
                .ok_or_else(|| {
                    DatabaseError::NotFound("Project primary workspace not configured".to_string())
                })?;
            let cwd = primary.cwd.clone().ok_or_else(|| {
                DatabaseError::InvalidData("Project primary workspace has no repo path".to_string())
            })?;
            let repository = queries::get_repository_by_path(conn, &cwd)?
                .map(|repo| (repo.id, repo.default_branch))
                .unwrap_or_else(|| {
                    let repo_id = Uuid::new_v4().to_string();
                    (repo_id, None)
                });
            if queries::get_repository_by_path(conn, &cwd)?.is_none() {
                let repo_name = Path::new(&cwd)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or("workspace")
                    .to_string();
                let repo = NewRepository {
                    id: repository.0.clone(),
                    path: cwd.clone(),
                    name: repo_name,
                    is_git_repository: true,
                    sessions_path: None,
                    default_branch: primary.repo_ref.clone(),
                    default_remote: None,
                };
                let _ = queries::insert_repository(conn, &repo)?;
            }

            let title = issue
                .identifier
                .as_ref()
                .map(|identifier| format!("{identifier}: {}", issue.title))
                .unwrap_or_else(|| issue.title.clone());
            Ok(StartWorkspaceContext::Create {
                issue,
                company_id,
                project_id,
                agent_id: assignee_agent_id,
                repository_id: repository.0,
                repo_path: cwd,
                repo_branch: primary.repo_ref.or(repository.1),
                title,
            })
        })
        .await?;

    let (issue, company_id, project_id, agent_id, repository_id, repo_path, repo_branch, title) =
        match ctx {
            StartWorkspaceContext::Existing(workspace) => return Ok(workspace),
            StartWorkspaceContext::Create {
                issue,
                company_id,
                project_id,
                agent_id,
                repository_id,
                repo_path,
                repo_branch,
                title,
            } => (
                issue,
                company_id,
                project_id,
                agent_id,
                repository_id,
                repo_path,
                repo_branch,
                title,
            ),
        };

    let agent = get_agent(db, &agent_id)
        .await?
        .ok_or_else(|| DatabaseError::NotFound("Assigned agent not found".to_string()))?;

    let session = writer
        .create_session_with_metadata(NewSession {
            id: agent_session_sqlite_persist_core::SessionId::new(),
            repository_id: RepositoryId::from_string(&repository_id),
            title,
            agent_id: Some(agent_id.clone()),
            agent_name: Some(agent.name.clone()),
            issue_id: Some(issue.id.clone()),
            issue_title: Some(issue.title.clone()),
            issue_url: None,
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        })
        .map_err(|error| BoardError::Runtime(error.to_string()))?;

    let session_id = session.id.as_str().to_string();
    let now = now_rfc3339();
    Ok(db
        .call_with_operation("board.workspace.start.persist", move |conn| {
            let tx = conn.unchecked_transaction()?;
            tx.execute(
                "UPDATE agent_coding_sessions
                 SET company_id = ?1,
                     project_id = ?2,
                     issue_id = ?3,
                     agent_id = ?4,
                     workspace_type = 'issue',
                     workspace_status = 'active',
                     workspace_repo_path = ?5,
                     workspace_branch = ?6,
                     workspace_metadata = ?7,
                     updated_at = ?8
                 WHERE id = ?9",
                params![
                    company_id,
                    project_id,
                    issue.id,
                    agent_id,
                    repo_path,
                    repo_branch,
                    json!({
                        "issue_id": issue.id,
                        "issue_identifier": issue.identifier,
                        "project_id": project_id,
                        "agent_id": agent_id,
                    })
                    .to_string(),
                    now,
                    session_id,
                ],
            )?;

            tx.execute(
                "INSERT INTO agent_task_sessions (
                    id, company_id, agent_id, adapter_type, task_key, session_params_json,
                    session_display_id, last_run_id, last_error, created_at, updated_at
                 ) VALUES (
                    ?1, ?2, ?3, 'issue_workspace', ?4, ?5, ?6, NULL, NULL, ?7, ?7
                 )
                 ON CONFLICT(company_id, agent_id, adapter_type, task_key) DO UPDATE SET
                    session_params_json = excluded.session_params_json,
                    session_display_id = excluded.session_display_id,
                    updated_at = excluded.updated_at",
                params![
                    Uuid::new_v4().to_string(),
                    company_id,
                    agent_id,
                    format!("issue:{}", issue.id),
                    json!({ "session_id": session_id, "issue_id": issue.id }).to_string(),
                    issue.identifier,
                    now,
                ],
            )?;

            tx.execute(
                "UPDATE issues
                 SET status = CASE
                        WHEN status IN ('done', 'cancelled') THEN status
                        ELSE 'in_progress'
                     END,
                     started_at = COALESCE(started_at, ?1),
                     updated_at = ?1
                 WHERE id = ?2",
                params![now, issue.id],
            )?;

            insert_activity_sync(
                &tx,
                &company_id,
                "agent",
                &agent_id,
                "workspace.created",
                "workspace",
                &session_id,
                Some(&agent_id),
                Some(json!({
                    "issue_id": issue.id,
                    "project_id": project_id,
                    "repo_path": repo_path,
                })),
                &now,
            )?;

            let workspace = conn
                .query_row(
                    &workspace_select_sql(Some("s.id = ?1")),
                    params![session_id],
                    row_to_workspace,
                )
                .optional()?
                .ok_or_else(|| {
                    DatabaseError::NotFound("Workspace missing after create".to_string())
                })?;

            tx.commit()?;
            Ok(workspace)
        })
        .await?)
}

#[derive(Debug)]
enum StartWorkspaceContext {
    Existing(Workspace),
    Create {
        issue: Issue,
        company_id: String,
        project_id: String,
        agent_id: String,
        repository_id: String,
        repo_path: String,
        repo_branch: Option<String>,
        title: String,
    },
}

fn list_companies_sync(conn: &Connection) -> DatabaseResult<Vec<Company>> {
    let mut stmt = conn.prepare(
        "SELECT
            c.id, c.name, c.description, c.status, c.issue_prefix, c.issue_counter,
            c.budget_monthly_cents, c.spent_monthly_cents, c.require_board_approval_for_new_agents,
            c.brand_color,
            (
                SELECT a.id
                FROM agents a
                WHERE a.company_id = c.id AND a.role = 'ceo'
                ORDER BY a.created_at ASC
                LIMIT 1
            ) AS ceo_agent_id,
            c.created_at, c.updated_at
         FROM companies c
         ORDER BY c.created_at DESC",
    )?;
    let companies = stmt
        .query_map([], row_to_company)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(DatabaseError::from)?;
    Ok(companies)
}

fn get_company_sync(conn: &Connection, company_id: &str) -> DatabaseResult<Option<Company>> {
    conn.query_row(
        "SELECT
            c.id, c.name, c.description, c.status, c.issue_prefix, c.issue_counter,
            c.budget_monthly_cents, c.spent_monthly_cents, c.require_board_approval_for_new_agents,
            c.brand_color,
            (
                SELECT a.id
                FROM agents a
                WHERE a.company_id = c.id AND a.role = 'ceo'
                ORDER BY a.created_at ASC
                LIMIT 1
            ) AS ceo_agent_id,
            c.created_at, c.updated_at
         FROM companies c
         WHERE c.id = ?1",
        params![company_id],
        row_to_company,
    )
    .optional()
    .map_err(Into::into)
}

fn list_projects_sync(conn: &Connection, company_id: &str) -> DatabaseResult<Vec<Project>> {
    let mut stmt = conn.prepare(
        "SELECT
            id, company_id, goal_id, name, description, status, lead_agent_id,
            target_date, color, execution_workspace_policy, archived_at, created_at, updated_at
         FROM projects
         WHERE company_id = ?1
         ORDER BY created_at DESC",
    )?;

    let project_rows = stmt
        .query_map(params![company_id], |row| {
            Ok((row.get::<_, String>(0)?, row_to_project_base(row)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut projects = Vec::with_capacity(project_rows.len());
    for (project_id, mut project) in project_rows {
        project.primary_workspace =
            get_primary_project_workspace_by_project_sync(conn, &project_id)?;
        projects.push(project);
    }
    Ok(projects)
}

fn get_project_sync(conn: &Connection, project_id: &str) -> DatabaseResult<Option<Project>> {
    let mut project = conn
        .query_row(
            "SELECT
                id, company_id, goal_id, name, description, status, lead_agent_id,
                target_date, color, execution_workspace_policy, archived_at, created_at, updated_at
             FROM projects
             WHERE id = ?1",
            params![project_id],
            row_to_project_base,
        )
        .optional()?;

    if let Some(project) = project.as_mut() {
        project.primary_workspace =
            get_primary_project_workspace_by_project_sync(conn, project_id)?;
    }

    Ok(project)
}

fn list_issues_sync(conn: &Connection, filter: &IssueListFilter) -> DatabaseResult<Vec<Issue>> {
    let mut sql = String::from(
        "SELECT
            i.id, i.company_id, i.project_id, i.goal_id, i.parent_id, i.title, i.description,
            i.status, i.priority, i.assignee_agent_id, i.assignee_user_id, i.checkout_run_id,
            i.execution_run_id, i.execution_agent_name_key, i.execution_locked_at,
            i.created_by_agent_id, i.created_by_user_id, i.issue_number, i.identifier,
            i.request_depth, i.billing_code, i.assignee_adapter_overrides,
            i.execution_workspace_settings, i.started_at, i.completed_at, i.cancelled_at,
            i.hidden_at,
            (
                SELECT s.id
                FROM agent_coding_sessions s
                WHERE s.issue_id = i.id AND s.workspace_type = 'issue'
                ORDER BY s.created_at DESC
                LIMIT 1
            ) AS workspace_session_id,
            i.created_at, i.updated_at
         FROM issues i
         WHERE i.company_id = ?1",
    );
    let mut param_values: Vec<String> = vec![filter.company_id.clone()];

    if let Some(project_id) = filter.project_id.as_ref() {
        sql.push_str(" AND i.project_id = ?");
        sql.push_str(&(param_values.len() + 1).to_string());
        param_values.push(project_id.clone());
    }
    if let Some(parent_id) = filter.parent_id.as_ref() {
        sql.push_str(" AND i.parent_id = ?");
        sql.push_str(&(param_values.len() + 1).to_string());
        param_values.push(parent_id.clone());
    }
    if let Some(assignee_agent_id) = filter.assignee_agent_id.as_ref() {
        sql.push_str(" AND i.assignee_agent_id = ?");
        sql.push_str(&(param_values.len() + 1).to_string());
        param_values.push(assignee_agent_id.clone());
    }
    if !filter.include_hidden.unwrap_or(false) {
        sql.push_str(" AND i.hidden_at IS NULL");
    }
    sql.push_str(" ORDER BY COALESCE(i.issue_number, 0) DESC, i.created_at DESC");

    let mut stmt = conn.prepare(&sql)?;
    let issues = stmt
        .query_map(
            rusqlite::params_from_iter(param_values.iter()),
            row_to_issue,
        )?
        .collect::<Result<Vec<_>, _>>()
        .map_err(DatabaseError::from)?;
    Ok(issues)
}

fn get_issue_sync(conn: &Connection, issue_id: &str) -> DatabaseResult<Option<Issue>> {
    conn.query_row(
        "SELECT
            i.id, i.company_id, i.project_id, i.goal_id, i.parent_id, i.title, i.description,
            i.status, i.priority, i.assignee_agent_id, i.assignee_user_id, i.checkout_run_id,
            i.execution_run_id, i.execution_agent_name_key, i.execution_locked_at,
            i.created_by_agent_id, i.created_by_user_id, i.issue_number, i.identifier,
            i.request_depth, i.billing_code, i.assignee_adapter_overrides,
            i.execution_workspace_settings, i.started_at, i.completed_at, i.cancelled_at,
            i.hidden_at,
            (
                SELECT s.id
                FROM agent_coding_sessions s
                WHERE s.issue_id = i.id AND s.workspace_type = 'issue'
                ORDER BY s.created_at DESC
                LIMIT 1
            ) AS workspace_session_id,
            i.created_at, i.updated_at
         FROM issues i
         WHERE i.id = ?1",
        params![issue_id],
        row_to_issue,
    )
    .optional()
    .map_err(Into::into)
}

fn find_latest_workspace_for_issue_sync(
    conn: &Connection,
    issue_id: &str,
) -> DatabaseResult<Option<Workspace>> {
    conn.query_row(
        &workspace_select_sql(Some("s.issue_id = ?1 AND s.workspace_type = 'issue'")),
        params![issue_id],
        row_to_workspace,
    )
    .optional()
    .map_err(Into::into)
}

fn list_workspaces_sync(conn: &Connection, company_id: &str) -> DatabaseResult<Vec<Workspace>> {
    let mut stmt = conn.prepare(&workspace_select_sql(Some("s.company_id = ?1")))?;
    let workspaces = stmt
        .query_map(params![company_id], row_to_workspace)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(DatabaseError::from)?;
    Ok(workspaces)
}

fn row_to_company(row: &Row<'_>) -> rusqlite::Result<Company> {
    Ok(Company {
        id: row.get(0)?,
        name: row.get(1)?,
        description: row.get(2)?,
        status: row.get(3)?,
        issue_prefix: row.get(4)?,
        issue_counter: row.get(5)?,
        budget_monthly_cents: row.get(6)?,
        spent_monthly_cents: row.get(7)?,
        require_board_approval_for_new_agents: row.get(8)?,
        brand_color: row.get(9)?,
        ceo_agent_id: row.get(10)?,
        created_at: row.get(11)?,
        updated_at: row.get(12)?,
    })
}

fn row_to_agent(row: &Row<'_>) -> rusqlite::Result<Agent> {
    Ok(Agent {
        id: row.get(0)?,
        company_id: row.get(1)?,
        name: row.get(2)?,
        slug: row.get(3)?,
        role: row.get(4)?,
        title: row.get(5)?,
        icon: row.get(6)?,
        status: row.get(7)?,
        reports_to: row.get(8)?,
        capabilities: row.get(9)?,
        adapter_type: row.get(10)?,
        adapter_config: parse_json(row.get::<_, String>(11)?),
        runtime_config: parse_json(row.get::<_, String>(12)?),
        budget_monthly_cents: row.get(13)?,
        spent_monthly_cents: row.get(14)?,
        permissions: parse_json(row.get::<_, String>(15)?),
        last_heartbeat_at: row.get(16)?,
        metadata: row
            .get::<_, Option<String>>(17)?
            .map(|value| parse_json(value)),
        home_path: row.get(18)?,
        instructions_path: row.get(19)?,
        created_at: row.get(20)?,
        updated_at: row.get(21)?,
    })
}

fn row_to_project_base(row: &Row<'_>) -> rusqlite::Result<Project> {
    Ok(Project {
        id: row.get(0)?,
        company_id: row.get(1)?,
        goal_id: row.get(2)?,
        name: row.get(3)?,
        description: row.get(4)?,
        status: row.get(5)?,
        lead_agent_id: row.get(6)?,
        target_date: row.get(7)?,
        color: row.get(8)?,
        execution_workspace_policy: row
            .get::<_, Option<String>>(9)?
            .map(|value| parse_json(value)),
        archived_at: row.get(10)?,
        created_at: row.get(11)?,
        updated_at: row.get(12)?,
        primary_workspace: None,
    })
}

fn row_to_project_workspace(row: &Row<'_>) -> rusqlite::Result<ProjectWorkspace> {
    Ok(ProjectWorkspace {
        id: row.get(0)?,
        company_id: row.get(1)?,
        project_id: row.get(2)?,
        name: row.get(3)?,
        cwd: row.get(4)?,
        repo_url: row.get(5)?,
        repo_ref: row.get(6)?,
        metadata: row
            .get::<_, Option<String>>(7)?
            .map(|value| parse_json(value)),
        is_primary: row.get(8)?,
        created_at: row.get(9)?,
        updated_at: row.get(10)?,
    })
}

fn row_to_goal(row: &Row<'_>) -> rusqlite::Result<Goal> {
    Ok(Goal {
        id: row.get(0)?,
        company_id: row.get(1)?,
        title: row.get(2)?,
        description: row.get(3)?,
        level: row.get(4)?,
        status: row.get(5)?,
        parent_id: row.get(6)?,
        owner_agent_id: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

fn row_to_issue(row: &Row<'_>) -> rusqlite::Result<Issue> {
    Ok(Issue {
        id: row.get(0)?,
        company_id: row.get(1)?,
        project_id: row.get(2)?,
        goal_id: row.get(3)?,
        parent_id: row.get(4)?,
        title: row.get(5)?,
        description: row.get(6)?,
        status: row.get(7)?,
        priority: row.get(8)?,
        assignee_agent_id: row.get(9)?,
        assignee_user_id: row.get(10)?,
        checkout_run_id: row.get(11)?,
        execution_run_id: row.get(12)?,
        execution_agent_name_key: row.get(13)?,
        execution_locked_at: row.get(14)?,
        created_by_agent_id: row.get(15)?,
        created_by_user_id: row.get(16)?,
        issue_number: row.get(17)?,
        identifier: row.get(18)?,
        request_depth: row.get(19)?,
        billing_code: row.get(20)?,
        assignee_adapter_overrides: row
            .get::<_, Option<String>>(21)?
            .map(|value| parse_json(value)),
        execution_workspace_settings: row
            .get::<_, Option<String>>(22)?
            .map(|value| parse_json(value)),
        started_at: row.get(23)?,
        completed_at: row.get(24)?,
        cancelled_at: row.get(25)?,
        hidden_at: row.get(26)?,
        workspace_session_id: row.get(27)?,
        created_at: row.get(28)?,
        updated_at: row.get(29)?,
    })
}

fn row_to_issue_comment(row: &Row<'_>) -> rusqlite::Result<IssueComment> {
    Ok(IssueComment {
        id: row.get(0)?,
        company_id: row.get(1)?,
        issue_id: row.get(2)?,
        author_agent_id: row.get(3)?,
        author_user_id: row.get(4)?,
        body: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn row_to_approval(row: &Row<'_>) -> rusqlite::Result<Approval> {
    Ok(Approval {
        id: row.get(0)?,
        company_id: row.get(1)?,
        approval_type: row.get(2)?,
        requested_by_agent_id: row.get(3)?,
        requested_by_user_id: row.get(4)?,
        status: row.get(5)?,
        payload: parse_json(row.get::<_, String>(6)?),
        decision_note: row.get(7)?,
        decided_by_user_id: row.get(8)?,
        decided_at: row.get(9)?,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}

fn row_to_workspace(row: &Row<'_>) -> rusqlite::Result<Workspace> {
    Ok(Workspace {
        session_id: row.get(0)?,
        repository_id: row.get(1)?,
        company_id: row.get(2)?,
        project_id: row.get(3)?,
        issue_id: row.get(4)?,
        agent_id: row.get(5)?,
        title: row.get(6)?,
        status: row.get(7)?,
        workspace_type: row.get(8)?,
        workspace_status: row.get(9)?,
        workspace_repo_path: row.get(10)?,
        workspace_branch: row.get(11)?,
        workspace_metadata: parse_json(row.get::<_, String>(12)?),
        issue_identifier: row.get(13)?,
        issue_title: row.get(14)?,
        project_name: row.get(15)?,
        agent_name: row.get(16)?,
        created_at: row.get(17)?,
        last_accessed_at: row.get(18)?,
        updated_at: row.get(19)?,
    })
}

fn get_primary_project_workspace_by_project_sync(
    conn: &Connection,
    project_id: &str,
) -> DatabaseResult<Option<ProjectWorkspace>> {
    conn.query_row(
        "SELECT
            id, company_id, project_id, name, cwd, repo_url, repo_ref, metadata,
            is_primary, created_at, updated_at
         FROM project_workspaces
         WHERE project_id = ?1
         ORDER BY is_primary DESC, created_at ASC
         LIMIT 1",
        params![project_id],
        row_to_project_workspace,
    )
    .optional()
    .map_err(Into::into)
}

fn ensure_local_board_user(conn: &Connection, now: &str) -> DatabaseResult<()> {
    conn.execute(
        "INSERT OR IGNORE INTO auth_users (
            id, name, email, email_verified, image, created_at, updated_at
         ) VALUES (?1, ?2, ?3, 1, NULL, ?4, ?4)",
        params![
            LOCAL_BOARD_USER_ID,
            LOCAL_BOARD_NAME,
            LOCAL_BOARD_EMAIL,
            now
        ],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO instance_user_roles (
            id, user_id, role, created_at, updated_at
         ) VALUES (?1, ?2, 'instance_admin', ?3, ?3)",
        params![Uuid::new_v4().to_string(), LOCAL_BOARD_USER_ID, now],
    )?;
    Ok(())
}

fn next_issue_identifier(
    conn: &Connection,
    company_id: &str,
    prefix: &str,
) -> DatabaseResult<(i64, String)> {
    let counter: i64 = conn.query_row(
        "SELECT issue_counter FROM companies WHERE id = ?1",
        params![company_id],
        |row| row.get(0),
    )?;
    let next = counter + 1;
    conn.execute(
        "UPDATE companies SET issue_counter = ?1, updated_at = ?2 WHERE id = ?3",
        params![next, now_rfc3339(), company_id],
    )?;
    Ok((next, format!("{prefix}-{next}")))
}

fn ensure_repository_for_project_sync(
    conn: &Connection,
    repo_path: &str,
    repo_name: &str,
    repo_ref: Option<&str>,
    now: &str,
) -> DatabaseResult<()> {
    if queries::get_repository_by_path(conn, repo_path)?.is_some() {
        return Ok(());
    }

    let repository = NewRepository {
        id: Uuid::new_v4().to_string(),
        path: repo_path.to_string(),
        name: repo_name.to_string(),
        is_git_repository: true,
        sessions_path: None,
        default_branch: repo_ref.map(ToOwned::to_owned),
        default_remote: None,
    };
    let _ = queries::insert_repository(conn, &repository)?;
    conn.execute(
        "UPDATE repositories SET added_at = ?1, last_accessed_at = ?1, updated_at = ?1 WHERE id = ?2",
        params![now, repository.id],
    )?;
    Ok(())
}

fn insert_activity_sync(
    conn: &Connection,
    company_id: &str,
    actor_type: &str,
    actor_id: &str,
    action: &str,
    entity_type: &str,
    entity_id: &str,
    agent_id: Option<&str>,
    details: Option<Value>,
    now: &str,
) -> DatabaseResult<()> {
    conn.execute(
        "INSERT INTO activity_log (
            id, company_id, actor_type, actor_id, action, entity_type, entity_id, agent_id, run_id, details, created_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, NULL, ?9, ?10)",
        params![
            Uuid::new_v4().to_string(),
            company_id,
            actor_type,
            actor_id,
            action,
            entity_type,
            entity_id,
            agent_id,
            details.map(|value| value.to_string()),
            now,
        ],
    )?;
    Ok(())
}

fn unique_issue_prefix(conn: &Connection, company_name: &str) -> DatabaseResult<String> {
    let base = derive_issue_prefix(company_name);
    for attempt in 0..100 {
        let candidate = if attempt == 0 {
            base.clone()
        } else {
            let suffix = (attempt + 1).to_string();
            let prefix_len = 6usize.saturating_sub(suffix.len());
            format!(
                "{}{}",
                base.chars().take(prefix_len.max(1)).collect::<String>(),
                suffix
            )
        };

        let exists: Option<String> = conn
            .query_row(
                "SELECT issue_prefix FROM companies WHERE issue_prefix = ?1",
                params![candidate],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_none() {
            return Ok(candidate);
        }
    }
    Err(DatabaseError::InvalidData(
        "Unable to allocate unique issue prefix".to_string(),
    ))
}

fn derive_issue_prefix(name: &str) -> String {
    let mut letters: String = name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .take(6)
        .collect();
    if letters.len() < 3 {
        letters.push_str("UNB");
    }
    letters.chars().take(3).collect()
}

fn unique_agent_slug(
    conn: &Connection,
    company_id: &str,
    base_name: &str,
) -> DatabaseResult<String> {
    let base = slugify(base_name);
    for attempt in 0..1000 {
        let candidate = if attempt == 0 {
            base.clone()
        } else {
            format!("{base}-{attempt}")
        };
        let exists: Option<String> = conn
            .query_row(
                "SELECT slug FROM agents WHERE company_id = ?1 AND slug = ?2",
                params![company_id, candidate],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_none() {
            return Ok(candidate);
        }
    }
    Err(DatabaseError::InvalidData(
        "Unable to allocate unique agent slug".to_string(),
    ))
}

fn slugify(value: &str) -> String {
    let mut slug = String::new();
    let mut last_was_dash = false;
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() {
            slug.push(ch.to_ascii_lowercase());
            last_was_dash = false;
        } else if !last_was_dash {
            slug.push('-');
            last_was_dash = true;
        }
    }
    let slug = slug.trim_matches('-').to_string();
    if slug.is_empty() {
        "agent".to_string()
    } else {
        slug
    }
}

fn parse_json(text: String) -> Value {
    serde_json::from_str(&text).unwrap_or(Value::Null)
}

fn require_name(value: &str, field_name: &str) -> BoardResult<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(BoardError::InvalidInput(format!(
            "{field_name} must not be empty"
        )));
    }
    Ok(trimmed.to_string())
}

fn normalize_optional_string(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn now_rfc3339() -> String {
    Utc::now().to_rfc3339()
}

fn scaffold_agent_home(
    paths: &Paths,
    company_id: &str,
    agent_name: &str,
    agent_slug: &str,
    company_name: &str,
    role: &str,
) -> BoardResult<()> {
    let agent_home = paths.agent_home_dir(company_id, agent_slug);
    fs::create_dir_all(paths.agent_memory_dir(company_id, agent_slug))?;
    fs::create_dir_all(paths.agent_life_dir(company_id, agent_slug))?;
    fs::create_dir_all(paths.company_assets_dir(company_id))?;
    fs::create_dir_all(paths.company_attachments_dir(company_id))?;

    let today_memory_path = paths
        .agent_memory_dir(company_id, agent_slug)
        .join(format!("{}.md", Utc::now().format("%Y-%m-%d")));

    write_if_missing(
        &agent_home.join("AGENTS.md"),
        &format!(
            "# {agent_name}\n\nYou are an {role} agent working inside Unbound for {company_name}.\nOperate through the daemon-managed local board.\n"
        ),
    )?;
    write_if_missing(
        &agent_home.join("HEARTBEAT.md"),
        "# Heartbeat\n\nUse this file to capture current execution rhythm, blockers, and next wake-up context.\n",
    )?;
    write_if_missing(
        &agent_home.join("SOUL.md"),
        "# Soul\n\nDocument enduring purpose, principles, and preferences for this Unbound agent.\n",
    )?;
    write_if_missing(
        &agent_home.join("TOOLS.md"),
        "# Tools\n\nList the tools, adapters, and repo anchors this agent relies on inside Unbound.\n",
    )?;
    write_if_missing(
        &agent_home.join("MEMORY.md"),
        "# Memory\n\nSummarize durable context, recent decisions, and important references.\n",
    )?;
    write_if_missing(
        &today_memory_path,
        "# Daily Memory\n\nCapture the most important events for this agent today.\n",
    )?;

    Ok(())
}

fn write_if_missing(path: &Path, contents: &str) -> BoardResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if !path.exists() {
        fs::write(path, contents)?;
    }
    Ok(())
}

fn find_company_ceo_sync(conn: &Connection, company_id: &str) -> DatabaseResult<Option<String>> {
    conn.query_row(
        "SELECT id FROM agents WHERE company_id = ?1 AND role = 'ceo' ORDER BY created_at ASC LIMIT 1",
        params![company_id],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn workspace_select_sql(predicate: Option<&str>) -> String {
    let mut sql = String::from(
        "SELECT
            s.id, s.repository_id, s.company_id, s.project_id, s.issue_id, s.agent_id,
            s.title, s.status, s.workspace_type, s.workspace_status, s.workspace_repo_path,
            s.workspace_branch, COALESCE(s.workspace_metadata, '{}'),
            i.identifier, i.title, p.name, a.name,
            s.created_at, s.last_accessed_at, s.updated_at
         FROM agent_coding_sessions s
         LEFT JOIN issues i ON i.id = s.issue_id
         LEFT JOIN projects p ON p.id = s.project_id
         LEFT JOIN agents a ON a.id = s.agent_id",
    );
    if let Some(predicate) = predicate {
        sql.push_str(" WHERE ");
        sql.push_str(predicate);
    }
    sql.push_str(" ORDER BY s.updated_at DESC, s.created_at DESC");
    sql
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn create_company_bootstraps_ceo_and_files() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let companies = list_companies(&db).await.unwrap();
        assert_eq!(companies.len(), 1);
        assert_eq!(company.issue_prefix, "ACM");

        let agents = list_agents(&db, &company.id).await.unwrap();
        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0].role, "ceo");
        assert!(Path::new(agents[0].home_path.as_ref().unwrap()).exists());
        assert!(
            Path::new(agents[0].instructions_path.as_ref().unwrap()).exists(),
            "AGENTS.md should exist"
        );
    }
}
