use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuthStatusInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hostname: Option<String>,
    #[serde(default)]
    pub active_only: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthStatusHost {
    pub host: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub login: Option<String>,
    pub state: String,
    pub active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub git_protocol: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthStatusResult {
    pub hosts: Vec<AuthStatusHost>,
    pub authenticated_host_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullRequestAuthor {
    pub login: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullRequestLabel {
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullRequestDetail {
    pub number: i64,
    pub title: String,
    pub url: String,
    pub state: String,
    pub is_draft: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base_ref_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub head_ref_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub merge_state_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mergeable: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub review_decision: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<PullRequestAuthor>,
    pub labels: Vec<PullRequestLabel>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status_check_rollup: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrCreateInput {
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub head: Option<String>,
    #[serde(default)]
    pub draft: bool,
    #[serde(default)]
    pub reviewers: Vec<String>,
    #[serde(default)]
    pub labels: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub maintainer_can_modify: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrCreateResult {
    pub url: String,
    pub pull_request: PullRequestDetail,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrViewInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selector: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PrListState {
    Open,
    Closed,
    Merged,
    All,
}

impl Default for PrListState {
    fn default() -> Self {
        Self::Open
    }
}

impl PrListState {
    pub fn as_flag_value(&self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::Closed => "closed",
            Self::Merged => "merged",
            Self::All => "all",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrListInput {
    #[serde(default)]
    pub state: PrListState,
    #[serde(default = "default_pr_list_limit")]
    pub limit: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub base: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub head: Option<String>,
}

impl Default for PrListInput {
    fn default() -> Self {
        Self {
            state: PrListState::Open,
            limit: default_pr_list_limit(),
            base: None,
            head: None,
        }
    }
}

const fn default_pr_list_limit() -> usize {
    20
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrListResult {
    pub pull_requests: Vec<PullRequestDetail>,
    pub count: usize,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrChecksInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selector: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrCheckItem {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bucket: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workflow: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub event: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrChecksSummary {
    pub total: usize,
    pub passing: usize,
    pub failing: usize,
    pub pending: usize,
    pub skipped: usize,
    pub cancelled: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrChecksResult {
    pub checks: Vec<PrCheckItem>,
    pub summary: PrChecksSummary,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PrMergeMethod {
    Merge,
    Squash,
    Rebase,
}

impl Default for PrMergeMethod {
    fn default() -> Self {
        Self::Squash
    }
}

impl PrMergeMethod {
    pub fn as_flag(&self) -> &'static str {
        match self {
            Self::Merge => "--merge",
            Self::Squash => "--squash",
            Self::Rebase => "--rebase",
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrMergeInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selector: Option<String>,
    #[serde(default)]
    pub merge_method: PrMergeMethod,
    #[serde(default)]
    pub delete_branch: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrMergeResult {
    pub merged: bool,
    pub merge_method: PrMergeMethod,
    pub deleted_branch: bool,
    pub pull_request: PullRequestDetail,
}
