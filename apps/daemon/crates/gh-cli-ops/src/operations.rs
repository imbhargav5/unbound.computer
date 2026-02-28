use crate::command_runner::GhCommandRunner;
use crate::types::{
    AuthStatusHost, AuthStatusInput, AuthStatusResult, PrCheckItem, PrChecksInput, PrChecksResult,
    PrChecksSummary, PrCreateInput, PrCreateResult, PrListInput, PrListResult, PrMergeInput,
    PrMergeResult, PrViewInput, PullRequestAuthor, PullRequestDetail, PullRequestLabel,
};
use crate::GhCliOpsError;
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

const TIMEOUT_SHORT_SECS: u64 = 30;
const TIMEOUT_LONG_SECS: u64 = 60;
const PR_JSON_FIELDS: &str = "number,title,url,state,isDraft,baseRefName,headRefName,mergeStateStatus,mergeable,reviewDecision,labels,author,body,createdAt,updatedAt,statusCheckRollup";
const CHECKS_JSON_FIELDS: &str =
    "bucket,completedAt,description,event,link,name,startedAt,state,workflow";

pub async fn auth_status(input: AuthStatusInput) -> Result<AuthStatusResult, GhCliOpsError> {
    let runner = GhCommandRunner::new();

    let mut args = vec![
        "auth".to_string(),
        "status".to_string(),
        "--json".to_string(),
        "hosts".to_string(),
    ];

    if let Some(hostname) = input.hostname.as_deref() {
        if hostname.trim().is_empty() {
            return Err(GhCliOpsError::InvalidParams {
                message: "hostname must not be empty".to_string(),
            });
        }
        args.push("--hostname".to_string());
        args.push(hostname.to_string());
    }

    if input.active_only {
        args.push("--active".to_string());
    }

    let output = runner.run(&args, None, TIMEOUT_SHORT_SECS).await?;

    let parsed: GhAuthStatusEnvelope =
        serde_json::from_str(&output.stdout).map_err(|err| GhCliOpsError::ParseError {
            message: format!("failed to parse gh auth status output: {err}"),
        })?;

    let mut hosts = Vec::new();
    for (host_key, entries) in parsed.hosts {
        for entry in entries {
            let state = entry.state.unwrap_or_else(|| "unknown".to_string());
            hosts.push(AuthStatusHost {
                host: entry.host.unwrap_or_else(|| host_key.clone()),
                login: entry.login,
                state,
                active: entry.active.unwrap_or(false),
                token_source: entry.token_source,
                git_protocol: entry.git_protocol,
                error: entry.error,
            });
        }
    }

    hosts.sort_by(|a, b| a.host.cmp(&b.host).then_with(|| a.login.cmp(&b.login)));

    let authenticated_host_count = hosts
        .iter()
        .filter(|h| is_authenticated_state(&h.state) && h.error.is_none())
        .count();

    Ok(AuthStatusResult {
        hosts,
        authenticated_host_count,
    })
}

pub async fn pr_create(
    working_dir: &Path,
    input: PrCreateInput,
) -> Result<PrCreateResult, GhCliOpsError> {
    if input.title.trim().is_empty() {
        return Err(GhCliOpsError::InvalidParams {
            message: "title is required".to_string(),
        });
    }

    let runner = GhCommandRunner::new();

    let mut args = vec![
        "pr".to_string(),
        "create".to_string(),
        "--title".to_string(),
        input.title.clone(),
        "--body".to_string(),
        input.body.clone().unwrap_or_default(),
    ];

    if let Some(base) = input.base.as_deref() {
        if !base.trim().is_empty() {
            args.push("--base".to_string());
            args.push(base.to_string());
        }
    }

    if let Some(head) = input.head.as_deref() {
        if !head.trim().is_empty() {
            args.push("--head".to_string());
            args.push(head.to_string());
        }
    }

    if input.draft {
        args.push("--draft".to_string());
    }

    for reviewer in input.reviewers.iter().filter(|v| !v.trim().is_empty()) {
        args.push("--reviewer".to_string());
        args.push(reviewer.to_string());
    }

    for label in input.labels.iter().filter(|v| !v.trim().is_empty()) {
        args.push("--label".to_string());
        args.push(label.to_string());
    }

    if input.maintainer_can_modify == Some(false) {
        args.push("--no-maintainer-edit".to_string());
    }

    let output = runner
        .run(&args, Some(working_dir), TIMEOUT_LONG_SECS)
        .await?;

    let url = extract_url(&output.stdout).ok_or_else(|| GhCliOpsError::ParseError {
        message: "could not extract pull request URL from gh pr create output".to_string(),
    })?;

    let pull_request = pr_view(
        working_dir,
        PrViewInput {
            selector: Some(url.clone()),
        },
    )
    .await?;

    Ok(PrCreateResult { url, pull_request })
}

pub async fn pr_view(
    working_dir: &Path,
    input: PrViewInput,
) -> Result<PullRequestDetail, GhCliOpsError> {
    let runner = GhCommandRunner::new();

    let mut args = vec!["pr".to_string(), "view".to_string()];

    if let Some(selector) = input.selector.as_deref() {
        if !selector.trim().is_empty() {
            args.push(selector.to_string());
        }
    }

    args.push("--json".to_string());
    args.push(PR_JSON_FIELDS.to_string());

    let output = runner
        .run(&args, Some(working_dir), TIMEOUT_SHORT_SECS)
        .await?;
    let parsed: GhPullRequest =
        serde_json::from_str(&output.stdout).map_err(|err| GhCliOpsError::ParseError {
            message: format!("failed to parse gh pr view output: {err}"),
        })?;

    Ok(map_pull_request(parsed))
}

pub async fn pr_list(working_dir: &Path, input: PrListInput) -> Result<PrListResult, GhCliOpsError> {
    let runner = GhCommandRunner::new();

    let limit = if input.limit == 0 { 20 } else { input.limit };

    let mut args = vec![
        "pr".to_string(),
        "list".to_string(),
        "--state".to_string(),
        input.state.as_flag_value().to_string(),
        "--limit".to_string(),
        limit.to_string(),
        "--json".to_string(),
        PR_JSON_FIELDS.to_string(),
    ];

    if let Some(base) = input.base.as_deref() {
        if !base.trim().is_empty() {
            args.push("--base".to_string());
            args.push(base.to_string());
        }
    }

    if let Some(head) = input.head.as_deref() {
        if !head.trim().is_empty() {
            args.push("--head".to_string());
            args.push(head.to_string());
        }
    }

    let output = runner
        .run(&args, Some(working_dir), TIMEOUT_SHORT_SECS)
        .await?;
    let parsed: Vec<GhPullRequest> =
        serde_json::from_str(&output.stdout).map_err(|err| GhCliOpsError::ParseError {
            message: format!("failed to parse gh pr list output: {err}"),
        })?;

    let pull_requests = parsed.into_iter().map(map_pull_request).collect::<Vec<_>>();
    let count = pull_requests.len();

    Ok(PrListResult {
        pull_requests,
        count,
    })
}

pub async fn pr_checks(
    working_dir: &Path,
    input: PrChecksInput,
) -> Result<PrChecksResult, GhCliOpsError> {
    let runner = GhCommandRunner::new();

    let mut args = vec!["pr".to_string(), "checks".to_string()];

    if let Some(selector) = input.selector.as_deref() {
        if !selector.trim().is_empty() {
            args.push(selector.to_string());
        }
    }

    args.push("--json".to_string());
    args.push(CHECKS_JSON_FIELDS.to_string());

    let output = runner
        .run(&args, Some(working_dir), TIMEOUT_SHORT_SECS)
        .await?;
    let parsed: Vec<GhPrCheck> =
        serde_json::from_str(&output.stdout).map_err(|err| GhCliOpsError::ParseError {
            message: format!("failed to parse gh pr checks output: {err}"),
        })?;

    let checks = parsed
        .iter()
        .map(|check| PrCheckItem {
            name: check.name.clone(),
            state: check.state.clone(),
            bucket: check.bucket.clone(),
            workflow: check.workflow.clone(),
            description: check.description.clone(),
            event: check.event.clone(),
            link: check.link.clone(),
            started_at: check.started_at.clone(),
            completed_at: check.completed_at.clone(),
        })
        .collect::<Vec<_>>();

    let summary = summarize_checks(&parsed);

    Ok(PrChecksResult { checks, summary })
}

pub async fn pr_merge(
    working_dir: &Path,
    input: PrMergeInput,
) -> Result<PrMergeResult, GhCliOpsError> {
    let selector = if let Some(selector) = input.selector.as_ref().filter(|s| !s.trim().is_empty())
    {
        selector.to_string()
    } else {
        let current = pr_view(working_dir, PrViewInput::default()).await?;
        current.number.to_string()
    };

    let runner = GhCommandRunner::new();

    let mut args = vec![
        "pr".to_string(),
        "merge".to_string(),
        selector.clone(),
        input.merge_method.as_flag().to_string(),
    ];

    if input.delete_branch {
        args.push("--delete-branch".to_string());
    }

    if let Some(subject) = input.subject.as_deref() {
        if !subject.trim().is_empty() {
            args.push("--subject".to_string());
            args.push(subject.to_string());
        }
    }

    if let Some(body) = input.body.as_deref() {
        args.push("--body".to_string());
        args.push(body.to_string());
    }

    runner
        .run(&args, Some(working_dir), TIMEOUT_LONG_SECS)
        .await?;

    let pull_request = pr_view(
        working_dir,
        PrViewInput {
            selector: Some(selector),
        },
    )
    .await?;

    Ok(PrMergeResult {
        merged: true,
        merge_method: input.merge_method,
        deleted_branch: input.delete_branch,
        pull_request,
    })
}

fn summarize_checks(checks: &[GhPrCheck]) -> PrChecksSummary {
    let mut summary = PrChecksSummary {
        total: checks.len(),
        ..PrChecksSummary::default()
    };

    for check in checks {
        let bucket = check
            .bucket
            .as_deref()
            .or(check.state.as_deref())
            .unwrap_or("unknown")
            .to_ascii_lowercase();

        if bucket.contains("pass") || bucket.contains("success") {
            summary.passing += 1;
        } else if bucket.contains("fail") || bucket.contains("error") {
            summary.failing += 1;
        } else if bucket.contains("pending")
            || bucket.contains("queued")
            || bucket.contains("in_progress")
        {
            summary.pending += 1;
        } else if bucket.contains("skip") {
            summary.skipped += 1;
        } else if bucket.contains("cancel") {
            summary.cancelled += 1;
        }
    }

    summary
}

fn extract_url(output: &str) -> Option<String> {
    output
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with("http://") || line.starts_with("https://"))
        .map(str::to_string)
}

fn map_pull_request(pr: GhPullRequest) -> PullRequestDetail {
    PullRequestDetail {
        number: pr.number,
        title: pr.title,
        url: pr.url,
        state: pr.state,
        is_draft: pr.is_draft,
        base_ref_name: pr.base_ref_name,
        head_ref_name: pr.head_ref_name,
        merge_state_status: pr.merge_state_status,
        mergeable: pr.mergeable,
        review_decision: pr.review_decision,
        author: pr.author.map(|a| PullRequestAuthor { login: a.login }),
        labels: pr
            .labels
            .into_iter()
            .map(|label| PullRequestLabel { name: label.name })
            .collect(),
        body: pr.body,
        created_at: pr.created_at,
        updated_at: pr.updated_at,
        status_check_rollup: pr.status_check_rollup,
    }
}

fn is_authenticated_state(state: &str) -> bool {
    let state_lower = state.to_ascii_lowercase();
    !(state_lower.contains("error")
        || state_lower.contains("invalid")
        || state_lower.contains("unauth"))
}

#[derive(Debug, Deserialize)]
struct GhAuthStatusEnvelope {
    hosts: HashMap<String, Vec<GhAuthHostEntry>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhAuthHostEntry {
    state: Option<String>,
    error: Option<String>,
    active: Option<bool>,
    host: Option<String>,
    login: Option<String>,
    token_source: Option<String>,
    git_protocol: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhPullRequest {
    number: i64,
    title: String,
    url: String,
    state: String,
    #[serde(default)]
    is_draft: bool,
    base_ref_name: Option<String>,
    head_ref_name: Option<String>,
    merge_state_status: Option<String>,
    mergeable: Option<String>,
    review_decision: Option<String>,
    #[serde(default)]
    labels: Vec<GhLabel>,
    author: Option<GhAuthor>,
    body: Option<String>,
    created_at: Option<String>,
    updated_at: Option<String>,
    status_check_rollup: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct GhLabel {
    name: String,
}

#[derive(Debug, Deserialize)]
struct GhAuthor {
    login: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhPrCheck {
    name: String,
    state: Option<String>,
    bucket: Option<String>,
    workflow: Option<String>,
    description: Option<String>,
    event: Option<String>,
    link: Option<String>,
    started_at: Option<String>,
    completed_at: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_url_picks_https_line() {
        let output = "Creating pull request...\nhttps://github.com/owner/repo/pull/42\n";
        let url = extract_url(output).expect("url");
        assert_eq!(url, "https://github.com/owner/repo/pull/42");
    }

    #[test]
    fn summarize_checks_counts_buckets() {
        let checks = vec![
            GhPrCheck {
                name: "unit".to_string(),
                state: Some("completed".to_string()),
                bucket: Some("pass".to_string()),
                workflow: None,
                description: None,
                event: None,
                link: None,
                started_at: None,
                completed_at: None,
            },
            GhPrCheck {
                name: "lint".to_string(),
                state: Some("completed".to_string()),
                bucket: Some("fail".to_string()),
                workflow: None,
                description: None,
                event: None,
                link: None,
                started_at: None,
                completed_at: None,
            },
            GhPrCheck {
                name: "deploy".to_string(),
                state: Some("queued".to_string()),
                bucket: Some("pending".to_string()),
                workflow: None,
                description: None,
                event: None,
                link: None,
                started_at: None,
                completed_at: None,
            },
        ];

        let summary = summarize_checks(&checks);
        assert_eq!(summary.total, 3);
        assert_eq!(summary.passing, 1);
        assert_eq!(summary.failing, 1);
        assert_eq!(summary.pending, 1);
    }

    #[test]
    fn parse_auth_status_hosts() {
        let json = r#"{
            "hosts": {
                "github.com": [{
                    "state": "ok",
                    "active": true,
                    "host": "github.com",
                    "login": "alice",
                    "tokenSource": "default",
                    "gitProtocol": "ssh"
                }]
            }
        }"#;

        let parsed: GhAuthStatusEnvelope = serde_json::from_str(json).expect("parse");
        assert!(parsed.hosts.contains_key("github.com"));
    }

    #[test]
    fn parse_pull_request_view_payload() {
        let json = r#"{
            "number": 42,
            "title": "Test PR",
            "url": "https://github.com/owner/repo/pull/42",
            "state": "OPEN",
            "isDraft": false,
            "baseRefName": "main",
            "headRefName": "feature/test",
            "labels": [{"name": "bug"}],
            "author": {"login": "alice"}
        }"#;

        let parsed: GhPullRequest = serde_json::from_str(json).expect("parse");
        let mapped = map_pull_request(parsed);
        assert_eq!(mapped.number, 42);
        assert_eq!(mapped.title, "Test PR");
        assert_eq!(mapped.labels.len(), 1);
    }
}
