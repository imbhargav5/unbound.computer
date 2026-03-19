use crate::error::{BoardError, BoardResult};
use crate::models::{
    AddIssueAttachmentInput, AddIssueCommentInput, Agent, AgentLiveRunCount, AgentRun,
    AgentRunEvent, Approval, ApprovalDecisionInput, Company, CreateAgentDecisionApprovalInput,
    CreateAgentHireInput, CreateAgentInput, CreateCompanyInput, CreateIssueInput,
    CreateProjectInput, Goal, Issue, IssueAttachment, IssueComment, IssueListFilter,
    IssueRunCardUpdate, Project, ProjectWorkspace, UpdateAgentInput, UpdateIssueInput, Workspace,
};
use crate::run_summary::{
    summarize_agent_run_event, summarize_agent_run_excerpt, summarize_agent_run_result,
    summarize_agent_run_text,
};
use agent_session_sqlite_persist_core::{NewSession, RepositoryId, SessionWriter};
use chrono::Utc;
use daemon_config_and_utils::Paths;
use daemon_database::{queries, AsyncDatabase, DatabaseError, DatabaseResult, NewRepository};
use rusqlite::{
    params, params_from_iter, types::Value as SqlValue, Connection, OptionalExtension, Row,
};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
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

#[derive(Clone, Debug)]
struct HireApprovalActivationTarget {
    approval_id: String,
    company_id: String,
    agent_id: String,
    agent_name: String,
    agent_slug: String,
    agent_role: String,
    adapter_type: String,
    company_name: String,
}

#[derive(Debug)]
struct PreparedHireApprovalActivation {
    agent_home: std::path::PathBuf,
    home_existed_before: bool,
}

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
    _paths: &Paths,
    input: CreateCompanyInput,
) -> BoardResult<Company> {
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
            let issue_prefix = unique_issue_prefix(&tx, &name)?;
            let company_name = name.clone();

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

            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company missing after insert".to_string()))?;

            tx.commit()?;
            Ok(company)
        })
        .await?;
    Ok(creation)
}

pub async fn update_company(
    db: &AsyncDatabase,
    input: crate::models::UpdateCompanyInput,
) -> BoardResult<Company> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let brand_color = normalize_optional_string(input.brand_color);
    let now = now_rfc3339();

    let updated_company = db
        .call_with_operation("board.company.update", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let existing_company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;

            tx.execute(
                "UPDATE companies
                 SET brand_color = ?1, updated_at = ?2
                 WHERE id = ?3",
                params![brand_color, now, company_id],
            )?;

            insert_activity_sync(
                &tx,
                &existing_company.id,
                "system",
                LOCAL_BOARD_USER_ID,
                "company.updated",
                "company",
                &existing_company.id,
                None,
                Some(json!({
                    "brand_color": brand_color,
                })),
                &now,
            )?;

            let company = get_company_sync(&tx, &existing_company.id)?.ok_or_else(|| {
                DatabaseError::NotFound("Company missing after update".to_string())
            })?;

            tx.commit()?;
            Ok(company)
        })
        .await?;

    Ok(updated_company)
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
            get_agent_sync(conn, &agent_id).map_err(Into::into)
        })
        .await?)
}

pub async fn update_agent(db: &AsyncDatabase, input: UpdateAgentInput) -> BoardResult<Agent> {
    let agent_id = require_name(&input.agent_id, "agent_id")?;
    let name = match input.name {
        Some(value) => Some(require_name(&value, "agent name")?),
        None => None,
    };
    let title = normalize_optional_update(input.title);
    let capabilities = normalize_optional_update(input.capabilities);
    let adapter_type = input.adapter_type.map(|value| value.trim().to_string());
    let adapter_config = input.adapter_config;
    let runtime_config = input.runtime_config;
    let budget_monthly_cents = input.budget_monthly_cents.map(|value| value.max(0));
    let permissions = input.permissions;
    let metadata = input.metadata;
    let home_path = normalize_optional_update(input.home_path);
    let instructions_path = normalize_optional_update(input.instructions_path);
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.agent.update", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let current = get_agent_sync(&tx, &agent_id)?
                .ok_or_else(|| DatabaseError::NotFound("Agent not found".to_string()))?;

            let next_name = name.unwrap_or_else(|| current.name.clone());
            let next_title = title.unwrap_or_else(|| current.title.clone());
            let next_capabilities = capabilities.unwrap_or_else(|| current.capabilities.clone());
            let next_adapter_type = adapter_type
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| current.adapter_type.clone());
            let next_adapter_config =
                adapter_config.unwrap_or_else(|| current.adapter_config.clone());
            let next_runtime_config =
                runtime_config.unwrap_or_else(|| current.runtime_config.clone());
            let next_budget_monthly_cents =
                budget_monthly_cents.unwrap_or(current.budget_monthly_cents);
            let next_permissions = permissions.unwrap_or_else(|| current.permissions.clone());
            let next_metadata = metadata.unwrap_or_else(|| current.metadata.clone());
            let next_home_path = home_path.unwrap_or_else(|| current.home_path.clone());
            let next_instructions_path =
                instructions_path.unwrap_or_else(|| current.instructions_path.clone());

            let mut changed_fields = Vec::new();
            if next_name != current.name {
                changed_fields.push("name");
            }
            if next_title != current.title {
                changed_fields.push("title");
            }
            if next_capabilities != current.capabilities {
                changed_fields.push("capabilities");
            }
            if next_adapter_type != current.adapter_type {
                changed_fields.push("adapter_type");
            }
            if next_adapter_config != current.adapter_config {
                changed_fields.push("adapter_config");
            }
            if next_runtime_config != current.runtime_config {
                changed_fields.push("runtime_config");
            }
            if next_budget_monthly_cents != current.budget_monthly_cents {
                changed_fields.push("budget_monthly_cents");
            }
            if next_permissions != current.permissions {
                changed_fields.push("permissions");
            }
            if next_metadata != current.metadata {
                changed_fields.push("metadata");
            }
            if next_home_path != current.home_path {
                changed_fields.push("home_path");
            }
            if next_instructions_path != current.instructions_path {
                changed_fields.push("instructions_path");
            }

            if changed_fields.is_empty() {
                return Ok(current);
            }

            tx.execute(
                "UPDATE agents
                 SET name = ?1,
                     title = ?2,
                     capabilities = ?3,
                     adapter_type = ?4,
                     adapter_config = ?5,
                     runtime_config = ?6,
                     budget_monthly_cents = ?7,
                     permissions = ?8,
                     metadata = ?9,
                     home_path = ?10,
                     instructions_path = ?11,
                     updated_at = ?12
                 WHERE id = ?13",
                params![
                    next_name,
                    next_title,
                    next_capabilities,
                    next_adapter_type,
                    next_adapter_config.to_string(),
                    next_runtime_config.to_string(),
                    next_budget_monthly_cents,
                    next_permissions.to_string(),
                    next_metadata.as_ref().map(Value::to_string),
                    next_home_path,
                    next_instructions_path,
                    now,
                    agent_id,
                ],
            )?;

            insert_activity_sync(
                &tx,
                &current.company_id,
                "user",
                LOCAL_BOARD_USER_ID,
                "agent.updated",
                "agent",
                &current.id,
                Some(&current.id),
                Some(json!({
                    "changed_fields": changed_fields,
                })),
                &now,
            )?;

            let agent = get_agent_sync(&tx, &current.id)?
                .ok_or_else(|| DatabaseError::NotFound("Agent missing after update".to_string()))?;

            tx.commit()?;
            Ok(agent)
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
    let is_ceo = role == "ceo";
    if is_ceo {
        let company_id_for_lookup = company_id.clone();
        let existing_ceo = db
            .call_with_operation("board.agent.validate_ceo_uniqueness", move |conn| {
                find_company_ceo_sync(conn, &company_id_for_lookup)
            })
            .await?;
        if existing_ceo.is_some() {
            return Err(BoardError::Conflict(
                "Company already has a CEO agent".to_string(),
            ));
        }
    }
    let status_requires_approval = get_company(db, &company_id)
        .await?
        .map(|company| company.require_board_approval_for_new_agents)
        .unwrap_or(true);
    let desired_status = if is_ceo {
        "idle".to_string()
    } else if status_requires_approval {
        "pending_approval".to_string()
    } else {
        "idle".to_string()
    };
    let now = now_rfc3339();
    let description_title = normalize_optional_string(input.title).or_else(|| {
        if is_ceo {
            Some("Chief Executive Officer".to_string())
        } else {
            None
        }
    });
    let icon = normalize_optional_string(input.icon).or_else(|| {
        if is_ceo {
            Some("crown".to_string())
        } else {
            None
        }
    });
    let reports_to = normalize_optional_string(input.reports_to);
    let capabilities = normalize_optional_string(input.capabilities);
    let adapter_type = input.adapter_type.unwrap_or_else(|| "process".to_string());
    let adapter_config = input.adapter_config.unwrap_or_else(|| json!({}));
    let runtime_config = input.runtime_config.unwrap_or_else(|| json!({}));
    let budget = input.budget_monthly_cents.unwrap_or(0).max(0);
    let permissions = input.permissions.unwrap_or_else(|| {
        if is_ceo {
            json!({ "canCreateAgents": true })
        } else {
            json!({})
        }
    });
    let metadata = input.metadata;

    let agent = db
        .call_with_operation("board.agent.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;
            let slug = unique_agent_slug(&tx, &company_id, &name)?;
            let agent_id = Uuid::new_v4().to_string();
            let reports_to = if is_ceo {
                None
            } else {
                reports_to.or_else(|| find_company_ceo_sync(&tx, &company_id).ok().flatten())
            };
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
    let scaffold_result = if is_ceo {
        provision_agent_home_root(&paths, &agent.company_id, &agent.slug).map(|_| ())
    } else {
        scaffold_agent_home(
            &paths,
            &agent.company_id,
            &agent.name,
            &agent.slug,
            &company_name,
            &agent.role,
        )
    };

    if let Err(error) = scaffold_result {
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

pub async fn create_agent_hire(
    db: &AsyncDatabase,
    paths: &Paths,
    input: CreateAgentHireInput,
) -> BoardResult<Agent> {
    let paths = paths.clone();
    let db_paths = paths.clone();
    let company_id = require_name(&input.company_id, "company_id")?;
    let name = require_name(&input.name, "agent name")?;
    let role = input.role.unwrap_or_else(|| "general".to_string());
    if role == "ceo" {
        return Err(BoardError::InvalidInput(
            "CEO agents must be created through the dedicated onboarding flow".to_string(),
        ));
    }

    let status_requires_approval = get_company(db, &company_id)
        .await?
        .map(|company| company.require_board_approval_for_new_agents)
        .unwrap_or(true);
    let desired_status = if status_requires_approval {
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
    let requested_by_agent_id = normalize_optional_string(input.requested_by_agent_id);
    let requested_by_user_id =
        normalize_optional_string(input.requested_by_user_id).or_else(|| {
            if requested_by_agent_id.is_none() {
                Some(LOCAL_BOARD_USER_ID.to_string())
            } else {
                None
            }
        });
    let requested_by_run_id = normalize_optional_string(input.requested_by_run_id);
    let source_issue_ids = normalize_issue_id_list(input.source_issue_id, input.source_issue_ids);

    let created = db
        .call_with_operation("board.agent_hire.create", move |conn| {
            let tx = conn.unchecked_transaction()?;
            ensure_local_board_user(&tx, &now)?;

            let company = get_company_sync(&tx, &company_id)?
                .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;
            if let Some(requested_by_agent_id) = requested_by_agent_id.as_deref() {
                validate_company_agent_sync(
                    &tx,
                    &company_id,
                    requested_by_agent_id,
                    "requested_by_agent_id",
                )?;
            }
            validate_issue_ids_for_company_sync(&tx, &company_id, &source_issue_ids)?;

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

            let (actor_type, actor_id) =
                activity_actor(requested_by_agent_id.as_deref(), requested_by_user_id.as_deref());
            insert_activity_sync(
                &tx,
                &company.id,
                actor_type,
                actor_id,
                "agent.hire_created",
                "agent",
                &agent_id,
                Some(&agent_id),
                Some(json!({
                    "name": name,
                    "role": role,
                    "status": desired_status,
                    "slug": slug,
                    "source_issue_ids": source_issue_ids,
                    "requested_by_run_id": requested_by_run_id,
                })),
                &now,
            )?;

            let approval_id = if desired_status == "pending_approval" {
                let approval_id = Uuid::new_v4().to_string();
                let approval_payload = json!({
                    "agent_id": agent_id,
                    "agent_name": name,
                    "agent_role": role,
                    "agent_title": description_title,
                    "agent_icon": icon,
                    "agent_slug": slug,
                    "reports_to": reports_to,
                    "capabilities": capabilities,
                    "adapter_type": adapter_type,
                    "adapter_config": adapter_config,
                    "runtime_config": runtime_config,
                    "budget_monthly_cents": budget,
                    "permissions": permissions,
                    "metadata": metadata,
                    "requested_by_agent_id": requested_by_agent_id,
                    "requested_by_user_id": requested_by_user_id,
                    "requested_by_run_id": requested_by_run_id,
                    "source_issue_id": source_issue_ids.first().cloned(),
                    "source_issue_ids": source_issue_ids,
                });
                tx.execute(
                    "INSERT INTO approvals (
                        id, company_id, type, requested_by_agent_id, requested_by_user_id, status,
                        payload, created_at, updated_at
                     ) VALUES (?1, ?2, 'hire_agent', ?3, ?4, 'pending', ?5, ?6, ?6)",
                    params![
                        approval_id,
                        company_id,
                        requested_by_agent_id,
                        requested_by_user_id,
                        approval_payload.to_string(),
                        now,
                    ],
                )?;

                for issue_id in &source_issue_ids {
                    tx.execute(
                        "INSERT OR IGNORE INTO issue_approvals (
                            company_id, issue_id, approval_id, linked_by_agent_id, linked_by_user_id, created_at
                         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                        params![
                            company_id,
                            issue_id,
                            approval_id,
                            requested_by_agent_id,
                            requested_by_user_id,
                            now,
                        ],
                    )?;
                }

                insert_activity_sync(
                    &tx,
                    &company.id,
                    actor_type,
                    actor_id,
                    "approval.created",
                    "approval",
                    &approval_id,
                    Some(&agent_id),
                    Some(json!({
                        "type": "hire_agent",
                        "agent_id": agent_id,
                        "source_issue_ids": source_issue_ids,
                    })),
                    &now,
                )?;

                Some(approval_id)
            } else {
                None
            };

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
            Ok((agent, approval_id))
        })
        .await?;

    let (agent, approval_id) = created;
    if agent.status != "pending_approval" {
        let company_name = get_company(db, &agent.company_id)
            .await?
            .map(|company| company.name)
            .unwrap_or_default();
        let scaffold_result = scaffold_agent_home(
            &paths,
            &agent.company_id,
            &agent.name,
            &agent.slug,
            &company_name,
            &agent.role,
        );

        if let Err(error) = scaffold_result {
            let agent_id = agent.id.clone();
            db.call_with_operation(
                "board.agent_hire.rollback_after_scaffold_failure",
                move |conn| {
                    let tx = conn.unchecked_transaction()?;
                    if let Some(approval_id) = approval_id {
                        tx.execute("DELETE FROM approvals WHERE id = ?1", params![approval_id])?;
                    }
                    tx.execute("DELETE FROM agents WHERE id = ?1", params![agent_id])?;
                    tx.commit()?;
                    Ok(())
                },
            )
            .await?;
            let _ = fs::remove_dir_all(paths.agent_home_dir(&agent.company_id, &agent.slug));
            return Err(error);
        }
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

pub async fn delete_project(db: &AsyncDatabase, project_id: &str) -> BoardResult<Project> {
    let project_id = require_name(project_id, "project_id")?;
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.project.delete", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let project = get_project_sync(&tx, &project_id)?
                .ok_or_else(|| DatabaseError::NotFound("Project not found".to_string()))?;

            tx.execute(
                "DELETE FROM workspace_runtime_services
                 WHERE project_id = ?1
                    OR project_workspace_id IN (
                        SELECT id FROM project_workspaces WHERE project_id = ?1
                    )
                    OR issue_id IN (
                        SELECT id FROM issues WHERE project_id = ?1
                    )",
                params![project_id],
            )?;

            let session_ids = {
                let mut stmt = tx.prepare(
                    "SELECT id
                     FROM agent_coding_sessions
                     WHERE project_id = ?1
                        OR issue_id IN (
                            SELECT id FROM issues WHERE project_id = ?1
                        )",
                )?;
                let rows = stmt.query_map(params![project_id], |row| row.get::<_, String>(0))?;
                rows.collect::<Result<Vec<_>, _>>()?
            };

            for session_id in session_ids {
                tx.execute(
                    "DELETE FROM agent_coding_sessions WHERE id = ?1",
                    params![session_id],
                )?;
            }

            tx.execute(
                "DELETE FROM issues WHERE project_id = ?1",
                params![project_id],
            )?;

            tx.execute("DELETE FROM projects WHERE id = ?1", params![project_id])?;

            insert_activity_sync(
                &tx,
                &project.company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "project.deleted",
                "project",
                &project.id,
                project.lead_agent_id.as_deref(),
                Some(json!({ "name": project.name.clone() })),
                &now,
            )?;

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
    let status = input.status.unwrap_or_else(|| "todo".to_string());
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
            if let Some(agent_id) = assignee_agent_id.as_deref() {
                validate_assignable_agent_sync(&tx, &company_id, agent_id, "assignee_agent_id")?;
            }
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

pub async fn update_issue(db: &AsyncDatabase, input: UpdateIssueInput) -> BoardResult<Issue> {
    let issue_id = require_name(&input.issue_id, "issue_id")?;
    let title = match input.title {
        Some(value) => Some(require_name(&value, "issue title")?),
        None => None,
    };
    let description = normalize_optional_update(input.description);
    let status = input.status.map(|value| value.trim().to_string());
    let priority = input.priority.map(|value| value.trim().to_string());
    let project_id = normalize_optional_update(input.project_id);
    let parent_id = normalize_optional_update(input.parent_id);
    let assignee_agent_id = normalize_optional_update(input.assignee_agent_id);
    let assignee_user_id = normalize_optional_update(input.assignee_user_id);
    let execution_workspace_settings = input.execution_workspace_settings;
    let hidden_at = normalize_optional_update(input.hidden_at);
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.issue.update", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let current = get_issue_sync(&tx, &issue_id)?
                .ok_or_else(|| DatabaseError::NotFound("Issue not found".to_string()))?;

            let next_title = title.unwrap_or_else(|| current.title.clone());
            let next_description = description.unwrap_or_else(|| current.description.clone());
            let next_status = status
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| current.status.clone());
            let next_priority = priority
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| current.priority.clone());
            let next_project_id = project_id.unwrap_or_else(|| current.project_id.clone());
            let next_parent_id = parent_id.unwrap_or_else(|| current.parent_id.clone());
            let next_assignee_agent_id = assignee_agent_id.unwrap_or_else(|| current.assignee_agent_id.clone());
            let next_assignee_user_id = assignee_user_id.unwrap_or_else(|| current.assignee_user_id.clone());
            let next_execution_workspace_settings = execution_workspace_settings
                .unwrap_or_else(|| current.execution_workspace_settings.clone());
            let next_hidden_at = hidden_at.unwrap_or_else(|| current.hidden_at.clone());

            if next_parent_id.as_deref() == Some(issue_id.as_str()) {
                return Err(DatabaseError::InvalidData(
                    "An issue cannot be its own parent".to_string(),
                )
                .into());
            }
            if let Some(parent_id) = next_parent_id.as_deref() {
                if issue_has_descendant_sync(&tx, &issue_id, parent_id)? {
                    return Err(DatabaseError::InvalidData(
                        "An issue cannot move under one of its descendants".to_string(),
                    )
                    .into());
                }
            }

            let next_request_depth = if let Some(parent_id) = next_parent_id.as_ref() {
                tx.query_row(
                    "SELECT COALESCE(request_depth, 0) + 1 FROM issues WHERE id = ?1 AND company_id = ?2",
                    params![parent_id, current.company_id],
                    |row| row.get::<_, i64>(0),
                )?
            } else {
                0
            };
            let depth_delta = next_request_depth - current.request_depth;
            if let Some(agent_id) = next_assignee_agent_id.as_deref() {
                validate_assignable_agent_sync(
                    &tx,
                    &current.company_id,
                    agent_id,
                    "assignee_agent_id",
                )?;
            }
            let execution_agent_name_key = if let Some(agent_id) = next_assignee_agent_id.as_ref() {
                tx.query_row(
                    "SELECT slug FROM agents WHERE id = ?1 AND company_id = ?2",
                    params![agent_id, current.company_id],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
            } else {
                None
            };
            let started_at = if next_status == "in_progress" {
                current.started_at.clone().or_else(|| Some(now.clone()))
            } else {
                current.started_at.clone()
            };
            let completed_at = if next_status == "done" {
                current.completed_at.clone().or_else(|| Some(now.clone()))
            } else {
                None
            };
            let cancelled_at = if next_status == "cancelled" {
                current.cancelled_at.clone().or_else(|| Some(now.clone()))
            } else {
                None
            };

            tx.execute(
                "UPDATE issues
                 SET title = ?1,
                     description = ?2,
                     status = ?3,
                     priority = ?4,
                     project_id = ?5,
                     parent_id = ?6,
                     assignee_agent_id = ?7,
                     assignee_user_id = ?8,
                     execution_agent_name_key = ?9,
                     execution_workspace_settings = ?10,
                     request_depth = ?11,
                     started_at = ?12,
                     completed_at = ?13,
                     cancelled_at = ?14,
                     hidden_at = ?15,
                     updated_at = ?16
                 WHERE id = ?17",
                params![
                    next_title,
                    next_description,
                    next_status,
                    next_priority,
                    next_project_id,
                    next_parent_id,
                    next_assignee_agent_id,
                    next_assignee_user_id,
                    execution_agent_name_key,
                    next_execution_workspace_settings.as_ref().map(Value::to_string),
                    next_request_depth,
                    started_at,
                    completed_at,
                    cancelled_at,
                    next_hidden_at,
                    now,
                    issue_id,
                ],
            )?;

            shift_issue_subtree_depths_sync(&tx, &issue_id, depth_delta)?;

            insert_activity_sync(
                &tx,
                &current.company_id,
                "system",
                LOCAL_BOARD_USER_ID,
                "issue.updated",
                "issue",
                &issue_id,
                next_assignee_agent_id.as_deref(),
                Some(json!({
                    "status": next_status,
                    "priority": next_priority,
                    "project_id": next_project_id,
                    "parent_id": next_parent_id,
                    "assignee_agent_id": next_assignee_agent_id,
                    "execution_workspace_settings": next_execution_workspace_settings,
                    "hidden_at": next_hidden_at,
                })),
                &now,
            )?;

            let issue = get_issue_sync(&tx, &issue_id)?
                .ok_or_else(|| DatabaseError::NotFound("Issue missing after update".to_string()))?;
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
                "SELECT
                    id, company_id, issue_id, author_agent_id, author_user_id,
                    target_agent_id, body, created_at, updated_at
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

pub async fn list_issue_attachments(
    db: &AsyncDatabase,
    paths: &Paths,
    issue_id: &str,
) -> BoardResult<Vec<IssueAttachment>> {
    let issue_id = issue_id.to_string();
    let paths = paths.clone();
    Ok(db
        .call_with_operation("board.issue.attachment.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    ia.id, ia.company_id, ia.issue_id, ia.asset_id, ia.issue_comment_id,
                    a.provider, a.object_key, a.content_type, a.byte_size, a.sha256,
                    a.original_filename, a.created_by_agent_id, a.created_by_user_id,
                    ia.created_at, ia.updated_at
                 FROM issue_attachments ia
                 JOIN assets a ON a.id = ia.asset_id
                 WHERE ia.issue_id = ?1
                 ORDER BY ia.created_at ASC",
            )?;
            let attachments = stmt
                .query_map(params![issue_id], |row| {
                    row_to_issue_attachment(row, &paths)
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(attachments)
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
    let target_agent_id = normalize_optional_string(input.target_agent_id);
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.issue.comment.add", move |conn| {
            let tx = conn.unchecked_transaction()?;
            if let Some(agent_id) = target_agent_id.as_deref() {
                validate_assignable_agent_sync(&tx, &company_id, agent_id, "target_agent_id")?;
            }
            let comment_id = Uuid::new_v4().to_string();
            tx.execute(
                "INSERT INTO issue_comments (
                    id, company_id, issue_id, author_agent_id, author_user_id,
                    target_agent_id, body, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
                params![
                    comment_id,
                    company_id,
                    issue_id,
                    author_agent_id,
                    author_user_id,
                    target_agent_id,
                    body,
                    now,
                ],
            )?;

            insert_activity_sync(
                &tx,
                &company_id,
                if author_agent_id.is_some() {
                    "agent"
                } else {
                    "user"
                },
                author_agent_id.as_deref().unwrap_or(LOCAL_BOARD_USER_ID),
                "issue.comment_added",
                "issue_comment",
                &comment_id,
                author_agent_id.as_deref(),
                Some(json!({
                    "issue_id": issue_id,
                    "target_agent_id": target_agent_id,
                })),
                &now,
            )?;

            let comment = tx
                .query_row(
                    "SELECT
                        id, company_id, issue_id, author_agent_id, author_user_id,
                        target_agent_id, body, created_at, updated_at
                     FROM issue_comments
                     WHERE id = ?1",
                    params![comment_id],
                    row_to_issue_comment,
                )
                .optional()?
                .ok_or_else(|| {
                    DatabaseError::NotFound("Comment missing after insert".to_string())
                })?;
            tx.commit()?;
            Ok(comment)
        })
        .await?)
}

pub async fn add_issue_attachment(
    db: &AsyncDatabase,
    paths: &Paths,
    input: AddIssueAttachmentInput,
) -> BoardResult<IssueAttachment> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let issue_id = require_name(&input.issue_id, "issue_id")?;
    let local_file_path = require_name(&input.local_file_path, "local_file_path")?;
    let issue_comment_id = normalize_optional_string(input.issue_comment_id);
    let created_by_agent_id = normalize_optional_string(input.created_by_agent_id);
    let created_by_user_id = normalize_optional_string(input.created_by_user_id)
        .or_else(|| Some(LOCAL_BOARD_USER_ID.to_string()));
    let now = now_rfc3339();

    let source_path = PathBuf::from(&local_file_path);
    if !source_path.is_file() {
        return Err(BoardError::InvalidInput(format!(
            "Attachment file does not exist: {local_file_path}"
        )));
    }

    let attachment_bytes = fs::read(&source_path)?;
    let byte_size = attachment_bytes.len() as i64;
    let sha256 = format!("{:x}", Sha256::digest(&attachment_bytes));
    let original_filename = source_path
        .file_name()
        .and_then(|value| value.to_str())
        .map(ToOwned::to_owned)
        .filter(|value| !value.is_empty());
    let attachment_id = Uuid::new_v4().to_string();
    let asset_id = Uuid::new_v4().to_string();
    let object_key = format!(
        "{issue_id}/{attachment_id}-{}",
        sanitize_attachment_filename(original_filename.as_deref().unwrap_or("attachment"))
    );
    let target_path = paths.company_attachment_file(&company_id, &object_key);
    let content_type = guess_content_type(
        original_filename
            .as_deref()
            .or_else(|| source_path.extension().and_then(|value| value.to_str())),
    );

    if let Some(parent) = target_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::create_dir_all(paths.company_assets_dir(&company_id))?;
    fs::write(&target_path, &attachment_bytes)?;

    let persisted = db
        .call_with_operation("board.issue.attachment.add", {
            let company_id = company_id.clone();
            let issue_id = issue_id.clone();
            let issue_comment_id = issue_comment_id.clone();
            let created_by_agent_id = created_by_agent_id.clone();
            let created_by_user_id = created_by_user_id.clone();
            let object_key = object_key.clone();
            let content_type = content_type.clone();
            let sha256 = sha256.clone();
            let original_filename = original_filename.clone();
            let attachment_id = attachment_id.clone();
            let asset_id = asset_id.clone();
            let now = now.clone();
            let paths = paths.clone();
            move |conn| {
                let tx = conn.unchecked_transaction()?;
                ensure_issue_exists_sync(&tx, &company_id, &issue_id)?;

                if let Some(comment_id) = issue_comment_id.as_deref() {
                    let valid_comment = tx
                        .query_row(
                            "SELECT 1
                             FROM issue_comments
                             WHERE id = ?1 AND company_id = ?2 AND issue_id = ?3",
                            params![comment_id, company_id, issue_id],
                            |row| row.get::<_, i64>(0),
                        )
                        .optional()?;
                    if valid_comment.is_none() {
                        return Err(DatabaseError::InvalidData(
                            "issue_comment_id must belong to the same issue".to_string(),
                        ));
                    }
                }

                if let Some(agent_id) = created_by_agent_id.as_deref() {
                    validate_company_agent_sync(&tx, &company_id, agent_id, "created_by_agent_id")?;
                }

                tx.execute(
                    "INSERT INTO assets (
                        id, company_id, provider, object_key, content_type, byte_size, sha256,
                        original_filename, created_by_agent_id, created_by_user_id, created_at, updated_at
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)",
                    params![
                        asset_id,
                        company_id,
                        "local_file",
                        object_key,
                        content_type,
                        byte_size,
                        sha256,
                        original_filename,
                        created_by_agent_id,
                        created_by_user_id,
                        now,
                    ],
                )?;

                tx.execute(
                    "INSERT INTO issue_attachments (
                        id, company_id, issue_id, asset_id, issue_comment_id, created_at, updated_at
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
                    params![
                        attachment_id,
                        company_id,
                        issue_id,
                        asset_id,
                        issue_comment_id,
                        now,
                    ],
                )?;

                insert_activity_sync(
                    &tx,
                    &company_id,
                    if created_by_agent_id.is_some() { "agent" } else { "user" },
                    created_by_agent_id
                        .as_deref()
                        .or(created_by_user_id.as_deref())
                        .unwrap_or(LOCAL_BOARD_USER_ID),
                    "issue.attachment_added",
                    "issue_attachment",
                    &attachment_id,
                    created_by_agent_id.as_deref(),
                    Some(json!({
                        "issue_id": issue_id,
                        "asset_id": asset_id,
                        "original_filename": original_filename,
                        "content_type": content_type,
                        "byte_size": byte_size,
                    })),
                    &now,
                )?;

                let attachment = tx
                    .query_row(
                        "SELECT
                            ia.id, ia.company_id, ia.issue_id, ia.asset_id, ia.issue_comment_id,
                            a.provider, a.object_key, a.content_type, a.byte_size, a.sha256,
                            a.original_filename, a.created_by_agent_id, a.created_by_user_id,
                            ia.created_at, ia.updated_at
                         FROM issue_attachments ia
                         JOIN assets a ON a.id = ia.asset_id
                         WHERE ia.id = ?1",
                        params![attachment_id],
                        |row| row_to_issue_attachment(row, &paths),
                    )
                    .optional()?
                    .ok_or_else(|| {
                        DatabaseError::NotFound("Attachment missing after insert".to_string())
                    })?;

                tx.commit()?;
                Ok(attachment)
            }
        })
        .await;

    match persisted {
        Ok(attachment) => Ok(attachment),
        Err(error) => {
            let _ = fs::remove_file(&target_path);
            Err(error.into())
        }
    }
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
    paths: &Paths,
    input: ApprovalDecisionInput,
) -> BoardResult<Approval> {
    let paths = paths.clone();
    let approval_id = require_name(&input.approval_id, "approval_id")?;
    let decided_by_user_id = normalize_optional_string(input.decided_by_user_id)
        .unwrap_or_else(|| LOCAL_BOARD_USER_ID.to_string());
    let decision_note = normalize_optional_string(input.decision_note);
    let now = now_rfc3339();
    let activation_target = db
        .call_with_operation("board.approval.approve.load_activation_target", {
            let approval_id = approval_id.clone();
            move |conn| load_hire_approval_activation_target_sync(conn, &approval_id)
        })
        .await?;
    let prepared_activation = activation_target
        .as_ref()
        .map(|target| prepare_hire_approval_activation(&paths, target))
        .transpose()?;

    let approval_result = db
        .call_with_operation("board.approval.approve", {
            let approval_id = approval_id.clone();
            let decided_by_user_id = decided_by_user_id.clone();
            let decision_note = decision_note.clone();
            let now = now.clone();
            let activation_target = activation_target.clone();
            move |conn| {
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

                if let Some(target) = activation_target.as_ref() {
                    tx.execute(
                        "UPDATE agents SET status = 'idle', updated_at = ?1 WHERE id = ?2",
                        params![now, target.agent_id],
                    )?;

                    insert_activity_sync(
                        &tx,
                        &target.company_id,
                        "system",
                        "hire_hook",
                        "hire_hook.succeeded",
                        "agent",
                        &target.agent_id,
                        Some(&target.agent_id),
                        Some(json!({
                            "source": "approval",
                            "source_id": target.approval_id,
                            "adapter_type": target.adapter_type,
                        })),
                        &now,
                    )?;
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
            }
        })
        .await;

    match approval_result {
        Ok(approval) => Ok(approval),
        Err(error) => {
            if let Some(prepared_activation) = prepared_activation.as_ref() {
                rollback_prepared_hire_activation(prepared_activation);
            }
            Err(error.into())
        }
    }
}

pub async fn create_agent_decision_approval(
    db: &AsyncDatabase,
    input: CreateAgentDecisionApprovalInput,
) -> BoardResult<Approval> {
    let company_id = require_name(&input.company_id, "company_id")?;
    let requested_by_agent_id =
        require_name(&input.requested_by_agent_id, "requested_by_agent_id")?;
    let requested_by_run_id = require_name(&input.requested_by_run_id, "requested_by_run_id")?;
    let request_key = require_name(&input.request_key, "request_key")?;
    let question = require_name(&input.question, "question")?;
    let requested_by_user_id = normalize_optional_string(input.requested_by_user_id);
    let provider = normalize_optional_string(input.provider);
    let provider_request_id = normalize_optional_string(input.provider_request_id);
    let source_issue_ids = normalize_issue_id_list(input.source_issue_id, input.source_issue_ids);
    let options = normalize_string_list(input.options);
    let questions = input.questions;
    let raw_request = input.raw_request;
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.approval.create_agent_decision", move |conn| {
            let tx = conn.unchecked_transaction()?;
            ensure_local_board_user(&tx, &now)?;

            if let Some(existing) = tx
                .query_row(
                    "SELECT
                        id, company_id, type, requested_by_agent_id, requested_by_user_id,
                        status, payload, decision_note, decided_by_user_id, decided_at,
                        created_at, updated_at
                     FROM approvals
                     WHERE company_id = ?1
                       AND type = 'agent_decision'
                       AND status = 'pending'
                       AND json_extract(payload, '$.request_key') = ?2
                     ORDER BY created_at DESC
                     LIMIT 1",
                    params![company_id, request_key],
                    row_to_approval,
                )
                .optional()?
            {
                tx.rollback()?;
                return Ok(existing);
            }

            let approval_id = Uuid::new_v4().to_string();
            let payload = json!({
                "source_issue_id": source_issue_ids.first().cloned(),
                "source_issue_ids": source_issue_ids.clone(),
                "requested_by_run_id": requested_by_run_id.clone(),
                "requested_by_agent_id": requested_by_agent_id.clone(),
                "provider": provider.clone(),
                "provider_request_id": provider_request_id.clone(),
                "request_key": request_key.clone(),
                "question": question.clone(),
                "options": options.clone(),
                "questions": questions.clone(),
                "raw_request": raw_request.clone(),
            });
            tx.execute(
                "INSERT INTO approvals (
                    id, company_id, type, requested_by_agent_id, requested_by_user_id, status,
                    payload, created_at, updated_at
                 ) VALUES (?1, ?2, 'agent_decision', ?3, ?4, 'pending', ?5, ?6, ?6)",
                params![
                    approval_id,
                    company_id,
                    requested_by_agent_id,
                    requested_by_user_id,
                    payload.to_string(),
                    now,
                ],
            )?;

            for issue_id in &source_issue_ids {
                tx.execute(
                    "INSERT OR IGNORE INTO issue_approvals (
                        company_id, issue_id, approval_id, linked_by_agent_id, linked_by_user_id, created_at
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![
                        company_id,
                        issue_id,
                        approval_id,
                        requested_by_agent_id,
                        requested_by_user_id,
                        now,
                    ],
                )?;
            }

            let (actor_type, actor_id) =
                activity_actor(Some(requested_by_agent_id.as_str()), requested_by_user_id.as_deref());
            insert_activity_sync(
                &tx,
                &company_id,
                actor_type,
                actor_id,
                "approval.created",
                "approval",
                &approval_id,
                Some(&requested_by_agent_id),
                Some(json!({
                    "type": "agent_decision",
                    "requested_by_run_id": requested_by_run_id,
                    "question": question,
                    "source_issue_ids": source_issue_ids,
                })),
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
                .ok_or_else(|| {
                    DatabaseError::NotFound("Approval missing after insert".to_string())
                })?;
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

pub async fn list_agent_runs(
    db: &AsyncDatabase,
    agent_id: &str,
    limit: Option<i64>,
) -> BoardResult<Vec<AgentRun>> {
    let agent_id = agent_id.to_string();
    let limit = limit.unwrap_or(100).clamp(1, 500);
    Ok(db
        .call_with_operation("board.agent_run.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, agent_id, issue_id, invocation_source,
                    trigger_detail, wake_reason, status, started_at, finished_at,
                    error, wakeup_request_id, exit_code, signal, usage_json,
                    result_json, session_id_before, session_id_after, log_store,
                    log_ref, log_bytes, log_sha256, log_compressed, stdout_excerpt,
                    stderr_excerpt, error_code, external_run_id, context_snapshot,
                    created_at, updated_at
                 FROM agent_runs
                 WHERE agent_id = ?1
                 ORDER BY created_at DESC
                 LIMIT ?2",
            )?;
            let rows = stmt
                .query_map(params![agent_id, limit], row_to_agent_run)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .await?)
}

pub async fn list_agent_live_run_counts(
    db: &AsyncDatabase,
    company_id: &str,
) -> BoardResult<Vec<AgentLiveRunCount>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.agent_run.live_counts", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    a.id,
                    COUNT(r.id) AS live_count
                 FROM agents a
                 LEFT JOIN agent_runs r
                   ON r.agent_id = a.id
                  AND r.status = 'running'
                 WHERE a.company_id = ?1
                 GROUP BY a.id
                 ORDER BY a.created_at ASC",
            )?;
            let rows = stmt
                .query_map(params![company_id], |row| {
                    Ok(AgentLiveRunCount {
                        agent_id: row.get(0)?,
                        live_count: row.get(1)?,
                    })
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .await?)
}

pub async fn list_issue_runs(
    db: &AsyncDatabase,
    issue_id: &str,
    limit: Option<i64>,
) -> BoardResult<Vec<AgentRun>> {
    let issue_id = issue_id.to_string();
    let limit = limit.unwrap_or(100).clamp(1, 500);
    Ok(db
        .call_with_operation("board.issue.run.list", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, agent_id, issue_id, invocation_source,
                    trigger_detail, wake_reason, status, started_at, finished_at,
                    error, wakeup_request_id, exit_code, signal, usage_json,
                    result_json, session_id_before, session_id_after, log_store,
                    log_ref, log_bytes, log_sha256, log_compressed, stdout_excerpt,
                    stderr_excerpt, error_code, external_run_id, context_snapshot,
                    created_at, updated_at
                 FROM agent_runs
                 WHERE issue_id = ?1
                 ORDER BY created_at DESC
                 LIMIT ?2",
            )?;
            let rows = stmt
                .query_map(params![issue_id, limit], row_to_agent_run)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .await?)
}

pub async fn list_issue_run_card_updates(
    db: &AsyncDatabase,
    company_id: &str,
) -> BoardResult<Vec<IssueRunCardUpdate>> {
    let company_id = company_id.to_string();
    Ok(db
        .call_with_operation("board.issue.run.card_updates", move |conn| {
            let rows = {
                let mut stmt = conn.prepare(
                    "SELECT
                        i.id,
                        i.status,
                        r.id,
                        r.agent_id,
                        r.status,
                        r.result_json,
                        r.stdout_excerpt,
                        r.stderr_excerpt,
                        r.updated_at
                     FROM issues i
                     JOIN agent_runs r
                       ON r.id = COALESCE(i.execution_run_id, i.checkout_run_id)
                     WHERE i.company_id = ?1
                       AND COALESCE(i.execution_run_id, i.checkout_run_id) IS NOT NULL
                     ORDER BY i.updated_at DESC, i.created_at DESC",
                )?;
                let rows = stmt
                    .query_map(params![company_id], row_to_issue_run_card_update_row)?
                    .collect::<Result<Vec<_>, _>>()?;
                rows
            };

            if rows.is_empty() {
                return Ok(Vec::new());
            }

            let run_ids = rows
                .iter()
                .map(|row| row.run_id.clone())
                .collect::<Vec<_>>();
            let events_by_run = list_recent_events_for_run_ids(conn, &run_ids, 8)?;

            Ok(rows
                .into_iter()
                .map(|row| {
                    let summary = summarize_issue_run_card_update(
                        &row.run_status,
                        events_by_run
                            .get(&row.run_id)
                            .map(Vec::as_slice)
                            .unwrap_or(&[]),
                        row.result_json.as_ref(),
                        row.stdout_excerpt.as_deref(),
                        row.stderr_excerpt.as_deref(),
                    );
                    let last_event = events_by_run
                        .get(&row.run_id)
                        .and_then(|events| events.first());

                    IssueRunCardUpdate {
                        issue_id: row.issue_id,
                        issue_status: row.issue_status,
                        run_id: row.run_id,
                        agent_id: row.agent_id,
                        run_status: row.run_status,
                        summary: Some(summary),
                        last_event_type: last_event.map(|event| event.event_type.clone()),
                        last_activity_at: last_event
                            .map(|event| event.created_at.clone())
                            .unwrap_or(row.run_updated_at),
                    }
                })
                .collect())
        })
        .await?)
}

pub async fn get_agent_run(db: &AsyncDatabase, run_id: &str) -> BoardResult<Option<AgentRun>> {
    let run_id = run_id.to_string();
    Ok(db
        .call_with_operation("board.agent_run.get", move |conn| {
            conn.query_row(
                "SELECT
                    id, company_id, agent_id, issue_id, invocation_source,
                    trigger_detail, wake_reason, status, started_at, finished_at,
                    error, wakeup_request_id, exit_code, signal, usage_json,
                    result_json, session_id_before, session_id_after, log_store,
                    log_ref, log_bytes, log_sha256, log_compressed, stdout_excerpt,
                    stderr_excerpt, error_code, external_run_id, context_snapshot,
                    created_at, updated_at
                 FROM agent_runs
                 WHERE id = ?1",
                params![run_id],
                row_to_agent_run,
            )
            .optional()
            .map_err(Into::into)
        })
        .await?)
}

pub async fn list_agent_run_events(
    db: &AsyncDatabase,
    run_id: &str,
    after_seq: Option<i64>,
    limit: Option<i64>,
) -> BoardResult<Vec<AgentRunEvent>> {
    let run_id = run_id.to_string();
    let after_seq = after_seq.unwrap_or(0);
    let limit = limit.unwrap_or(200).clamp(1, 1000);
    Ok(db
        .call_with_operation("board.agent_run.events", move |conn| {
            let mut stmt = conn.prepare(
                "SELECT
                    id, company_id, run_id, agent_id, seq, event_type, stream, level,
                    color, message, payload, created_at
                 FROM agent_run_events
                 WHERE run_id = ?1 AND seq > ?2
                 ORDER BY seq ASC
                 LIMIT ?3",
            )?;
            let rows = stmt
                .query_map(params![run_id, after_seq, limit], row_to_agent_run_event)?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
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
                agent_id: assignee_agent_id,
                repository_id: repository.0,
                repo_path: cwd,
                repo_branch: primary.repo_ref.or(repository.1),
                title,
            })
        })
        .await?;

    let (issue, agent_id, repository_id, repo_path, repo_branch, title) = match ctx {
        StartWorkspaceContext::Existing(workspace) => return Ok(workspace),
        StartWorkspaceContext::Create {
            issue,
            agent_id,
            repository_id,
            repo_path,
            repo_branch,
            title,
            ..
        } => (
            issue,
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
            provider: None,
            provider_session_id: None,
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        })
        .map_err(|error| BoardError::Runtime(error.to_string()))?;

    let session_id = session.id.as_str().to_string();
    let workspace_repo_path = session.worktree_path.unwrap_or(repo_path);
    attach_issue_workspace_session(
        db,
        &issue.id,
        &session_id,
        &workspace_repo_path,
        repo_branch,
    )
    .await
}

pub async fn attach_issue_workspace_session(
    db: &AsyncDatabase,
    issue_id: &str,
    session_id: &str,
    workspace_repo_path: &str,
    workspace_branch: Option<String>,
) -> BoardResult<Workspace> {
    let issue_id = require_name(issue_id, "issue_id")?;
    let session_id = require_name(session_id, "session_id")?;
    let workspace_repo_path = require_name(workspace_repo_path, "workspace_repo_path")?;
    let now = now_rfc3339();

    Ok(db
        .call_with_operation("board.workspace.start.persist", move |conn| {
            let tx = conn.unchecked_transaction()?;
            let issue = get_issue_sync(&tx, &issue_id)?
                .ok_or_else(|| DatabaseError::NotFound("Issue not found".to_string()))?;
            let project_id = issue.project_id.clone().ok_or_else(|| {
                DatabaseError::InvalidData("Issue must belong to a project".to_string())
            })?;
            let agent_id = issue.assignee_agent_id.clone().ok_or_else(|| {
                DatabaseError::InvalidData("Issue must be assigned to an agent".to_string())
            })?;
            let company_id = issue.company_id.clone();
            let issue_row_id = issue.id.clone();
            let issue_identifier = issue.identifier.clone();

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
                    company_id.clone(),
                    project_id.clone(),
                    issue_row_id.clone(),
                    agent_id.clone(),
                    workspace_repo_path.clone(),
                    workspace_branch.clone(),
                    json!({
                        "issue_id": issue_row_id.clone(),
                        "issue_identifier": issue_identifier.clone(),
                        "project_id": project_id.clone(),
                        "agent_id": agent_id.clone(),
                    })
                    .to_string(),
                    now.clone(),
                    session_id.clone(),
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
                    company_id.clone(),
                    agent_id.clone(),
                    format!("issue:{}", issue_row_id.clone()),
                    json!({ "session_id": session_id.clone(), "issue_id": issue_row_id.clone() })
                        .to_string(),
                    issue_identifier.clone(),
                    now.clone(),
                ],
            )?;

            tx.execute(
                "UPDATE issues
                 SET started_at = COALESCE(started_at, ?1),
                     updated_at = ?1
                 WHERE id = ?2",
                params![now.clone(), issue_row_id.clone()],
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
                    "issue_id": issue_row_id,
                    "project_id": project_id,
                    "repo_path": workspace_repo_path,
                })),
                &now,
            )?;

            let workspace = tx
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

fn get_agent_sync(conn: &Connection, agent_id: &str) -> rusqlite::Result<Option<Agent>> {
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
        target_agent_id: row.get(5)?,
        body: row.get(6)?,
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
    })
}

fn row_to_issue_attachment(row: &Row<'_>, paths: &Paths) -> rusqlite::Result<IssueAttachment> {
    let company_id: String = row.get(1)?;
    let object_key: String = row.get(6)?;
    let local_path = paths
        .company_attachment_file(&company_id, &object_key)
        .to_string_lossy()
        .to_string();

    Ok(IssueAttachment {
        id: row.get(0)?,
        company_id,
        issue_id: row.get(2)?,
        asset_id: row.get(3)?,
        issue_comment_id: row.get(4)?,
        provider: row.get(5)?,
        object_key,
        content_type: row.get(7)?,
        byte_size: row.get(8)?,
        sha256: row.get(9)?,
        original_filename: row.get(10)?,
        created_by_agent_id: row.get(11)?,
        created_by_user_id: row.get(12)?,
        local_path,
        created_at: row.get(13)?,
        updated_at: row.get(14)?,
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

#[derive(Debug, Clone)]
struct IssueRunCardUpdateRow {
    issue_id: String,
    issue_status: String,
    run_id: String,
    agent_id: String,
    run_status: String,
    result_json: Option<Value>,
    stdout_excerpt: Option<String>,
    stderr_excerpt: Option<String>,
    run_updated_at: String,
}

fn row_to_issue_run_card_update_row(row: &Row<'_>) -> rusqlite::Result<IssueRunCardUpdateRow> {
    Ok(IssueRunCardUpdateRow {
        issue_id: row.get(0)?,
        issue_status: row.get(1)?,
        run_id: row.get(2)?,
        agent_id: row.get(3)?,
        run_status: row.get(4)?,
        result_json: row.get::<_, Option<String>>(5)?.map(parse_json),
        stdout_excerpt: row.get(6)?,
        stderr_excerpt: row.get(7)?,
        run_updated_at: row.get(8)?,
    })
}

fn row_to_agent_run(row: &Row<'_>) -> rusqlite::Result<AgentRun> {
    let mut run = AgentRun {
        id: row.get(0)?,
        company_id: row.get(1)?,
        agent_id: row.get(2)?,
        issue_id: row.get(3)?,
        invocation_source: row.get(4)?,
        trigger_detail: row.get(5)?,
        wake_reason: row.get(6)?,
        status: row.get(7)?,
        started_at: row.get(8)?,
        finished_at: row.get(9)?,
        error: row.get(10)?,
        wakeup_request_id: row.get(11)?,
        exit_code: row.get(12)?,
        signal: row.get(13)?,
        usage_json: row
            .get::<_, Option<String>>(14)?
            .map(|value| parse_json(value)),
        result_json: row
            .get::<_, Option<String>>(15)?
            .map(|value| parse_json(value)),
        session_id_before: row.get(16)?,
        session_id_after: row.get(17)?,
        log_store: row.get(18)?,
        log_ref: row.get(19)?,
        log_bytes: row.get(20)?,
        log_sha256: row.get(21)?,
        log_compressed: row.get(22)?,
        stdout_excerpt: row.get(23)?,
        stderr_excerpt: row.get(24)?,
        error_code: row.get(25)?,
        external_run_id: row.get(26)?,
        context_snapshot: row
            .get::<_, Option<String>>(27)?
            .map(|value| parse_json(value)),
        created_at: row.get(28)?,
        updated_at: row.get(29)?,
    };

    normalize_agent_run_for_display(&mut run);
    Ok(run)
}

fn row_to_agent_run_event(row: &Row<'_>) -> rusqlite::Result<AgentRunEvent> {
    Ok(AgentRunEvent {
        id: row.get(0)?,
        company_id: row.get(1)?,
        run_id: row.get(2)?,
        agent_id: row.get(3)?,
        seq: row.get(4)?,
        event_type: row.get(5)?,
        stream: row.get(6)?,
        level: row.get(7)?,
        color: row.get(8)?,
        message: row.get(9)?,
        payload: row
            .get::<_, Option<String>>(10)?
            .map(|value| parse_json(value)),
        created_at: row.get(11)?,
    })
}

fn list_recent_events_for_run_ids(
    conn: &Connection,
    run_ids: &[String],
    per_run_limit: usize,
) -> rusqlite::Result<HashMap<String, Vec<AgentRunEvent>>> {
    if run_ids.is_empty() {
        return Ok(HashMap::new());
    }

    let placeholders = vec!["?"; run_ids.len()].join(", ");
    let sql = format!(
        "SELECT
            id, company_id, run_id, agent_id, seq, event_type, stream, level,
            color, message, payload, created_at
         FROM (
            SELECT
                id, company_id, run_id, agent_id, seq, event_type, stream, level,
                color, message, payload, created_at,
                ROW_NUMBER() OVER (PARTITION BY run_id ORDER BY seq DESC, id DESC) AS row_number
            FROM agent_run_events
            WHERE run_id IN ({placeholders})
         )
         WHERE row_number <= ?
         ORDER BY run_id ASC, seq DESC, id DESC"
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut bind_params = run_ids
        .iter()
        .cloned()
        .map(SqlValue::from)
        .collect::<Vec<_>>();
    bind_params.push(SqlValue::from(per_run_limit as i64));

    let events = stmt
        .query_map(params_from_iter(bind_params), row_to_agent_run_event)?
        .collect::<Result<Vec<_>, _>>()?;
    let mut grouped = HashMap::new();

    for event in events {
        grouped
            .entry(event.run_id.clone())
            .or_insert_with(Vec::new)
            .push(event);
    }

    Ok(grouped)
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

fn normalize_agent_run_for_display(run: &mut AgentRun) {
    let result_summary = run
        .result_json
        .as_ref()
        .and_then(summarize_agent_run_result);

    run.stdout_excerpt = result_summary
        .or_else(|| {
            run.stdout_excerpt
                .as_deref()
                .and_then(summarize_agent_run_excerpt)
        })
        .or_else(|| {
            run.stdout_excerpt
                .as_deref()
                .and_then(summarize_agent_run_text)
        });

    run.stderr_excerpt = run
        .stderr_excerpt
        .as_deref()
        .and_then(summarize_agent_run_excerpt)
        .or_else(|| {
            run.stderr_excerpt
                .as_deref()
                .and_then(summarize_agent_run_text)
        });
}

fn summarize_issue_run_card_update(
    run_status: &str,
    recent_events: &[AgentRunEvent],
    result_json: Option<&Value>,
    stdout_excerpt: Option<&str>,
    stderr_excerpt: Option<&str>,
) -> String {
    for event in recent_events {
        if let Some(summary) = event
            .payload
            .as_ref()
            .and_then(summarize_agent_run_event)
            .or_else(|| event.payload.as_ref().and_then(summarize_agent_run_result))
            .or_else(|| event.message.as_deref().and_then(summarize_agent_run_text))
        {
            return summary;
        }
    }

    if let Some(summary) = result_json
        .and_then(summarize_agent_run_result)
        .or_else(|| stdout_excerpt.and_then(summarize_agent_run_excerpt))
        .or_else(|| stdout_excerpt.and_then(summarize_agent_run_text))
        .or_else(|| stderr_excerpt.and_then(summarize_agent_run_excerpt))
        .or_else(|| stderr_excerpt.and_then(summarize_agent_run_text))
    {
        return summary;
    }

    match run_status {
        "queued" => "Waiting to start".to_string(),
        "running" => "Working on the issue".to_string(),
        "succeeded" => "Run finished".to_string(),
        "failed" => "Run failed".to_string(),
        "cancelled" => "Run cancelled".to_string(),
        "timed_out" => "Run timed out".to_string(),
        _ => "Run updated".to_string(),
    }
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

fn normalize_optional_update(value: Option<Option<String>>) -> Option<Option<String>> {
    value.map(normalize_optional_string)
}

fn normalize_issue_id_list(
    source_issue_id: Option<String>,
    source_issue_ids: Option<Vec<String>>,
) -> Vec<String> {
    let mut normalized = Vec::new();
    let mut seen = HashSet::new();
    for issue_id in source_issue_id
        .into_iter()
        .chain(source_issue_ids.into_iter().flatten())
    {
        let trimmed = issue_id.trim();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed.to_string()) {
            normalized.push(trimmed.to_string());
        }
    }
    normalized
}

fn normalize_string_list(values: Option<Vec<String>>) -> Vec<String> {
    let mut normalized = Vec::new();
    let mut seen = HashSet::new();
    for value in values.into_iter().flatten() {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed.to_string()) {
            normalized.push(trimmed.to_string());
        }
    }
    normalized
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
    let agent_home = provision_agent_home_root(paths, company_id, agent_slug)?;
    let base_dir = paths.base_dir().to_string_lossy();

    let today_memory_path = paths
        .agent_memory_dir(company_id, agent_slug)
        .join(format!("{}.md", Utc::now().format("%Y-%m-%d")));

    write_if_missing(
        &agent_home.join("AGENTS.md"),
        &format!(
            "# {agent_name}\n\nYou are an {role} agent working inside Unbound for {company_name}.\nOperate through the daemon-managed local board, and use the board helper commands for hires, issue changes, and comments.\nNever create sibling agent directories by hand under companies/.../agents.\n"
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
        &format!(
            "# Tools\n\nUse daemon-managed board mutations instead of editing sibling agent directories directly.\n\n- Hire agents: `unbound-daemon --base-dir \"{base_dir}\" board hire-agent ...`\n- Create issues: `unbound-daemon --base-dir \"{base_dir}\" board issue-create ...`\n- Update issues: `unbound-daemon --base-dir \"{base_dir}\" board issue-update ...`\n- Add issue comments: `unbound-daemon --base-dir \"{base_dir}\" board issue-comment-add ...`\n\nDirect filesystem creation of new agent homes does not create board records or approvals.\n"
        ),
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

fn load_hire_approval_activation_target_sync(
    conn: &Connection,
    approval_id: &str,
) -> DatabaseResult<Option<HireApprovalActivationTarget>> {
    let approval = conn
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
        .optional()?;

    let Some(approval) = approval else {
        return Ok(None);
    };
    if approval.approval_type != "hire_agent" {
        return Ok(None);
    }

    let agent_id = approval
        .payload
        .get("agent_id")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DatabaseError::InvalidData("Hire approval payload missing agent_id".to_string())
        })?;
    let agent = conn
        .query_row(
            "SELECT
                id, company_id, name, slug, role, title, icon, status, reports_to, capabilities,
                adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                spent_monthly_cents, permissions, last_heartbeat_at, metadata,
                home_path, instructions_path, created_at, updated_at
             FROM agents
             WHERE id = ?1 AND company_id = ?2",
            params![agent_id, approval.company_id],
            row_to_agent,
        )
        .optional()?
        .ok_or_else(|| DatabaseError::NotFound("Approved hire agent not found".to_string()))?;
    let company = get_company_sync(conn, &approval.company_id)?
        .ok_or_else(|| DatabaseError::NotFound("Company not found".to_string()))?;

    Ok(Some(HireApprovalActivationTarget {
        approval_id: approval.id,
        company_id: approval.company_id,
        agent_id: agent.id,
        agent_name: agent.name,
        agent_slug: agent.slug,
        agent_role: agent.role,
        adapter_type: agent.adapter_type,
        company_name: company.name,
    }))
}

fn prepare_hire_approval_activation(
    paths: &Paths,
    target: &HireApprovalActivationTarget,
) -> BoardResult<PreparedHireApprovalActivation> {
    let agent_home = paths.agent_home_dir(&target.company_id, &target.agent_slug);
    let home_existed_before = agent_home.exists();

    if target.adapter_type == "process" {
        scaffold_agent_home(
            paths,
            &target.company_id,
            &target.agent_name,
            &target.agent_slug,
            &target.company_name,
            &target.agent_role,
        )?;
    }

    Ok(PreparedHireApprovalActivation {
        agent_home,
        home_existed_before,
    })
}

fn rollback_prepared_hire_activation(prepared: &PreparedHireApprovalActivation) {
    if !prepared.home_existed_before {
        let _ = fs::remove_dir_all(&prepared.agent_home);
    }
}

fn provision_agent_home_root(
    paths: &Paths,
    company_id: &str,
    agent_slug: &str,
) -> BoardResult<std::path::PathBuf> {
    let agent_home = paths.agent_home_dir(company_id, agent_slug);
    fs::create_dir_all(&agent_home)?;
    fs::create_dir_all(paths.agent_memory_dir(company_id, agent_slug))?;
    fs::create_dir_all(paths.agent_life_dir(company_id, agent_slug))?;
    fs::create_dir_all(paths.company_assets_dir(company_id))?;
    fs::create_dir_all(paths.company_attachments_dir(company_id))?;
    Ok(agent_home)
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

fn validate_company_agent_sync(
    conn: &Connection,
    company_id: &str,
    agent_id: &str,
    field_name: &str,
) -> DatabaseResult<()> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM agents WHERE id = ?1 AND company_id = ?2",
            params![agent_id, company_id],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;
    if exists.is_none() {
        return Err(DatabaseError::InvalidData(format!(
            "{field_name} must reference an agent in the same company"
        )));
    }
    Ok(())
}

fn ensure_issue_exists_sync(
    conn: &Connection,
    company_id: &str,
    issue_id: &str,
) -> DatabaseResult<()> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM issues WHERE id = ?1 AND company_id = ?2",
            params![issue_id, company_id],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;
    if exists.is_none() {
        return Err(DatabaseError::NotFound("Issue not found".to_string()));
    }
    Ok(())
}

fn validate_assignable_agent_sync(
    conn: &Connection,
    company_id: &str,
    agent_id: &str,
    field_name: &str,
) -> DatabaseResult<()> {
    let status = conn
        .query_row(
            "SELECT status FROM agents WHERE id = ?1 AND company_id = ?2",
            params![agent_id, company_id],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    match status.as_deref() {
        None => Err(DatabaseError::InvalidData(format!(
            "{field_name} must reference an agent in the same company"
        ))),
        Some("pending_approval") => Err(DatabaseError::InvalidData(
            "Cannot assign work to pending approval agents".to_string(),
        )),
        Some(_) => Ok(()),
    }
}

fn validate_issue_ids_for_company_sync(
    conn: &Connection,
    company_id: &str,
    issue_ids: &[String],
) -> DatabaseResult<()> {
    for issue_id in issue_ids {
        let exists = conn
            .query_row(
                "SELECT 1 FROM issues WHERE id = ?1 AND company_id = ?2",
                params![issue_id, company_id],
                |row| row.get::<_, i64>(0),
            )
            .optional()?;
        if exists.is_none() {
            return Err(DatabaseError::InvalidData(format!(
                "Issue {issue_id} does not belong to this company"
            )));
        }
    }
    Ok(())
}

fn sanitize_attachment_filename(value: &str) -> String {
    let sanitized: String = value
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect();
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        "attachment".to_string()
    } else {
        trimmed.to_string()
    }
}

fn guess_content_type(file_name_or_extension: Option<&str>) -> String {
    let extension = file_name_or_extension
        .and_then(|value| {
            Path::new(value)
                .extension()
                .and_then(|ext| ext.to_str())
                .or(Some(value))
        })
        .unwrap_or("")
        .trim()
        .trim_start_matches('.')
        .to_ascii_lowercase();

    match extension.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "txt" | "md" | "log" => "text/plain",
        "json" => "application/json",
        "csv" => "text/csv",
        "zip" => "application/zip",
        "tar" => "application/x-tar",
        "gz" => "application/gzip",
        "patch" | "diff" => "text/x-diff",
        "rs" | "ts" | "tsx" | "js" | "jsx" | "py" | "go" | "swift" | "java" | "kt" | "sql"
        | "toml" | "yaml" | "yml" => "text/plain",
        _ => "application/octet-stream",
    }
    .to_string()
}

fn activity_actor<'a>(
    requested_by_agent_id: Option<&'a str>,
    requested_by_user_id: Option<&'a str>,
) -> (&'static str, &'a str) {
    if let Some(agent_id) = requested_by_agent_id {
        ("agent", agent_id)
    } else {
        ("user", requested_by_user_id.unwrap_or(LOCAL_BOARD_USER_ID))
    }
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

fn issue_has_descendant_sync(
    conn: &Connection,
    issue_id: &str,
    candidate_issue_id: &str,
) -> DatabaseResult<bool> {
    let mut child_ids = direct_child_issue_ids_sync(conn, issue_id)?;
    while let Some(child_id) = child_ids.pop() {
        if child_id == candidate_issue_id {
            return Ok(true);
        }
        child_ids.extend(direct_child_issue_ids_sync(conn, &child_id)?);
    }
    Ok(false)
}

fn direct_child_issue_ids_sync(conn: &Connection, issue_id: &str) -> DatabaseResult<Vec<String>> {
    let mut stmt = conn.prepare("SELECT id FROM issues WHERE parent_id = ?1")?;
    let child_ids = stmt
        .query_map(params![issue_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(child_ids)
}

fn shift_issue_subtree_depths_sync(
    conn: &Connection,
    issue_id: &str,
    depth_delta: i64,
) -> DatabaseResult<()> {
    if depth_delta == 0 {
        return Ok(());
    }

    for child_id in direct_child_issue_ids_sync(conn, issue_id)? {
        conn.execute(
            "UPDATE issues
             SET request_depth = CASE
                 WHEN request_depth + ?1 < 0 THEN 0
                 ELSE request_depth + ?1
             END
             WHERE id = ?2",
            params![depth_delta, child_id],
        )?;
        shift_issue_subtree_depths_sync(conn, &child_id, depth_delta)?;
    }

    Ok(())
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
    async fn create_company_starts_without_ceo_or_agent_files() {
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
        assert_eq!(company.ceo_agent_id, None);

        let agents = list_agents(&db, &company.id).await.unwrap();
        assert!(agents.is_empty());
        assert!(!paths.company_root(&company.id).exists());
    }

    #[tokio::test]
    async fn create_ceo_agent_sets_company_ceo_without_prewriting_instruction_files() {
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

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                title: Some("Chief Executive Officer".to_string()),
                icon: Some("crown".to_string()),
                runtime_config: Some(json!({
                    "heartbeat": {
                        "enabled": true,
                        "intervalSec": 3600,
                        "wakeOnDemand": true,
                        "cooldownSec": 10,
                        "maxConcurrentRuns": 1
                    }
                })),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(ceo.role, "ceo");
        assert_eq!(ceo.status, "idle");
        assert_eq!(ceo.reports_to, None);
        assert!(Path::new(ceo.home_path.as_ref().unwrap()).exists());
        assert!(paths.agent_memory_dir(&company.id, &ceo.slug).exists());
        assert!(paths.agent_life_dir(&company.id, &ceo.slug).exists());
        assert!(
            !Path::new(ceo.instructions_path.as_ref().unwrap()).exists(),
            "CEO AGENTS.md should be created by the bootstrap issue, not prewritten"
        );

        let refreshed_company = get_company(&db, &company.id).await.unwrap().unwrap();
        assert_eq!(refreshed_company.ceo_agent_id, Some(ceo.id.clone()));
    }

    #[tokio::test]
    async fn create_non_ceo_agent_still_scaffolds_instruction_files() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        assert!(
            Path::new(agent.instructions_path.as_ref().unwrap()).exists(),
            "Non-CEO agents should keep the existing scaffolded local files"
        );
    }

    #[tokio::test]
    async fn update_agent_persists_configuration_changes() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let updated = update_agent(
            &db,
            UpdateAgentInput {
                agent_id: agent.id.clone(),
                name: Some("CEO".to_string()),
                title: Some(Some("Chief Executive Officer".to_string())),
                capabilities: Some(Some("Own strategy".to_string())),
                adapter_type: Some("process".to_string()),
                adapter_config: Some(json!({
                    "command": "claude",
                    "model": "default",
                    "thinkingEffort": "auto",
                    "extraArgs": ["--verbose"],
                })),
                runtime_config: Some(json!({
                    "maxTurns": 80,
                    "heartbeat": {
                        "enabled": true,
                        "intervalSec": 3600,
                        "wakeOnDemand": true,
                        "cooldownSec": 15,
                        "maxConcurrentRuns": 1
                    }
                })),
                permissions: Some(json!({
                    "canCreateAgents": true,
                })),
                metadata: Some(Some(json!({
                    "promptTemplate": "You are {{ agent.name }}.",
                }))),
                home_path: Some(Some("/tmp/ceo".to_string())),
                instructions_path: Some(Some("/tmp/ceo/AGENTS.md".to_string())),
                ..UpdateAgentInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(updated.name, "CEO");
        assert_eq!(updated.title.as_deref(), Some("Chief Executive Officer"));
        assert_eq!(updated.capabilities.as_deref(), Some("Own strategy"));
        assert_eq!(updated.home_path.as_deref(), Some("/tmp/ceo"));
        assert_eq!(
            updated.instructions_path.as_deref(),
            Some("/tmp/ceo/AGENTS.md")
        );
        assert_eq!(
            updated
                .metadata
                .as_ref()
                .and_then(|value| value.get("promptTemplate"))
                .and_then(Value::as_str),
            Some("You are {{ agent.name }}.")
        );
        assert_eq!(
            updated
                .runtime_config
                .get("heartbeat")
                .and_then(|value| value.get("intervalSec"))
                .and_then(Value::as_i64),
            Some(3600)
        );
        assert_eq!(
            updated
                .permissions
                .get("canCreateAgents")
                .and_then(Value::as_bool),
            Some(true)
        );
    }

    #[tokio::test]
    async fn create_agent_hire_creates_pending_agent_approval_and_issue_link() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let source_issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Bootstrap the engineering team".to_string(),
                assignee_agent_id: Some(ceo.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let hired_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                title: Some("Founding Engineer".to_string()),
                source_issue_id: Some(source_issue.id.clone()),
                requested_by_agent_id: Some(ceo.id.clone()),
                requested_by_run_id: Some("run-123".to_string()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(hired_agent.status, "pending_approval");
        assert_eq!(hired_agent.reports_to, Some(ceo.id.clone()));
        assert!(
            !paths
                .agent_home_dir(&company.id, &hired_agent.slug)
                .exists(),
            "Pending approval hires should not have a local home provisioned yet"
        );
        assert!(
            !Path::new(hired_agent.instructions_path.as_deref().unwrap()).exists(),
            "Pending approval hires should not have instruction files yet"
        );

        let approvals = list_approvals(&db, &company.id).await.unwrap();
        assert_eq!(approvals.len(), 1);
        let approval = &approvals[0];
        assert_eq!(approval.approval_type, "hire_agent");
        assert_eq!(approval.requested_by_agent_id, Some(ceo.id.clone()));
        assert_eq!(approval.requested_by_user_id, None);
        assert_eq!(
            approval.payload.get("agent_id").and_then(Value::as_str),
            Some(hired_agent.id.as_str())
        );
        assert_eq!(
            approval
                .payload
                .get("source_issue_id")
                .and_then(Value::as_str),
            Some(source_issue.id.as_str())
        );
        assert_eq!(
            approval
                .payload
                .get("requested_by_run_id")
                .and_then(Value::as_str),
            Some("run-123")
        );

        let issue_link_count = db
            .call_with_operation("board.test.issue_approval_count", {
                let approval_id = approval.id.clone();
                let issue_id = source_issue.id.clone();
                move |conn| {
                    Ok(conn.query_row(
                        "SELECT COUNT(*) FROM issue_approvals WHERE approval_id = ?1 AND issue_id = ?2",
                        params![approval_id, issue_id],
                        |row| row.get::<_, i64>(0),
                    )?)
                }
            })
            .await
            .unwrap();
        assert_eq!(issue_link_count, 1);
    }

    #[tokio::test]
    async fn create_agent_decision_approval_links_issue_and_dedupes_request_key() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Need board guidance".to_string(),
                assignee_agent_id: Some(agent.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let approval = create_agent_decision_approval(
            &db,
            CreateAgentDecisionApprovalInput {
                company_id: company.id.clone(),
                requested_by_agent_id: agent.id.clone(),
                requested_by_run_id: "run-123".to_string(),
                source_issue_id: Some(issue.id.clone()),
                provider: Some("claude".to_string()),
                provider_request_id: Some("toolu_123".to_string()),
                request_key: "decision-key-1".to_string(),
                question: "Should I land this risky migration?".to_string(),
                options: Some(vec!["Land it".to_string(), "Hold".to_string()]),
                questions: Some(json!([
                    {
                        "id": "ship_it",
                        "header": "Migration",
                        "question": "Should I land this risky migration?",
                        "options": [
                            { "label": "Land it", "description": "Proceed now" },
                            { "label": "Hold", "description": "Wait for review" }
                        ]
                    }
                ])),
                raw_request: Some(json!({
                    "name": "AskUserQuestion",
                    "input": {
                        "question": "Should I land this risky migration?"
                    }
                })),
                ..CreateAgentDecisionApprovalInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(approval.approval_type, "agent_decision");
        assert_eq!(approval.requested_by_agent_id, Some(agent.id.clone()));
        assert_eq!(
            approval
                .payload
                .get("source_issue_id")
                .and_then(Value::as_str),
            Some(issue.id.as_str())
        );
        assert_eq!(
            approval
                .payload
                .pointer("/questions/0/options/0/label")
                .and_then(Value::as_str),
            Some("Land it")
        );

        let duplicate = create_agent_decision_approval(
            &db,
            CreateAgentDecisionApprovalInput {
                company_id: company.id.clone(),
                requested_by_agent_id: agent.id.clone(),
                requested_by_run_id: "run-123".to_string(),
                source_issue_id: Some(issue.id.clone()),
                request_key: "decision-key-1".to_string(),
                question: "Should I land this risky migration?".to_string(),
                ..CreateAgentDecisionApprovalInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(duplicate.id, approval.id);

        let approvals = list_approvals(&db, &company.id).await.unwrap();
        assert_eq!(approvals.len(), 1);

        let issue_link_count = db
            .call_with_operation("board.test.decision_issue_approval_count", {
                let approval_id = approval.id.clone();
                let issue_id = issue.id.clone();
                move |conn| {
                    Ok(conn.query_row(
                        "SELECT COUNT(*) FROM issue_approvals WHERE approval_id = ?1 AND issue_id = ?2",
                        params![approval_id, issue_id],
                        |row| row.get::<_, i64>(0),
                    )?)
                }
            })
            .await
            .unwrap();
        assert_eq!(issue_link_count, 1);
    }

    #[tokio::test]
    async fn approving_agent_decision_approval_persists_decision_note() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Need board guidance".to_string(),
                assignee_agent_id: Some(agent.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let approval = create_agent_decision_approval(
            &db,
            CreateAgentDecisionApprovalInput {
                company_id: company.id.clone(),
                requested_by_agent_id: agent.id.clone(),
                requested_by_run_id: "run-123".to_string(),
                source_issue_id: Some(issue.id.clone()),
                request_key: "decision-key-2".to_string(),
                question: "Should I ship this now?".to_string(),
                options: Some(vec!["Ship".to_string(), "Wait".to_string()]),
                ..CreateAgentDecisionApprovalInput::default()
            },
        )
        .await
        .unwrap();

        let approved = approve_approval(
            &db,
            &paths,
            ApprovalDecisionInput {
                approval_id: approval.id.clone(),
                decided_by_user_id: Some(LOCAL_BOARD_USER_ID.to_string()),
                decision_note: Some("Decision: Ship".to_string()),
            },
        )
        .await
        .unwrap();

        assert_eq!(approved.status, "approved");
        assert_eq!(
            approved.decided_by_user_id.as_deref(),
            Some(LOCAL_BOARD_USER_ID)
        );
        assert_eq!(approved.decision_note.as_deref(), Some("Decision: Ship"));
        assert_eq!(
            approved
                .payload
                .get("source_issue_id")
                .and_then(Value::as_str),
            Some(issue.id.as_str())
        );
    }

    #[tokio::test]
    async fn create_agent_hire_without_required_approval_creates_idle_agent() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(agent.status, "idle");
        assert!(list_approvals(&db, &company.id).await.unwrap().is_empty());
        assert!(
            Path::new(agent.instructions_path.as_deref().unwrap()).exists(),
            "Immediate hires should still scaffold the local agent files"
        );
    }

    #[tokio::test]
    async fn approving_hire_approval_transitions_agent_to_idle() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let hired_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                requested_by_agent_id: Some(ceo.id.clone()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        assert!(
            !paths
                .agent_home_dir(&company.id, &hired_agent.slug)
                .exists(),
            "Pending approval hires should not be provisioned before approval"
        );

        let mut approvals = list_approvals(&db, &company.id).await.unwrap();
        let approval = approvals.remove(0);
        let approved = approve_approval(
            &db,
            &paths,
            ApprovalDecisionInput {
                approval_id: approval.id.clone(),
                ..ApprovalDecisionInput::default()
            },
        )
        .await
        .unwrap();

        let refreshed_agent = get_agent(&db, &hired_agent.id).await.unwrap().unwrap();
        assert_eq!(approved.status, "approved");
        assert_eq!(refreshed_agent.status, "idle");
        assert!(paths
            .agent_home_dir(&company.id, &hired_agent.slug)
            .exists());
        assert!(Path::new(refreshed_agent.instructions_path.as_deref().unwrap()).exists());
    }

    #[tokio::test]
    async fn approving_hire_approval_reuses_existing_home_if_present() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let hired_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                requested_by_agent_id: Some(ceo.id.clone()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        scaffold_agent_home(
            &paths,
            &company.id,
            &hired_agent.name,
            &hired_agent.slug,
            &company.name,
            &hired_agent.role,
        )
        .unwrap();

        let mut approvals = list_approvals(&db, &company.id).await.unwrap();
        let approval = approvals.remove(0);
        let approved = approve_approval(
            &db,
            &paths,
            ApprovalDecisionInput {
                approval_id: approval.id.clone(),
                ..ApprovalDecisionInput::default()
            },
        )
        .await
        .unwrap();

        let refreshed_agent = get_agent(&db, &hired_agent.id).await.unwrap().unwrap();
        assert_eq!(approved.status, "approved");
        assert_eq!(refreshed_agent.status, "idle");
        assert!(Path::new(refreshed_agent.instructions_path.as_deref().unwrap()).exists());
    }

    #[tokio::test]
    async fn approving_hire_approval_keeps_pending_state_when_activation_fails() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let hired_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                requested_by_agent_id: Some(ceo.id.clone()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        let blocking_path = paths.agent_home_dir(&company.id, &hired_agent.slug);
        fs::write(&blocking_path, "not a directory").unwrap();

        let mut approvals = list_approvals(&db, &company.id).await.unwrap();
        let approval = approvals.remove(0);
        let error = approve_approval(
            &db,
            &paths,
            ApprovalDecisionInput {
                approval_id: approval.id.clone(),
                ..ApprovalDecisionInput::default()
            },
        )
        .await
        .unwrap_err();

        assert!(
            error.to_string().contains("File exists")
                || error.to_string().contains("Not a directory")
                || error.to_string().contains("directory"),
            "unexpected activation failure: {error}"
        );

        let refreshed_approval = get_approval(&db, &approval.id).await.unwrap().unwrap();
        let refreshed_agent = get_agent(&db, &hired_agent.id).await.unwrap().unwrap();
        assert_eq!(refreshed_approval.status, "pending");
        assert_eq!(refreshed_agent.status, "pending_approval");
    }

    #[tokio::test]
    async fn create_issue_persists_assignee_for_bootstrap_tasks() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Create your CEO HEARTBEAT.md".to_string(),
                assignee_agent_id: Some(ceo.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(issue.assignee_agent_id, Some(ceo.id.clone()));
        assert_eq!(issue.execution_agent_name_key, Some(ceo.slug.clone()));
        assert_eq!(issue.status, "todo");
    }

    #[tokio::test]
    async fn delete_project_removes_related_issues_and_workspaces() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let alpha_repo_path = dir.path().join("alpha").to_string_lossy().into_owned();
        let beta_repo_path = dir.path().join("beta").to_string_lossy().into_owned();

        let alpha_project = create_project(
            &db,
            CreateProjectInput {
                company_id: company.id.clone(),
                name: "Alpha".to_string(),
                repo_path: Some(alpha_repo_path.clone()),
                ..CreateProjectInput::default()
            },
        )
        .await
        .unwrap();

        let beta_project = create_project(
            &db,
            CreateProjectInput {
                company_id: company.id.clone(),
                name: "Beta".to_string(),
                repo_path: Some(beta_repo_path.clone()),
                ..CreateProjectInput::default()
            },
        )
        .await
        .unwrap();

        let alpha_issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                project_id: Some(alpha_project.id.clone()),
                title: "Alpha issue".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let beta_issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                project_id: Some(beta_project.id.clone()),
                title: "Beta issue".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let alpha_session_id = Uuid::new_v4().to_string();
        let beta_session_id = Uuid::new_v4().to_string();
        let company_id = company.id.clone();
        let alpha_project_id = alpha_project.id.clone();
        let beta_project_id = beta_project.id.clone();
        let alpha_issue_id = alpha_issue.id.clone();
        let beta_issue_id = beta_issue.id.clone();
        let session_now = now_rfc3339();

        db.call_with_operation("board.project_delete_test.seed_workspaces", move |conn| {
            let alpha_repo_id: String = conn.query_row(
                "SELECT id FROM repositories WHERE path = ?1",
                params![alpha_repo_path],
                |row| row.get(0),
            )?;
            let beta_repo_id: String = conn.query_row(
                "SELECT id FROM repositories WHERE path = ?1",
                params![beta_repo_path],
                |row| row.get(0),
            )?;

            conn.execute(
                "INSERT INTO agent_coding_sessions (
                    id, repository_id, title, status, is_worktree,
                    created_at, last_accessed_at, updated_at,
                    company_id, project_id, issue_id
                 ) VALUES (?1, ?2, ?3, 'active', 0, ?4, ?4, ?4, ?5, ?6, ?7)",
                params![
                    alpha_session_id,
                    alpha_repo_id,
                    "Alpha workspace",
                    session_now,
                    company_id,
                    alpha_project_id,
                    alpha_issue_id,
                ],
            )?;

            conn.execute(
                "INSERT INTO agent_coding_sessions (
                    id, repository_id, title, status, is_worktree,
                    created_at, last_accessed_at, updated_at,
                    company_id, project_id, issue_id
                 ) VALUES (?1, ?2, ?3, 'active', 0, ?4, ?4, ?4, ?5, ?6, ?7)",
                params![
                    beta_session_id,
                    beta_repo_id,
                    "Beta workspace",
                    session_now,
                    company_id,
                    beta_project_id,
                    beta_issue_id,
                ],
            )?;

            Ok(())
        })
        .await
        .unwrap();

        let deleted_project = delete_project(&db, &alpha_project.id).await.unwrap();
        assert_eq!(deleted_project.id, alpha_project.id);

        assert!(get_project(&db, &alpha_project.id).await.unwrap().is_none());

        let remaining_projects = list_projects(&db, &company.id).await.unwrap();
        assert_eq!(remaining_projects.len(), 1);
        assert_eq!(remaining_projects[0].id, beta_project.id);

        let remaining_issues = list_issues(
            &db,
            IssueListFilter {
                company_id: company.id.clone(),
                ..IssueListFilter::default()
            },
        )
        .await
        .unwrap();
        assert_eq!(remaining_issues.len(), 1);
        assert_eq!(remaining_issues[0].id, beta_issue.id);

        let remaining_workspaces = list_workspaces(&db, &company.id).await.unwrap();
        assert_eq!(remaining_workspaces.len(), 1);
        assert_eq!(
            remaining_workspaces[0].project_id.as_deref(),
            Some(beta_project.id.as_str())
        );
        assert_eq!(
            remaining_workspaces[0].issue_id.as_deref(),
            Some(beta_issue.id.as_str())
        );
    }

    #[tokio::test]
    async fn update_issue_edits_and_clears_visible_issue_fields() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let project = create_project(
            &db,
            CreateProjectInput {
                company_id: company.id.clone(),
                name: "Bootstrap".to_string(),
                ..CreateProjectInput::default()
            },
        )
        .await
        .unwrap();

        let parent_issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Parent".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Child".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let updated = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: issue.id.clone(),
                title: Some("Updated Child".to_string()),
                description: Some(Some("Bootstrap the workspace".to_string())),
                status: Some("in_progress".to_string()),
                priority: Some("high".to_string()),
                project_id: Some(Some(project.id.clone())),
                parent_id: Some(Some(parent_issue.id.clone())),
                assignee_agent_id: Some(Some(agent.id.clone())),
                execution_workspace_settings: Some(Some(json!({
                    "mode": "new_worktree"
                }))),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(updated.title, "Updated Child");
        assert_eq!(
            updated.description.as_deref(),
            Some("Bootstrap the workspace")
        );
        assert_eq!(updated.status, "in_progress");
        assert_eq!(updated.priority, "high");
        assert_eq!(updated.project_id, Some(project.id.clone()));
        assert_eq!(updated.parent_id, Some(parent_issue.id.clone()));
        assert_eq!(updated.assignee_agent_id, Some(agent.id.clone()));
        assert_eq!(updated.execution_agent_name_key, Some(agent.slug.clone()));
        assert_eq!(
            updated.execution_workspace_settings,
            Some(json!({ "mode": "new_worktree" }))
        );
        assert_eq!(updated.request_depth, parent_issue.request_depth + 1);

        let cleared = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: issue.id.clone(),
                description: Some(None),
                project_id: Some(None),
                parent_id: Some(None),
                assignee_agent_id: Some(None),
                execution_workspace_settings: Some(None),
                hidden_at: Some(Some(now_rfc3339())),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(cleared.description, None);
        assert_eq!(cleared.project_id, None);
        assert_eq!(cleared.parent_id, None);
        assert_eq!(cleared.assignee_agent_id, None);
        assert_eq!(cleared.execution_agent_name_key, None);
        assert_eq!(cleared.execution_workspace_settings, None);
        assert!(cleared.hidden_at.is_some());
        assert_eq!(cleared.request_depth, 0);
    }

    #[tokio::test]
    async fn attach_issue_workspace_session_preserves_todo_status() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Builder".to_string(),
                role: Some("engineer".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let repo_path = dir.path().join("project").to_string_lossy().into_owned();
        let project = create_project(
            &db,
            CreateProjectInput {
                company_id: company.id.clone(),
                name: "Project".to_string(),
                repo_path: Some(repo_path.clone()),
                repo_ref: Some("main".to_string()),
                ..CreateProjectInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                project_id: Some(project.id.clone()),
                title: "Keep status".to_string(),
                status: Some("todo".to_string()),
                assignee_agent_id: Some(agent.id.clone()),
                execution_workspace_settings: Some(json!({ "mode": "main" })),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let session_id = uuid::Uuid::new_v4().to_string();
        let session_created_at = now_rfc3339();
        let company_id = company.id.clone();
        let project_id = project.id.clone();
        let issue_id = issue.id.clone();
        let session_id_for_insert = session_id.clone();
        let repo_path_for_lookup = repo_path.clone();
        db.call_with_operation(
            "board.attach_issue_workspace_test.seed_session",
            move |conn| {
                let repository_id: String = conn.query_row(
                    "SELECT id FROM repositories WHERE path = ?1",
                    params![repo_path_for_lookup],
                    |row| row.get(0),
                )?;

                conn.execute(
                    "INSERT INTO agent_coding_sessions (
                    id, repository_id, title, status, is_worktree,
                    created_at, last_accessed_at, updated_at,
                    company_id, project_id, issue_id
                 ) VALUES (?1, ?2, ?3, 'active', 0, ?4, ?4, ?4, ?5, ?6, ?7)",
                    params![
                        session_id_for_insert,
                        repository_id,
                        "Issue workspace",
                        session_created_at,
                        company_id,
                        project_id,
                        issue_id,
                    ],
                )?;
                Ok(())
            },
        )
        .await
        .unwrap();

        let workspace = attach_issue_workspace_session(
            &db,
            &issue.id,
            &session_id,
            &repo_path,
            Some("main".to_string()),
        )
        .await
        .unwrap();

        let refreshed_issue = get_issue(&db, &issue.id).await.unwrap().unwrap();
        assert_eq!(workspace.session_id, session_id);
        assert_eq!(refreshed_issue.status, "todo");
        assert!(refreshed_issue.started_at.is_some());
    }

    #[tokio::test]
    async fn reopening_issue_to_todo_clears_completion_timestamps() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Closed".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let done_issue = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: issue.id.clone(),
                status: Some("done".to_string()),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert!(done_issue.completed_at.is_some());

        let reopened_done = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: done_issue.id.clone(),
                status: Some("todo".to_string()),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(reopened_done.status, "todo");
        assert_eq!(reopened_done.completed_at, None);

        let cancelled_issue = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: issue.id.clone(),
                status: Some("cancelled".to_string()),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert!(cancelled_issue.cancelled_at.is_some());

        let reopened_cancelled = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: cancelled_issue.id.clone(),
                status: Some("todo".to_string()),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(reopened_cancelled.status, "todo");
        assert_eq!(reopened_cancelled.cancelled_at, None);
    }

    #[tokio::test]
    async fn add_issue_comment_persists_target_agent_id() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Comment target".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let comment = add_issue_comment(
            &db,
            AddIssueCommentInput {
                company_id: company.id.clone(),
                issue_id: issue.id.clone(),
                target_agent_id: Some(agent.id.clone()),
                body: "Please pick this up.".to_string(),
                ..AddIssueCommentInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(comment.target_agent_id.as_deref(), Some(agent.id.as_str()));
    }

    #[tokio::test]
    async fn add_issue_attachment_copies_file_and_lists_it() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Attachments".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let source_path = dir.path().join("source-brief.txt");
        fs::write(&source_path, "attachment payload").unwrap();

        let attachment = add_issue_attachment(
            &db,
            &paths,
            AddIssueAttachmentInput {
                company_id: company.id.clone(),
                issue_id: issue.id.clone(),
                local_file_path: source_path.to_string_lossy().to_string(),
                ..AddIssueAttachmentInput::default()
            },
        )
        .await
        .unwrap();

        assert_eq!(attachment.issue_id, issue.id);
        assert_eq!(
            attachment.original_filename.as_deref(),
            Some("source-brief.txt")
        );
        assert!(attachment.local_path.contains("/attachments/"));
        assert_eq!(
            fs::read_to_string(&attachment.local_path).unwrap(),
            "attachment payload"
        );

        let listed = list_issue_attachments(&db, &paths, &issue.id)
            .await
            .unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].id, attachment.id);
        assert_eq!(listed[0].local_path, attachment.local_path);
    }

    #[tokio::test]
    async fn list_issue_runs_returns_all_runs_linked_to_issue() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Run history".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let other_issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Other".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let company_id = company.id.clone();
        let agent_id = agent.id.clone();
        let issue_id = issue.id.clone();
        let other_issue_id = other_issue.id.clone();
        db.call_with_operation("board.issue.run.list_test.seed", move |conn| {
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                    wake_reason, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, 'automation', 'system', 'issue_commented', 'queued', ?5, ?5)",
                params![
                    "run-1",
                    &company_id,
                    &agent_id,
                    &issue_id,
                    "2026-03-18T00:00:00Z"
                ],
            )?;
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                    wake_reason, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, 'automation', 'system', 'issue_commented', 'running', ?5, ?5)",
                params![
                    "run-2",
                    &company_id,
                    &agent_id,
                    &issue_id,
                    "2026-03-18T00:01:00Z"
                ],
            )?;
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                    wake_reason, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, 'automation', 'system', 'issue_commented', 'queued', ?5, ?5)",
                params![
                    "run-3",
                    &company_id,
                    &agent_id,
                    &other_issue_id,
                    "2026-03-18T00:02:00Z"
                ],
            )?;
            Ok(())
        })
        .await
        .unwrap();

        let runs = list_issue_runs(&db, &issue.id, Some(10)).await.unwrap();

        assert_eq!(runs.len(), 2);
        assert_eq!(runs[0].id, "run-2");
        assert_eq!(runs[1].id, "run-1");
        assert!(runs
            .iter()
            .all(|run| run.issue_id.as_deref() == Some(issue.id.as_str())));
    }

    #[tokio::test]
    async fn list_agent_live_run_counts_returns_running_instances_per_agent() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent_a = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let agent_b = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let company_id = company.id.clone();
        let agent_a_id = agent_a.id.clone();
        let agent_b_id = agent_b.id.clone();
        db.call_with_operation("board.agent_run.live_counts_test.seed", move |conn| {
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, invocation_source, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'assignment', 'running', ?4, ?4)",
                params!["run-1", &company_id, &agent_a_id, "2026-03-20T12:00:00Z"],
            )?;
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, invocation_source, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'assignment', 'running', ?4, ?4)",
                params!["run-2", &company_id, &agent_a_id, "2026-03-20T12:01:00Z"],
            )?;
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, invocation_source, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'assignment', 'queued', ?4, ?4)",
                params!["run-3", &company_id, &agent_a_id, "2026-03-20T12:02:00Z"],
            )?;
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, invocation_source, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'assignment', 'running', ?4, ?4)",
                params!["run-4", &company_id, &agent_b_id, "2026-03-20T12:03:00Z"],
            )?;
            Ok(())
        })
        .await
        .unwrap();

        let counts = list_agent_live_run_counts(&db, &company.id).await.unwrap();
        let counts_by_agent = counts
            .into_iter()
            .map(|entry| (entry.agent_id, entry.live_count))
            .collect::<HashMap<_, _>>();

        assert_eq!(counts_by_agent.get(&agent_a.id), Some(&2));
        assert_eq!(counts_by_agent.get(&agent_b.id), Some(&1));
    }

    #[tokio::test]
    async fn list_agent_live_run_counts_returns_zero_for_idle_agents() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Idle Agent".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let counts = list_agent_live_run_counts(&db, &company.id).await.unwrap();
        assert_eq!(counts.len(), 1);
        assert_eq!(counts[0].agent_id, agent.id);
        assert_eq!(counts[0].live_count, 0);
    }

    #[tokio::test]
    async fn list_issue_run_card_updates_prefers_latest_summarizable_event() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Live card update".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let company_id = company.id.clone();
        let agent_id = agent.id.clone();
        let issue_id = issue.id.clone();
        db.call_with_operation("board.issue.run.card_updates_test.seed_events", move |conn| {
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                    wake_reason, status, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, 'assignment', 'system', 'issue_assigned', 'running', ?5, ?5)",
                params![
                    "run-1",
                    &company_id,
                    &agent_id,
                    &issue_id,
                    "2026-03-20T10:00:00Z"
                ],
            )?;
            conn.execute(
                "UPDATE issues
                 SET status = 'in_progress', execution_run_id = 'run-1', updated_at = ?1
                 WHERE id = ?2",
                params!["2026-03-20T10:00:00Z", &issue_id],
            )?;
            conn.execute(
                "INSERT INTO agent_run_events (
                    company_id, run_id, agent_id, seq, event_type, stream, level,
                    color, message, payload, created_at
                 ) VALUES (?1, ?2, ?3, 1, 'run_started', 'system', 'info', NULL, ?4, ?5, ?6)",
                params![
                    &company_id,
                    "run-1",
                    &agent_id,
                    "Run started in issue session",
                    Value::Null.to_string(),
                    "2026-03-20T10:00:01Z"
                ],
            )?;
            conn.execute(
                "INSERT INTO agent_run_events (
                    company_id, run_id, agent_id, seq, event_type, stream, level,
                    color, message, payload, created_at
                 ) VALUES (?1, ?2, ?3, 2, 'item.completed.command_execution', 'stdout', 'info', NULL, ?4, ?5, ?6)",
                params![
                    &company_id,
                    "run-1",
                    &agent_id,
                    "{\"type\":\"item.completed\"}",
                    json!({
                        "type": "item.completed",
                        "item": {
                            "type": "command_execution",
                            "command": "cargo test",
                            "aggregated_output": "Ran cargo test for the workspace."
                        }
                    })
                    .to_string(),
                    "2026-03-20T10:00:02Z"
                ],
            )?;
            conn.execute(
                "INSERT INTO agent_run_events (
                    company_id, run_id, agent_id, seq, event_type, stream, level,
                    color, message, payload, created_at
                 ) VALUES (?1, ?2, ?3, 3, 'response.output_text.delta', 'stdout', 'info', NULL, ?4, ?5, ?6)",
                params![
                    &company_id,
                    "run-1",
                    &agent_id,
                    "{\"type\":\"response.output_text.delta\"}",
                    json!({
                        "type": "response.output_text.delta",
                        "delta": "Working through the next step"
                    })
                    .to_string(),
                    "2026-03-20T10:00:03Z"
                ],
            )?;
            Ok(())
        })
        .await
        .unwrap();

        let updates = list_issue_run_card_updates(&db, &issue.company_id)
            .await
            .unwrap();

        assert_eq!(updates.len(), 1);
        assert_eq!(updates[0].issue_id, issue.id);
        assert_eq!(updates[0].issue_status, "in_progress");
        assert_eq!(updates[0].run_status, "running");
        assert_eq!(
            updates[0].summary.as_deref(),
            Some("Ran cargo test for the workspace.")
        );
        assert_eq!(
            updates[0].last_event_type.as_deref(),
            Some("response.output_text.delta")
        );
    }

    #[tokio::test]
    async fn list_issue_run_card_updates_fall_back_to_run_excerpt() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(false),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let agent = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Operator".to_string(),
                role: Some("general".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Finished work".to_string(),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let company_id = company.id.clone();
        let agent_id = agent.id.clone();
        let issue_id = issue.id.clone();
        db.call_with_operation("board.issue.run.card_updates_test.seed_excerpt", move |conn| {
            conn.execute(
                "INSERT INTO agent_runs (
                    id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                    wake_reason, status, stdout_excerpt, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, 'assignment', 'system', 'issue_assigned', 'succeeded', ?5, ?6, ?6)",
                params![
                    "run-2",
                    &company_id,
                    &agent_id,
                    &issue_id,
                    "Implemented the retry guard and updated the daemon tests.",
                    "2026-03-20T11:00:00Z"
                ],
            )?;
            conn.execute(
                "UPDATE issues
                 SET execution_run_id = 'run-2', updated_at = ?1
                 WHERE id = ?2",
                params!["2026-03-20T11:00:00Z", &issue_id],
            )?;
            Ok(())
        })
        .await
        .unwrap();

        let updates = list_issue_run_card_updates(&db, &issue.company_id)
            .await
            .unwrap();

        assert_eq!(updates.len(), 1);
        assert_eq!(
            updates[0].summary.as_deref(),
            Some("Implemented the retry guard and updated the daemon tests.")
        );
        assert_eq!(updates[0].run_status, "succeeded");
    }

    #[tokio::test]
    async fn create_issue_rejects_pending_approval_assignee() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let pending_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        let error = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "Onboard engineer".to_string(),
                assignee_agent_id: Some(pending_agent.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap_err();

        assert!(error
            .to_string()
            .contains("Cannot assign work to pending approval agents"));
    }

    #[tokio::test]
    async fn update_issue_rejects_pending_approval_assignee() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().join("unbound"));
        paths.ensure_dirs().unwrap();
        let db = AsyncDatabase::open(&paths.database_file()).await.unwrap();

        let company = create_company(
            &db,
            &paths,
            CreateCompanyInput {
                name: "Acme".to_string(),
                require_board_approval_for_new_agents: Some(true),
                ..CreateCompanyInput::default()
            },
        )
        .await
        .unwrap();

        let ceo = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let pending_agent = create_agent_hire(
            &db,
            &paths,
            CreateAgentHireInput {
                company_id: company.id.clone(),
                name: "Founding Engineer".to_string(),
                role: Some("founding_engineer".to_string()),
                ..CreateAgentHireInput::default()
            },
        )
        .await
        .unwrap();

        let issue = create_issue(
            &db,
            CreateIssueInput {
                company_id: company.id.clone(),
                title: "CEO bootstrap".to_string(),
                assignee_agent_id: Some(ceo.id.clone()),
                ..CreateIssueInput::default()
            },
        )
        .await
        .unwrap();

        let error = update_issue(
            &db,
            UpdateIssueInput {
                issue_id: issue.id.clone(),
                assignee_agent_id: Some(Some(pending_agent.id.clone())),
                ..UpdateIssueInput::default()
            },
        )
        .await
        .unwrap_err();

        assert!(error
            .to_string()
            .contains("Cannot assign work to pending approval agents"));
    }

    #[tokio::test]
    async fn create_agent_rejects_second_ceo_for_same_company() {
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

        create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap();

        let error = create_agent(
            &db,
            &paths,
            CreateAgentInput {
                company_id: company.id.clone(),
                name: "Another CEO".to_string(),
                role: Some("ceo".to_string()),
                ..CreateAgentInput::default()
            },
        )
        .await
        .unwrap_err();

        match error {
            BoardError::Conflict(message) => {
                assert!(message.contains("CEO"));
            }
            other => panic!("Expected CEO conflict, got {other:?}"),
        }
    }
}
