use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Company {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub status: String,
    pub issue_prefix: String,
    pub issue_counter: i64,
    pub budget_monthly_cents: i64,
    pub spent_monthly_cents: i64,
    pub require_board_approval_for_new_agents: bool,
    pub brand_color: Option<String>,
    pub ceo_agent_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Agent {
    pub id: String,
    pub company_id: String,
    pub name: String,
    pub slug: String,
    pub role: String,
    pub title: Option<String>,
    pub icon: Option<String>,
    pub status: String,
    pub reports_to: Option<String>,
    pub capabilities: Option<String>,
    pub adapter_type: String,
    pub adapter_config: serde_json::Value,
    pub runtime_config: serde_json::Value,
    pub budget_monthly_cents: i64,
    pub spent_monthly_cents: i64,
    pub permissions: serde_json::Value,
    pub last_heartbeat_at: Option<String>,
    pub metadata: Option<serde_json::Value>,
    pub home_path: Option<String>,
    pub instructions_path: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectWorkspace {
    pub id: String,
    pub company_id: String,
    pub project_id: String,
    pub name: String,
    pub cwd: Option<String>,
    pub repo_url: Option<String>,
    pub repo_ref: Option<String>,
    pub metadata: Option<serde_json::Value>,
    pub is_primary: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub company_id: String,
    pub goal_id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub status: String,
    pub lead_agent_id: Option<String>,
    pub target_date: Option<String>,
    pub color: Option<String>,
    pub execution_workspace_policy: Option<serde_json::Value>,
    pub archived_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub primary_workspace: Option<ProjectWorkspace>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Goal {
    pub id: String,
    pub company_id: String,
    pub title: String,
    pub description: Option<String>,
    pub level: String,
    pub status: String,
    pub parent_id: Option<String>,
    pub owner_agent_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub id: String,
    pub company_id: String,
    pub project_id: Option<String>,
    pub goal_id: Option<String>,
    pub parent_id: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub status: String,
    pub priority: String,
    pub assignee_agent_id: Option<String>,
    pub assignee_user_id: Option<String>,
    pub checkout_run_id: Option<String>,
    pub execution_run_id: Option<String>,
    pub execution_agent_name_key: Option<String>,
    pub execution_locked_at: Option<String>,
    pub created_by_agent_id: Option<String>,
    pub created_by_user_id: Option<String>,
    pub issue_number: Option<i64>,
    pub identifier: Option<String>,
    pub request_depth: i64,
    pub billing_code: Option<String>,
    pub assignee_adapter_overrides: Option<serde_json::Value>,
    pub execution_workspace_settings: Option<serde_json::Value>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub cancelled_at: Option<String>,
    pub hidden_at: Option<String>,
    pub workspace_session_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IssueComment {
    pub id: String,
    pub company_id: String,
    pub issue_id: String,
    pub author_agent_id: Option<String>,
    pub author_user_id: Option<String>,
    pub body: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Approval {
    pub id: String,
    pub company_id: String,
    pub approval_type: String,
    pub requested_by_agent_id: Option<String>,
    pub requested_by_user_id: Option<String>,
    pub status: String,
    pub payload: serde_json::Value,
    pub decision_note: Option<String>,
    pub decided_by_user_id: Option<String>,
    pub decided_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    pub session_id: String,
    pub repository_id: String,
    pub company_id: Option<String>,
    pub project_id: Option<String>,
    pub issue_id: Option<String>,
    pub agent_id: Option<String>,
    pub title: String,
    pub status: String,
    pub workspace_type: String,
    pub workspace_status: String,
    pub workspace_repo_path: Option<String>,
    pub workspace_branch: Option<String>,
    pub workspace_metadata: serde_json::Value,
    pub issue_identifier: Option<String>,
    pub issue_title: Option<String>,
    pub project_name: Option<String>,
    pub agent_name: Option<String>,
    pub created_at: String,
    pub last_accessed_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CreateCompanyInput {
    pub name: String,
    pub description: Option<String>,
    pub budget_monthly_cents: Option<i64>,
    pub brand_color: Option<String>,
    pub require_board_approval_for_new_agents: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UpdateCompanyInput {
    pub company_id: String,
    pub brand_color: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CreateAgentInput {
    pub company_id: String,
    pub name: String,
    pub role: Option<String>,
    pub title: Option<String>,
    pub icon: Option<String>,
    pub reports_to: Option<String>,
    pub capabilities: Option<String>,
    pub adapter_type: Option<String>,
    pub adapter_config: Option<serde_json::Value>,
    pub runtime_config: Option<serde_json::Value>,
    pub budget_monthly_cents: Option<i64>,
    pub permissions: Option<serde_json::Value>,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CreateProjectInput {
    pub company_id: String,
    pub goal_id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub status: Option<String>,
    pub lead_agent_id: Option<String>,
    pub target_date: Option<String>,
    pub color: Option<String>,
    pub execution_workspace_policy: Option<serde_json::Value>,
    pub repo_path: Option<String>,
    pub repo_url: Option<String>,
    pub repo_ref: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CreateIssueInput {
    pub company_id: String,
    pub project_id: Option<String>,
    pub goal_id: Option<String>,
    pub parent_id: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub status: Option<String>,
    pub priority: Option<String>,
    pub assignee_agent_id: Option<String>,
    pub assignee_user_id: Option<String>,
    pub created_by_agent_id: Option<String>,
    pub created_by_user_id: Option<String>,
    pub billing_code: Option<String>,
    pub assignee_adapter_overrides: Option<serde_json::Value>,
    pub execution_workspace_settings: Option<serde_json::Value>,
    pub label_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AddIssueCommentInput {
    pub company_id: String,
    pub issue_id: String,
    pub author_agent_id: Option<String>,
    pub author_user_id: Option<String>,
    pub body: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct IssueListFilter {
    pub company_id: String,
    pub project_id: Option<String>,
    pub parent_id: Option<String>,
    pub assignee_agent_id: Option<String>,
    pub include_hidden: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ApprovalDecisionInput {
    pub approval_id: String,
    pub decided_by_user_id: Option<String>,
    pub decision_note: Option<String>,
}
