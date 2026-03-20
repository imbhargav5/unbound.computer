use crate::app::agent_cli::{
    agent_cli_label as shared_agent_cli_label, build_agent_cli_config_from_adapter,
    detect_agent_cli_kind, AgentCliConfig, AgentCliEvent, AgentCliKind, AgentCliProcess,
};
use crate::app::{
    ensure_issue_workspace, ensure_workspace_repository, issue_has_attached_workspace_target,
};
use crate::armin_adapter::DaemonArmin;
use crate::observability::{current_trace_context, spawn_in_current_span};
use crate::utils::SessionSecretCache;
use agent_session_sqlite_persist_core::{
    CodingSessionStatus, NewMessage, NewSession, RepositoryId, Session, SessionId, SessionWriter,
};
use chrono::Utc;
use daemon_board::{
    service, summarize_agent_run_event, summarize_agent_run_result, summarize_agent_run_text,
    Agent, AgentRun, Approval, BoardError, CreateAgentDecisionApprovalInput, Issue, IssueComment,
};
use daemon_config_and_utils::Paths;
use daemon_database::{queries, AsyncDatabase, NewRepository};
use daemon_ipc::{Event, EventType, SubscriptionManager};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, Notify};
use tokio::time::{sleep, Duration};
use tracing::{error, warn};
use uuid::Uuid;
use workspace_resolver::{resolve_working_dir_from_str, ResolveError};

const STATUS_QUEUED: &str = "queued";
const STATUS_RUNNING: &str = "running";
const STATUS_SUCCEEDED: &str = "succeeded";
const STATUS_FAILED: &str = "failed";
const STATUS_CANCELLED: &str = "cancelled";
const STATUS_TIMED_OUT: &str = "timed_out";

const SOURCE_TIMER: &str = "timer";
const SOURCE_ON_DEMAND: &str = "on_demand";

const TRIGGER_MANUAL: &str = "manual";
const TRIGGER_SYSTEM: &str = "system";

const ERROR_CODE_PROCESS_LOST: &str = "process_lost";

#[derive(Clone)]
pub struct AgentRunCoordinator {
    db: AsyncDatabase,
    paths: Arc<Paths>,
    armin: Arc<DaemonArmin>,
    db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
    session_secret_cache: SessionSecretCache,
    subscriptions: SubscriptionManager,
    claude_processes: Arc<Mutex<HashMap<String, broadcast::Sender<()>>>>,
    device_id: Arc<Mutex<Option<String>>>,
    run_processes: Arc<Mutex<HashMap<String, broadcast::Sender<()>>>>,
    queue_notify: Arc<Notify>,
}

#[derive(Debug, Clone)]
pub struct AgentRunEnqueueRequest {
    pub agent_id: String,
    pub company_id: Option<String>,
    pub invocation_source: String,
    pub trigger_detail: Option<String>,
    pub wake_reason: Option<String>,
    pub payload: Option<Value>,
    pub prompt: Option<String>,
    pub requested_by_actor_type: Option<String>,
    pub requested_by_actor_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AgentRunLogChunk {
    pub content: String,
    pub next_offset: u64,
    pub done: bool,
}

#[derive(Debug, Clone)]
struct RunLaunchContext {
    run: AgentRun,
}

#[derive(Debug, Clone)]
struct RunSessionContext {
    local_session_id: String,
    local_session_title: String,
    task_session_ref: RunTaskSessionRef,
}

#[derive(Debug, Clone)]
struct RunTaskSessionRef {
    adapter_type: String,
    task_key: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum IssueRunSessionStrategy {
    AttachedWorkspace,
    ProjectRoot,
    AgentHome,
}

#[derive(Debug, Clone)]
struct RunCompletion {
    status: String,
    error: Option<String>,
    error_code: Option<String>,
    exit_code: Option<i32>,
    signal: Option<String>,
    usage_json: Option<Value>,
    result_json: Option<Value>,
    session_id_after: Option<String>,
    stdout_excerpt: Option<String>,
    stderr_excerpt: Option<String>,
    external_run_id: Option<String>,
}

#[derive(Debug, Clone)]
struct AgentDecisionRequest {
    provider: &'static str,
    provider_request_id: Option<String>,
    question: String,
    options: Vec<String>,
    questions: Option<Value>,
    raw_request: Value,
}

impl AgentRunCoordinator {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        db: AsyncDatabase,
        paths: Arc<Paths>,
        armin: Arc<DaemonArmin>,
        db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
        session_secret_cache: SessionSecretCache,
        subscriptions: SubscriptionManager,
        claude_processes: Arc<Mutex<HashMap<String, broadcast::Sender<()>>>>,
        device_id: Arc<Mutex<Option<String>>>,
    ) -> Self {
        Self {
            db,
            paths,
            armin,
            db_encryption_key,
            session_secret_cache,
            subscriptions,
            claude_processes,
            device_id,
            run_processes: Arc::new(Mutex::new(HashMap::new())),
            queue_notify: Arc::new(Notify::new()),
        }
    }

    pub fn spawn_background(self: Arc<Self>) {
        let queue_runner = self.clone();
        spawn_in_current_span(async move {
            queue_runner.queue_loop().await;
        });

        let reaper = self;
        spawn_in_current_span(async move {
            reaper.stale_run_reaper_loop().await;
        });
    }

    pub async fn enqueue_run(
        &self,
        request: AgentRunEnqueueRequest,
    ) -> Result<AgentRun, BoardError> {
        let agent_id = request.agent_id.trim().to_string();
        if agent_id.is_empty() {
            return Err(BoardError::InvalidInput("agent_id is required".to_string()));
        }

        let company_id = match request.company_id.clone() {
            Some(company_id) => company_id,
            None => self.agent_company_id(&agent_id).await?,
        };
        let now = now_rfc3339();
        let payload = request.payload.unwrap_or(Value::Null);
        let payload_text = if payload.is_null() {
            None
        } else {
            Some(payload.to_string())
        };
        let issue_id = issue_id_from_value(&payload);
        let idempotency_key = build_idempotency_key(
            &agent_id,
            &request.invocation_source,
            request.trigger_detail.as_deref(),
            request.wake_reason.as_deref(),
            issue_id.as_deref(),
            request.prompt.as_deref(),
        );
        let prompt = request.prompt.clone();
        let trigger_detail = request.trigger_detail.clone();
        let wake_reason = request.wake_reason.clone();
        let invocation_source = request.invocation_source.clone();
        let requested_by_actor_type = request.requested_by_actor_type.clone();
        let requested_by_actor_id = request.requested_by_actor_id.clone();
        let log_ref = self
            .paths
            .agent_run_log_file("placeholder")
            .parent()
            .map(|_| ())
            .ok_or_else(|| {
                BoardError::Runtime("Run logs directory could not be resolved".to_string())
            })?;
        let _ = log_ref;

        let paths = self.paths.clone();
        let run_id = self
            .db
            .call_with_operation("agent_run.enqueue", move |conn| {
                let tx = conn.unchecked_transaction()?;

                if let Some(key) = idempotency_key.as_ref() {
                    let existing: Option<String> = tx
                        .query_row(
                            "SELECT r.id
                             FROM agent_runs r
                             JOIN agent_wakeup_requests w ON w.id = r.wakeup_request_id
                             WHERE r.agent_id = ?1
                               AND r.status = 'queued'
                               AND w.status = 'queued'
                               AND COALESCE(w.idempotency_key, '') = ?2
                             ORDER BY r.created_at DESC
                             LIMIT 1",
                            params![agent_id, key],
                            |row| row.get(0),
                        )
                        .optional()?;
                    if let Some(existing_run_id) = existing {
                        tx.execute(
                            "UPDATE agent_wakeup_requests
                             SET coalesced_count = coalesced_count + 1,
                                 requested_at = ?1,
                                 updated_at = ?1
                             WHERE run_id = ?2",
                            params![now, existing_run_id],
                        )?;
                        tx.commit()?;
                        return Ok(existing_run_id);
                    }
                }

                let run_id = Uuid::new_v4().to_string();
                let wakeup_request_id = Uuid::new_v4().to_string();
                let context_snapshot = json!({
                    "payload": payload,
                    "prompt": prompt,
                    "agent_id": agent_id,
                    "company_id": company_id,
                    "issue_id": issue_id,
                    "invocation_source": invocation_source,
                    "trigger_detail": trigger_detail,
                    "wake_reason": wake_reason,
                });
                let run_log_ref = paths
                    .agent_run_log_file(&run_id)
                    .to_string_lossy()
                    .to_string();

                tx.execute(
                    "INSERT INTO agent_wakeup_requests (
                        id, company_id, agent_id, source, trigger_detail, reason, payload,
                        status, coalesced_count, requested_by_actor_type, requested_by_actor_id,
                        idempotency_key, run_id, requested_at, created_at, updated_at
                     ) VALUES (
                        ?1, ?2, ?3, ?4, ?5, ?6, ?7,
                        'queued', 0, ?8, ?9,
                        ?10, ?11, ?12, ?12, ?12
                     )",
                    params![
                        wakeup_request_id,
                        company_id,
                        agent_id,
                        invocation_source,
                        trigger_detail,
                        wake_reason,
                        payload_text,
                        requested_by_actor_type,
                        requested_by_actor_id,
                        idempotency_key,
                        run_id,
                        now,
                    ],
                )?;

                tx.execute(
                    "INSERT INTO agent_runs (
                        id, company_id, agent_id, issue_id, invocation_source, trigger_detail,
                        wake_reason, status, started_at, finished_at, error, wakeup_request_id,
                        exit_code, signal, usage_json, result_json, session_id_before,
                        session_id_after, log_store, log_ref, log_bytes, log_sha256,
                        log_compressed, stdout_excerpt, stderr_excerpt, error_code,
                        external_run_id, context_snapshot, created_at, updated_at
                     ) VALUES (
                        ?1, ?2, ?3, ?4, ?5, ?6,
                        ?7, 'queued', NULL, NULL, NULL, ?8,
                        NULL, NULL, NULL, NULL, NULL,
                        NULL, 'file', ?9, 0, NULL,
                        0, NULL, NULL, NULL,
                        NULL, ?10, ?11, ?11
                     )",
                    params![
                        run_id,
                        company_id,
                        agent_id,
                        issue_id,
                        invocation_source,
                        trigger_detail,
                        wake_reason,
                        wakeup_request_id,
                        run_log_ref,
                        context_snapshot.to_string(),
                        now,
                    ],
                )?;

                if let Some(issue_id) = issue_id {
                    if matches!(wake_reason.as_deref(), Some("issue_checked_out")) {
                        tx.execute(
                            "UPDATE issues
                             SET checkout_run_id = ?1, updated_at = ?2
                             WHERE id = ?3",
                            params![run_id, now, issue_id],
                        )?;
                    } else {
                        tx.execute(
                            "UPDATE issues
                             SET execution_run_id = ?1,
                                 execution_locked_at = ?2,
                                 updated_at = ?2
                             WHERE id = ?3",
                            params![run_id, now, issue_id],
                        )?;
                    }
                }

                tx.commit()?;
                Ok(run_id)
            })
            .await?;

        self.queue_notify.notify_waiters();

        service::get_agent_run(&self.db, &run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found after enqueue".to_string()))
    }

    pub async fn enqueue_manual_run(
        &self,
        agent_id: &str,
        issue_id: Option<String>,
        prompt: Option<String>,
    ) -> Result<AgentRun, BoardError> {
        let payload = issue_id.map(|issue_id| json!({ "issue_id": issue_id }));
        self.enqueue_run(AgentRunEnqueueRequest {
            agent_id: agent_id.to_string(),
            company_id: None,
            invocation_source: SOURCE_ON_DEMAND.to_string(),
            trigger_detail: Some(TRIGGER_MANUAL.to_string()),
            wake_reason: None,
            payload,
            prompt,
            requested_by_actor_type: Some("user".to_string()),
            requested_by_actor_id: Some("local-board".to_string()),
        })
        .await
    }

    pub async fn retry_run(&self, run_id: &str) -> Result<AgentRun, BoardError> {
        let run = service::get_agent_run(&self.db, run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found".to_string()))?;
        if run.status != STATUS_FAILED && run.status != STATUS_TIMED_OUT {
            return Err(BoardError::Conflict(
                "Only failed or timed out runs can be retried".to_string(),
            ));
        }
        let snapshot = run.context_snapshot.clone().unwrap_or(Value::Null);
        let payload = snapshot
            .get("payload")
            .cloned()
            .filter(|value| !value.is_null());
        let prompt = snapshot
            .get("prompt")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned);
        self.enqueue_run(AgentRunEnqueueRequest {
            agent_id: run.agent_id,
            company_id: Some(run.company_id),
            invocation_source: run.invocation_source,
            trigger_detail: run.trigger_detail,
            wake_reason: run.wake_reason,
            payload,
            prompt,
            requested_by_actor_type: Some("system".to_string()),
            requested_by_actor_id: Some(run.id),
        })
        .await
    }

    pub async fn resume_run(&self, run_id: &str) -> Result<AgentRun, BoardError> {
        let run = service::get_agent_run(&self.db, run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found".to_string()))?;
        if run.status != STATUS_FAILED || run.error_code.as_deref() != Some(ERROR_CODE_PROCESS_LOST)
        {
            return Err(BoardError::Conflict(
                "Only failed process_lost runs can be resumed".to_string(),
            ));
        }
        let snapshot = run.context_snapshot.clone().unwrap_or(Value::Null);
        let payload = snapshot
            .get("payload")
            .cloned()
            .filter(|value| !value.is_null());
        let prompt = snapshot
            .get("prompt")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned);
        self.enqueue_run(AgentRunEnqueueRequest {
            agent_id: run.agent_id,
            company_id: Some(run.company_id),
            invocation_source: SOURCE_ON_DEMAND.to_string(),
            trigger_detail: Some(TRIGGER_SYSTEM.to_string()),
            wake_reason: run.wake_reason,
            payload,
            prompt,
            requested_by_actor_type: Some("system".to_string()),
            requested_by_actor_id: Some(run.id),
        })
        .await
    }

    pub async fn cancel_run(&self, run_id: &str) -> Result<AgentRun, BoardError> {
        let run = service::get_agent_run(&self.db, run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found".to_string()))?;

        match run.status.as_str() {
            STATUS_QUEUED => {
                let now = now_rfc3339();
                let run_id = run.id.clone();
                let wakeup_request_id = run.wakeup_request_id.clone();
                self.db
                    .call_with_operation("agent_run.cancel.queued", move |conn| {
                        let tx = conn.unchecked_transaction()?;
                        tx.execute(
                            "UPDATE agent_runs
                             SET status = 'cancelled',
                                 error = 'Cancelled before execution',
                                 error_code = 'cancelled',
                                 finished_at = ?1,
                                 updated_at = ?1
                             WHERE id = ?2 AND status = 'queued'",
                            params![now, run_id],
                        )?;
                        if let Some(wakeup_request_id) = wakeup_request_id {
                            tx.execute(
                                "UPDATE agent_wakeup_requests
                                 SET status = 'cancelled', finished_at = ?1, updated_at = ?1
                                 WHERE id = ?2",
                                params![now, wakeup_request_id],
                            )?;
                        }
                        tx.commit()?;
                        Ok(())
                    })
                    .await?;
                let cancelled_run = service::get_agent_run(&self.db, &run.id)
                    .await?
                    .ok_or_else(|| {
                        BoardError::NotFound("Run not found after cancellation".to_string())
                    })?;
                self.record_run_event(
                    &cancelled_run,
                    1,
                    "run_cancelled",
                    Some("system"),
                    Some("info"),
                    Some("Cancelled before execution"),
                    Some(json!({ "reason": "queued_cancel" })),
                )
                .await?;
                return Ok(cancelled_run);
            }
            STATUS_RUNNING => {
                let stop_tx = {
                    let processes = self.run_processes.lock().unwrap();
                    processes.get(run_id).cloned()
                };
                if let Some(stop_tx) = stop_tx {
                    let _ = stop_tx.send(());
                    return service::get_agent_run(&self.db, run_id)
                        .await?
                        .ok_or_else(|| {
                            BoardError::NotFound("Run not found after cancel request".to_string())
                        });
                }
                self.mark_run_as_process_lost(run_id).await?;
                return service::get_agent_run(&self.db, run_id)
                    .await?
                    .ok_or_else(|| {
                        BoardError::NotFound("Run not found after recovery".to_string())
                    });
            }
            _ => {}
        }

        Err(BoardError::Conflict(
            "Only queued or running runs can be cancelled".to_string(),
        ))
    }

    pub async fn read_log_chunk(
        &self,
        run_id: &str,
        offset: u64,
        limit_bytes: usize,
    ) -> Result<AgentRunLogChunk, BoardError> {
        let run = service::get_agent_run(&self.db, run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found".to_string()))?;
        let log_path = run.log_ref.clone().unwrap_or_else(|| {
            self.paths
                .agent_run_log_file(run_id)
                .to_string_lossy()
                .to_string()
        });
        let path = Path::new(&log_path);
        if !path.exists() {
            return Ok(AgentRunLogChunk {
                content: String::new(),
                next_offset: offset,
                done: true,
            });
        }

        let mut file = File::open(path)?;
        let file_len = file.metadata()?.len();
        if offset >= file_len {
            return Ok(AgentRunLogChunk {
                content: String::new(),
                next_offset: file_len,
                done: run.status != STATUS_RUNNING && run.status != STATUS_QUEUED,
            });
        }

        file.seek(SeekFrom::Start(offset))?;
        let mut buffer = vec![0_u8; limit_bytes.max(1024)];
        let read = file.read(&mut buffer)?;
        buffer.truncate(read);
        Ok(AgentRunLogChunk {
            content: String::from_utf8_lossy(&buffer).to_string(),
            next_offset: offset + read as u64,
            done: offset + read as u64 >= file_len && run.status != STATUS_RUNNING,
        })
    }

    async fn queue_loop(self: Arc<Self>) {
        loop {
            match self.process_pending_runs().await {
                Ok(true) => continue,
                Ok(false) => self.queue_notify.notified().await,
                Err(error) => {
                    warn!(error = %error, "Failed to process queued agent runs");
                    sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    async fn stale_run_reaper_loop(self: Arc<Self>) {
        if let Err(error) = self.reap_orphaned_running_runs().await {
            warn!(error = %error, "Failed to reap orphaned runs");
        }
        loop {
            sleep(Duration::from_secs(30)).await;
            if let Err(error) = self.reap_orphaned_running_runs().await {
                warn!(error = %error, "Failed to reap orphaned runs");
            }
        }
    }

    async fn process_pending_runs(&self) -> Result<bool, BoardError> {
        let queued_run_ids = self
            .db
            .call_with_operation("agent_run.queue.pending", move |conn| {
                let mut stmt = conn.prepare(
                    "SELECT id
                     FROM agent_runs
                     WHERE status = 'queued'
                     ORDER BY created_at ASC
                     LIMIT 100",
                )?;
                let rows = stmt
                    .query_map([], |row| row.get::<_, String>(0))?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(rows)
            })
            .await?;

        let mut started_any = false;
        for run_id in queued_run_ids {
            if let Some(context) = self.try_claim_run(&run_id).await? {
                started_any = true;
                let coordinator = self.clone();
                spawn_in_current_span(async move {
                    if let Err(error) = coordinator.execute_run(context).await {
                        error!(error = %error, run_id = %run_id, "Agent run execution failed");
                        if let Err(recovery_error) = coordinator
                            .recover_failed_run_startup(&run_id, &error)
                            .await
                        {
                            error!(
                                error = %recovery_error,
                                run_id = %run_id,
                                "Failed to recover errored agent run"
                            );
                        }
                    }
                });
            }
        }

        Ok(started_any)
    }

    async fn try_claim_run(&self, run_id: &str) -> Result<Option<RunLaunchContext>, BoardError> {
        let run_id = run_id.to_string();
        let run_id_for_fetch = run_id.clone();
        let now = now_rfc3339();
        let claimed = self
            .db
            .call_with_operation("agent_run.queue.claim", move |conn| {
                let tx = conn.unchecked_transaction()?;
                let queued_run: Option<(i64, String, Option<String>, Option<String>, String)> = tx
                    .query_row(
                        "SELECT rowid, agent_id, issue_id, wake_reason, created_at
                         FROM agent_runs
                         WHERE id = ?1 AND status = 'queued'",
                        params![run_id],
                        |row| {
                            Ok((
                                row.get(0)?,
                                row.get(1)?,
                                row.get(2)?,
                                row.get(3)?,
                                row.get(4)?,
                            ))
                        },
                    )
                    .optional()?;
                let Some((rowid, agent_id, issue_id, wake_reason, created_at)) = queued_run else {
                    tx.rollback()?;
                    return Ok(false);
                };

                let running_count: i64 = tx.query_row(
                    "SELECT COUNT(*) FROM agent_runs
                     WHERE agent_id = ?1 AND status = 'running'",
                    params![agent_id],
                    |row| row.get(0),
                )?;
                if running_count > 0 {
                    tx.rollback()?;
                    return Ok(false);
                }

                if queued_run_waits_for_prior_issue_runs(
                    issue_id.as_deref(),
                    wake_reason.as_deref(),
                ) {
                    if let Some(issue_id) = issue_id.as_deref() {
                        if has_older_pending_issue_runs(&tx, issue_id, &created_at, rowid)? {
                            tx.rollback()?;
                            return Ok(false);
                        }
                    }
                }

                tx.execute(
                    "UPDATE agent_runs
                     SET status = 'running',
                         started_at = COALESCE(started_at, ?1),
                         updated_at = ?1
                     WHERE id = ?2 AND status = 'queued'",
                    params![now, run_id],
                )?;
                tx.execute(
                    "UPDATE agent_wakeup_requests
                     SET status = 'claimed', claimed_at = ?1, updated_at = ?1
                     WHERE run_id = ?2",
                    params![now, run_id],
                )?;
                tx.commit()?;
                Ok(true)
            })
            .await?;

        if !claimed {
            return Ok(None);
        }

        let run = service::get_agent_run(&self.db, &run_id_for_fetch)
            .await?
            .ok_or_else(|| BoardError::NotFound("Claimed run not found".to_string()))?;
        Ok(Some(RunLaunchContext { run }))
    }

    async fn execute_run(&self, context: RunLaunchContext) -> Result<(), BoardError> {
        let run = context.run;
        let snapshot = run.context_snapshot.clone().unwrap_or(Value::Null);
        let payload = snapshot.get("payload").cloned().unwrap_or(Value::Null);
        let issue_id = issue_id_from_value(&payload);
        let prompt_override = snapshot
            .get("prompt")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned);
        let agent = service::get_agent(&self.db, &run.agent_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Agent not found for run".to_string()))?;
        let session = self
            .resolve_session_for_run(&agent, issue_id.clone())
            .await?;
        let resolved_workspace =
            resolve_working_dir_from_str(&*self.armin, &session.local_session_id)
                .map_err(map_resolve_error)?;
        let cli_kind = agent_cli_kind(&agent);
        let provider_session_id_before =
            stored_provider_session_id_for_kind(&resolved_workspace.session, cli_kind);
        let resumes_existing_session = provider_session_id_before.as_ref().is_some_and(|_| {
            should_resume_claude_session(
                run.invocation_source.as_str(),
                run.trigger_detail.as_deref(),
                run.wake_reason.as_deref(),
            )
        });
        let prompt = match prompt_override {
            Some(prompt) => prompt,
            None => {
                self.build_prompt(&run, &agent, issue_id.as_deref(), !resumes_existing_session)
                    .await?
            }
        };

        self.db
            .call_with_operation("agent_run.execute.prepare", {
                let run_id = run.id.clone();
                let session_id_before = provider_session_id_before.clone();
                let local_session_id = session.local_session_id.clone();
                let task_session_adapter_type = session.task_session_ref.adapter_type.clone();
                let task_session_key = session.task_session_ref.task_key.clone();
                move |conn| {
                    conn.execute(
                        "UPDATE agent_runs
                         SET session_id_before = ?1,
                             updated_at = ?2,
                             context_snapshot = json_set(
                                 COALESCE(context_snapshot, '{}'),
                                 '$.local_session_id', ?3,
                                 '$.task_session.adapter_type', ?4,
                                 '$.task_session.task_key', ?5
                             )
                         WHERE id = ?6",
                        params![
                            session_id_before,
                            now_rfc3339(),
                            local_session_id,
                            task_session_adapter_type,
                            task_session_key,
                            run_id,
                        ],
                    )?;
                    Ok(())
                }
            })
            .await?;

        let armin_session_id = SessionId::from_string(&session.local_session_id);
        self.append_claude_message(&armin_session_id, &prompt, "agent_run_prompt");

        let config = build_agent_cli_config(
            &agent,
            &prompt,
            resolved_workspace.working_dir,
            if resumes_existing_session {
                provider_session_id_before.as_deref()
            } else {
                None
            },
        );
        let timeout_sec = agent_timeout_sec(&agent);

        let mut process = match AgentCliProcess::spawn(config).await {
            Ok(process) => process,
            Err(error) => {
                let cli_label = agent_cli_label(cli_kind);
                self.finalize_run(
                    &run,
                    issue_id.as_deref(),
                    Some(session.task_session_ref.clone()),
                    RunCompletion {
                        status: STATUS_FAILED.to_string(),
                        error: Some(format!("Failed to spawn {cli_label}: {error}")),
                        error_code: Some("spawn_failed".to_string()),
                        exit_code: None,
                        signal: None,
                        usage_json: None,
                        result_json: None,
                        session_id_after: provider_session_id_before.clone(),
                        stdout_excerpt: None,
                        stderr_excerpt: None,
                        external_run_id: None,
                    },
                )
                .await?;
                self.queue_notify.notify_waiters();
                return Ok(());
            }
        };

        let stop_tx = process.stop_sender();
        {
            let mut processes = self.claude_processes.lock().unwrap();
            processes.insert(session.local_session_id.clone(), stop_tx.clone());
        }
        {
            let mut processes = self.run_processes.lock().unwrap();
            processes.insert(run.id.clone(), stop_tx);
        }

        let mut stream = process.take_stream().ok_or_else(|| {
            BoardError::Runtime(format!(
                "{} stream was unavailable",
                agent_cli_label(cli_kind)
            ))
        })?;
        let mut seq = 1_i64;
        let mut last_status: Option<CodingSessionStatus> = None;
        let mut last_error_message: Option<String> = None;
        let mut terminal_status_written = false;
        let mut stdout_excerpt = String::new();
        let mut stderr_excerpt = String::new();
        let mut usage_json: Option<Value> = None;
        let mut result_json: Option<Value> = None;
        let mut session_id_after = provider_session_id_before.clone();
        let mut external_run_id: Option<String> = None;
        let mut timed_out = false;
        let mut completion = RunCompletion {
            status: STATUS_FAILED.to_string(),
            error: Some(format!(
                "{} run exited unexpectedly",
                agent_cli_label(cli_kind)
            )),
            error_code: Some(ERROR_CODE_PROCESS_LOST.to_string()),
            exit_code: None,
            signal: None,
            usage_json: None,
            result_json: None,
            session_id_after: provider_session_id_before,
            stdout_excerpt: None,
            stderr_excerpt: None,
            external_run_id: None,
        };

        self.write_runtime_status_if_changed(
            &armin_session_id,
            CodingSessionStatus::Running,
            None,
            "agent-run-start",
            &mut last_status,
            &mut last_error_message,
        );
        self.record_run_event(
            &run,
            seq,
            "run_started",
            Some("system"),
            Some("info"),
            Some(&format!("Run started in {}", session.local_session_title)),
            Some(json!({ "local_session_id": session.local_session_id })),
        )
        .await?;
        seq += 1;

        let timeout_deadline = timeout_sec.map(|seconds| sleep(Duration::from_secs(seconds)));
        tokio::pin!(timeout_deadline);
        let mut surfaced_approval_ids = HashSet::new();

        loop {
            let event = if let Some(deadline) = timeout_deadline.as_mut().as_pin_mut() {
                tokio::select! {
                    _ = deadline, if !timed_out => {
                        timed_out = true;
                        let _ = self.record_run_event(
                            &run,
                            seq,
                            "timed_out",
                            Some("system"),
                            Some("warn"),
                            Some("Run timed out; stopping agent process"),
                            Some(json!({ "timeout_sec": timeout_sec })),
                        ).await;
                        seq += 1;
                        let _ = {
                            let processes = self.run_processes.lock().unwrap();
                            processes.get(&run.id).cloned()
                        }.map(|tx| tx.send(()));
                        continue;
                    }
                    next_event = stream.next() => next_event
                }
            } else {
                stream.next().await
            };

            let Some(event) = event else {
                break;
            };

            match &event {
                AgentCliEvent::Json { raw, json } => {
                    let decision_request = extract_agent_decision_request(cli_kind, json);
                    self.append_claude_message(
                        &armin_session_id,
                        raw,
                        match cli_kind {
                            AgentCliKind::Claude => "claude_json",
                            AgentCliKind::Codex => "codex_json",
                        },
                    );
                    self.broadcast_session_event(&session.local_session_id, raw);
                    if decision_request.is_some() {
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Waiting,
                            None,
                            "awaiting-board-approval",
                            &mut last_status,
                            &mut last_error_message,
                        );
                    } else {
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Running,
                            None,
                            "event-processing",
                            &mut last_status,
                            &mut last_error_message,
                        );
                    }
                    if let Some(summary) = summarize_process_event(cli_kind, json) {
                        push_excerpt(&mut stdout_excerpt, &summary);
                    }
                    let event_type = process_event_type(json);
                    self.record_run_event(
                        &run,
                        seq,
                        &event_type,
                        Some("stdout"),
                        Some("info"),
                        Some(raw),
                        Some(json.clone()),
                    )
                    .await?;

                    if let Some(decision_request) = decision_request {
                        let approval = self
                            .maybe_create_agent_decision_approval(
                                &run,
                                issue_id.as_deref(),
                                &decision_request,
                            )
                            .await?;
                        if surfaced_approval_ids.insert(approval.id.clone()) {
                            let approval_message = format!(
                                "Waiting for board decision: {}",
                                decision_request.question
                            );
                            push_excerpt(&mut stdout_excerpt, &approval_message);
                            self.record_run_event(
                                &run,
                                seq + 1,
                                "approval_requested",
                                Some("system"),
                                Some("info"),
                                Some(&approval_message),
                                Some(json!({
                                    "approval_id": approval.id,
                                    "approval_type": approval.approval_type,
                                    "provider": decision_request.provider,
                                    "provider_request_id": decision_request.provider_request_id.clone(),
                                    "question": decision_request.question.clone(),
                                    "options": decision_request.options.clone(),
                                    "issue_id": issue_id.clone(),
                                })),
                            )
                            .await?;
                            seq += 1;
                        }
                    }

                    if let Some(session_id) = extract_process_session_id(cli_kind, json) {
                        if let Err(error) = self.armin.update_session_provider_session(
                            &armin_session_id,
                            provider_name_for_cli_kind(cli_kind),
                            &session_id,
                        ) {
                            warn!(
                                error = %error,
                                provider = provider_name_for_cli_kind(cli_kind),
                                "Failed to update provider session id"
                            );
                        }
                        session_id_after = Some(session_id.clone());
                        external_run_id = Some(session_id);
                    } else if external_run_id.is_none() {
                        external_run_id = json
                            .get("id")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned);
                    }

                    if usage_json.is_none() {
                        usage_json = extract_process_usage(cli_kind, json);
                    }
                    if result_json.is_none() && is_process_result_payload(cli_kind, json) {
                        result_json = Some(json.clone());
                    }
                    if let Some(error_message) = extract_process_error(cli_kind, json) {
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Error,
                            Some(error_message.clone()),
                            "process-json-error",
                            &mut last_status,
                            &mut last_error_message,
                        );
                        completion.status = STATUS_FAILED.to_string();
                        completion.error = Some(error_message);
                        completion.error_code = Some("result_error".to_string());
                        terminal_status_written = true;
                    }
                }
                AgentCliEvent::Stderr { line } => {
                    if let Some(summary) = summarize_agent_run_text(line) {
                        push_excerpt(&mut stderr_excerpt, &summary);
                    }
                    self.record_run_event(
                        &run,
                        seq,
                        "stderr",
                        Some("stderr"),
                        Some("warn"),
                        Some(line),
                        None,
                    )
                    .await?;
                }
                AgentCliEvent::Finished { success, exit_code } => {
                    if *success {
                        if !terminal_status_written {
                            self.write_runtime_status_if_changed(
                                &armin_session_id,
                                CodingSessionStatus::Idle,
                                None,
                                "process-finished-success",
                                &mut last_status,
                                &mut last_error_message,
                            );
                        }
                        if completion.error_code.is_none() {
                            completion.status = STATUS_SUCCEEDED.to_string();
                            completion.error = None;
                            completion.error_code = None;
                        }
                    } else {
                        let cli_label = agent_cli_label(cli_kind);
                        let error_message = match exit_code {
                            Some(code) => format!("{cli_label} process exited with status {code}"),
                            None => format!("{cli_label} process exited with non-zero status"),
                        };
                        if !terminal_status_written {
                            self.write_runtime_status_if_changed(
                                &armin_session_id,
                                CodingSessionStatus::Error,
                                Some(error_message.clone()),
                                "process-finished-error",
                                &mut last_status,
                                &mut last_error_message,
                            );
                        }
                        completion.status = STATUS_FAILED.to_string();
                        completion.error = Some(error_message);
                        completion.error_code = Some("process_exit".to_string());
                    }
                    completion.exit_code = *exit_code;
                    terminal_status_written = true;
                    self.record_run_event(
                        &run,
                        seq,
                        "finished",
                        Some("system"),
                        Some(if *success { "info" } else { "error" }),
                        Some(if *success {
                            "Coding agent process finished successfully"
                        } else {
                            "Coding agent process finished with an error"
                        }),
                        Some(json!({ "success": success, "exit_code": exit_code })),
                    )
                    .await?;
                }
                AgentCliEvent::Stopped => {
                    let (status, error, error_code, event_type, event_message, payload) =
                        if timed_out {
                            (
                                STATUS_TIMED_OUT.to_string(),
                                Some("Run timed out".to_string()),
                                Some("timeout".to_string()),
                                "timed_out",
                                "Run timed out",
                                json!({ "timed_out": true }),
                            )
                        } else {
                            (
                                STATUS_CANCELLED.to_string(),
                                Some("Run was cancelled".to_string()),
                                Some("cancelled".to_string()),
                                "stopped",
                                "Run was cancelled",
                                json!({ "cancelled": true }),
                            )
                        };
                    self.write_runtime_status_if_changed(
                        &armin_session_id,
                        CodingSessionStatus::NotAvailable,
                        None,
                        if timed_out {
                            "process-timed-out"
                        } else {
                            "process-stopped"
                        },
                        &mut last_status,
                        &mut last_error_message,
                    );
                    completion.status = status;
                    completion.error = error;
                    completion.error_code = error_code;
                    terminal_status_written = true;
                    self.record_run_event(
                        &run,
                        seq,
                        event_type,
                        Some("system"),
                        Some(if timed_out { "warn" } else { "info" }),
                        Some(event_message),
                        Some(payload),
                    )
                    .await?;
                }
            }
            seq += 1;

            if event.is_terminal() {
                break;
            }
        }

        if !terminal_status_written {
            self.write_runtime_status_if_changed(
                &armin_session_id,
                CodingSessionStatus::NotAvailable,
                None,
                "stream-cleanup",
                &mut last_status,
                &mut last_error_message,
            );
        }

        completion.usage_json = usage_json;
        completion.result_json = result_json;
        completion.session_id_after = session_id_after;
        completion.stdout_excerpt = trim_excerpt(stdout_excerpt);
        completion.stderr_excerpt = trim_excerpt(stderr_excerpt);
        completion.external_run_id = external_run_id;

        {
            let mut processes = self.claude_processes.lock().unwrap();
            processes.remove(&session.local_session_id);
        }
        {
            let mut processes = self.run_processes.lock().unwrap();
            processes.remove(&run.id);
        }

        self.finalize_run(
            &run,
            issue_id.as_deref(),
            Some(session.task_session_ref.clone()),
            completion,
        )
        .await?;
        self.queue_notify.notify_waiters();
        Ok(())
    }

    async fn finalize_run(
        &self,
        run: &AgentRun,
        issue_id: Option<&str>,
        task_session_ref: Option<RunTaskSessionRef>,
        completion: RunCompletion,
    ) -> Result<(), BoardError> {
        let now = now_rfc3339();
        let log_path = self.paths.agent_run_log_file(&run.id);
        let (log_bytes, log_sha256) = compute_log_metadata(&log_path)?;
        let run_id = run.id.clone();
        let wakeup_request_id = run.wakeup_request_id.clone();
        let company_id = run.company_id.clone();
        let agent_id = run.agent_id.clone();
        let status = completion.status.clone();
        let error = completion.error.clone();
        let error_code = completion.error_code.clone();
        let exit_code = completion.exit_code.map(i64::from);
        let signal = completion.signal.clone();
        let usage_json = completion.usage_json.clone().map(|value| value.to_string());
        let result_json = completion
            .result_json
            .clone()
            .map(|value| value.to_string());
        let session_id_after = completion.session_id_after.clone();
        let stdout_excerpt = completion.stdout_excerpt.clone();
        let stderr_excerpt = completion.stderr_excerpt.clone();
        let external_run_id = completion.external_run_id.clone();
        let issue_id_owned = issue_id.map(ToOwned::to_owned);
        let task_session_ref =
            task_session_ref.or_else(|| task_session_ref_from_run(run, issue_id_owned.as_deref()));

        self.db
            .call_with_operation("agent_run.finalize", move |conn| {
                let tx = conn.unchecked_transaction()?;
                tx.execute(
                    "UPDATE agent_runs
                     SET status = ?1,
                         finished_at = ?2,
                         error = ?3,
                         error_code = ?4,
                         exit_code = ?5,
                         signal = ?6,
                         usage_json = ?7,
                         result_json = ?8,
                         session_id_after = ?9,
                         log_bytes = ?10,
                         log_sha256 = ?11,
                         stdout_excerpt = ?12,
                         stderr_excerpt = ?13,
                         external_run_id = ?14,
                         updated_at = ?2
                     WHERE id = ?15",
                    params![
                        status,
                        now,
                        error,
                        error_code,
                        exit_code,
                        signal,
                        usage_json,
                        result_json,
                        session_id_after,
                        log_bytes,
                        log_sha256,
                        stdout_excerpt,
                        stderr_excerpt,
                        external_run_id,
                        run_id,
                    ],
                )?;
                if let Some(wakeup_request_id) = wakeup_request_id {
                    let wakeup_status = match status.as_str() {
                        STATUS_SUCCEEDED => "finished",
                        STATUS_CANCELLED => "cancelled",
                        _ => "failed",
                    };
                    tx.execute(
                        "UPDATE agent_wakeup_requests
                         SET status = ?1, finished_at = ?2, updated_at = ?2
                         WHERE id = ?3",
                        params![wakeup_status, now, wakeup_request_id],
                    )?;
                }
                tx.execute(
                    "UPDATE agents
                     SET last_heartbeat_at = ?1, updated_at = ?1
                     WHERE id = ?2",
                    params![now, agent_id],
                )?;
                if let Some(ref issue_id) = issue_id_owned {
                    tx.execute(
                        "UPDATE issues
                         SET execution_locked_at = CASE
                                WHEN execution_run_id = ?1 THEN NULL
                                ELSE execution_locked_at
                             END,
                             updated_at = ?2
                         WHERE id = ?3",
                        params![run_id, now, issue_id],
                    )?;
                }

                let updated_task_session = if let Some(task_session_ref) = task_session_ref.as_ref()
                {
                    tx.execute(
                        "UPDATE agent_task_sessions
                         SET last_run_id = ?1, last_error = ?2, updated_at = ?3
                         WHERE company_id = ?4 AND agent_id = ?5 AND adapter_type = ?6 AND task_key = ?7",
                        params![
                            run_id,
                            error,
                            now,
                            company_id,
                            agent_id,
                            task_session_ref.adapter_type,
                            task_session_ref.task_key,
                        ],
                    )?
                } else {
                    0
                };
                if updated_task_session == 0 {
                    tx.execute(
                        "UPDATE agent_task_sessions
                         SET last_run_id = ?1, last_error = ?2, updated_at = ?3
                         WHERE company_id = ?4 AND agent_id = ?5 AND adapter_type = 'agent_home' AND task_key = 'home'",
                        params![run_id, error, now, company_id, agent_id],
                    )?;
                }

                tx.commit()?;
                Ok(())
            })
            .await?;

        if let Err(error) = self.record_agent_directory_drift_warning(run).await {
            warn!(error = %error, run_id = %run.id, "Failed to record agent home drift warning");
        }

        Ok(())
    }

    async fn record_agent_directory_drift_warning(&self, run: &AgentRun) -> Result<(), BoardError> {
        let orphan_slugs = self.orphan_agent_home_slugs(&run.company_id).await?;
        if orphan_slugs.is_empty() {
            return Ok(());
        }

        let message = format!(
            "Found agent home directories without matching board records: {}. Hiring must go through the board helper, not manual filesystem creation.",
            orphan_slugs.join(", ")
        );
        self.record_run_event(
            run,
            next_run_seq(&self.db, &run.id).await?,
            "agent_home_drift_warning",
            Some("system"),
            Some("warn"),
            Some(&message),
            Some(json!({ "orphan_agent_home_slugs": orphan_slugs })),
        )
        .await
    }

    async fn orphan_agent_home_slugs(&self, company_id: &str) -> Result<Vec<String>, BoardError> {
        let known_slugs = service::list_agents(&self.db, company_id)
            .await?
            .into_iter()
            .map(|agent| agent.slug)
            .collect::<HashSet<_>>();
        let agent_root = self.paths.company_agents_dir(company_id);
        if !agent_root.exists() {
            return Ok(Vec::new());
        }

        let mut orphan_slugs = Vec::new();
        for entry in fs::read_dir(agent_root)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let slug = entry.file_name().to_string_lossy().to_string();
            if !known_slugs.contains(&slug) {
                orphan_slugs.push(slug);
            }
        }
        orphan_slugs.sort();
        Ok(orphan_slugs)
    }

    async fn record_run_event(
        &self,
        run: &AgentRun,
        seq: i64,
        event_type: &str,
        stream: Option<&str>,
        level: Option<&str>,
        message: Option<&str>,
        payload: Option<Value>,
    ) -> Result<(), BoardError> {
        let now = now_rfc3339();
        let run_id = run.id.clone();
        let company_id = run.company_id.clone();
        let agent_id = run.agent_id.clone();
        let event_type = event_type.to_string();
        let stream = stream.map(ToOwned::to_owned);
        let level = level.map(ToOwned::to_owned);
        let message = message.map(ToOwned::to_owned);
        let payload_text = payload.clone().map(|value| value.to_string());
        let event_type_for_log = event_type.clone();
        let stream_for_log = stream.clone();
        let level_for_log = level.clone();
        let message_for_log = message.clone();

        self.db
            .call_with_operation("agent_run.events.insert", move |conn| {
                conn.execute(
                    "INSERT INTO agent_run_events (
                        company_id, run_id, agent_id, seq, event_type, stream, level,
                        color, message, payload, created_at
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, ?8, ?9, ?10)",
                    params![
                        company_id,
                        run_id,
                        agent_id,
                        seq,
                        event_type,
                        stream,
                        level,
                        message,
                        payload_text,
                        now,
                    ],
                )?;
                Ok(())
            })
            .await?;

        self.append_log_line(
            &run.id,
            seq,
            event_type_for_log.as_str(),
            stream_for_log.as_deref(),
            level_for_log.as_deref(),
            message_for_log.as_deref(),
            payload,
        )
        .map_err(BoardError::from)
    }

    fn append_log_line(
        &self,
        run_id: &str,
        seq: i64,
        event_type: &str,
        stream: Option<&str>,
        level: Option<&str>,
        message: Option<&str>,
        payload: Option<Value>,
    ) -> Result<(), std::io::Error> {
        let log_path = self.paths.agent_run_log_file(run_id);
        if let Some(parent) = log_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_path)?;
        let line = json!({
            "timestamp": now_rfc3339(),
            "seq": seq,
            "event_type": event_type,
            "stream": stream,
            "level": level,
            "message": message,
            "payload": payload,
        });
        file.write_all(line.to_string().as_bytes())?;
        file.write_all(b"\n")?;
        Ok(())
    }

    async fn reap_orphaned_running_runs(&self) -> Result<(), BoardError> {
        let running_run_ids = self
            .db
            .call_with_operation("agent_run.reaper.running", move |conn| {
                let mut stmt =
                    conn.prepare("SELECT id FROM agent_runs WHERE status = 'running'")?;
                let rows = stmt
                    .query_map([], |row| row.get::<_, String>(0))?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(rows)
            })
            .await?;

        let active_runs = {
            let processes = self.run_processes.lock().unwrap();
            processes.keys().cloned().collect::<Vec<_>>()
        };

        for run_id in running_run_ids {
            if !active_runs.iter().any(|active| active == &run_id) {
                self.mark_run_as_process_lost(&run_id).await?;
            }
        }

        Ok(())
    }

    async fn recover_failed_run_startup(
        &self,
        run_id: &str,
        error: &BoardError,
    ) -> Result<(), BoardError> {
        let Some(run) = service::get_agent_run(&self.db, run_id).await? else {
            return Ok(());
        };

        if run.status != STATUS_RUNNING && run.status != STATUS_QUEUED {
            return Ok(());
        }

        let error_message = error.to_string();
        self.record_run_event(
            &run,
            next_run_seq(&self.db, &run.id).await?,
            "run_failed",
            Some("system"),
            Some("error"),
            Some(&error_message),
            Some(json!({ "error_code": "startup_failed" })),
        )
        .await?;

        let snapshot = run.context_snapshot.clone().unwrap_or(Value::Null);
        let issue_id = snapshot
            .get("payload")
            .and_then(|payload| payload.get("issue_id"))
            .and_then(Value::as_str);
        self.finalize_run(
            &run,
            issue_id,
            None,
            RunCompletion {
                status: STATUS_FAILED.to_string(),
                error: Some(error_message.clone()),
                error_code: Some("startup_failed".to_string()),
                exit_code: None,
                signal: None,
                usage_json: run.usage_json.clone(),
                result_json: run.result_json.clone(),
                session_id_after: run
                    .session_id_after
                    .clone()
                    .or(run.session_id_before.clone()),
                stdout_excerpt: run.stdout_excerpt.clone(),
                stderr_excerpt: Some(error_message),
                external_run_id: run.external_run_id.clone(),
            },
        )
        .await
    }

    async fn mark_run_as_process_lost(&self, run_id: &str) -> Result<(), BoardError> {
        let run = service::get_agent_run(&self.db, run_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Run not found".to_string()))?;
        if run.status != STATUS_RUNNING {
            return Ok(());
        }

        self.record_run_event(
            &run,
            next_run_seq(&self.db, &run.id).await?,
            "process_lost",
            Some("system"),
            Some("error"),
            Some("Run process was lost before completion"),
            Some(json!({ "error_code": ERROR_CODE_PROCESS_LOST })),
        )
        .await?;

        let snapshot = run.context_snapshot.clone().unwrap_or(Value::Null);
        let issue_id = snapshot
            .get("payload")
            .and_then(|payload| payload.get("issue_id"))
            .and_then(Value::as_str);
        self.finalize_run(
            &run,
            issue_id,
            None,
            RunCompletion {
                status: STATUS_FAILED.to_string(),
                error: Some("Run process was lost before completion".to_string()),
                error_code: Some(ERROR_CODE_PROCESS_LOST.to_string()),
                exit_code: None,
                signal: None,
                usage_json: None,
                result_json: None,
                session_id_after: run
                    .session_id_after
                    .clone()
                    .or(run.session_id_before.clone()),
                stdout_excerpt: run.stdout_excerpt.clone(),
                stderr_excerpt: run.stderr_excerpt.clone(),
                external_run_id: run.external_run_id.clone(),
            },
        )
        .await
    }

    async fn resolve_session_for_run(
        &self,
        agent: &Agent,
        issue_id: Option<String>,
    ) -> Result<RunSessionContext, BoardError> {
        if let Some(issue_id) = issue_id {
            let issue = service::get_issue(&self.db, &issue_id)
                .await?
                .ok_or_else(|| BoardError::NotFound("Issue not found for run".to_string()))?;
            match issue_run_session_strategy(&issue) {
                IssueRunSessionStrategy::AttachedWorkspace => {
                    let workspace = ensure_issue_workspace(
                        &self.db,
                        self.armin.as_ref(),
                        &self.db_encryption_key,
                        &self.session_secret_cache,
                        &issue_id,
                    )
                    .await?;
                    return Ok(RunSessionContext {
                        local_session_id: workspace.session_id,
                        local_session_title: workspace.title,
                        task_session_ref: RunTaskSessionRef::issue_workspace(&issue.id),
                    });
                }
                IssueRunSessionStrategy::ProjectRoot => {
                    return self.ensure_issue_project_root_session(agent, &issue).await;
                }
                IssueRunSessionStrategy::AgentHome => {}
            }
        }

        self.ensure_agent_home_session(agent).await
    }

    async fn ensure_issue_project_root_session(
        &self,
        agent: &Agent,
        issue: &Issue,
    ) -> Result<RunSessionContext, BoardError> {
        let project_id = issue.project_id.clone().ok_or_else(|| {
            BoardError::InvalidInput("Issue must belong to a project".to_string())
        })?;
        let project = service::get_project(&self.db, &project_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Project not found".to_string()))?;
        let primary_workspace = project.primary_workspace.ok_or_else(|| {
            BoardError::NotFound("Project repo root is not configured".to_string())
        })?;
        let repo_path = primary_workspace.cwd.clone().ok_or_else(|| {
            BoardError::InvalidInput("Project repo root path is missing".to_string())
        })?;
        let repository = ensure_workspace_repository(
            self.armin.as_ref(),
            &repo_path,
            primary_workspace.repo_ref.clone(),
        )?;
        let title = issue
            .identifier
            .as_ref()
            .map(|identifier| format!("{identifier}: {}", issue.title))
            .unwrap_or_else(|| issue.title.clone());
        let task_session_ref = RunTaskSessionRef::issue_project_root(&issue.id);
        let existing_task_session = task_session_ref.clone();
        let company_id = agent.company_id.clone();
        let agent_id = agent.id.clone();

        let existing_session_id = self
            .db
            .call_with_operation("agent_run.issue_project_root.lookup", move |conn| {
                conn.query_row(
                    "SELECT json_extract(session_params_json, '$.session_id')
                     FROM agent_task_sessions
                     WHERE company_id = ?1
                       AND agent_id = ?2
                       AND adapter_type = ?3
                       AND task_key = ?4
                     LIMIT 1",
                    params![
                        company_id,
                        agent_id,
                        existing_task_session.adapter_type,
                        existing_task_session.task_key
                    ],
                    |row| row.get::<_, String>(0),
                )
                .optional()
                .map_err(Into::into)
            })
            .await?;

        if let Some(existing_session_id) = existing_session_id {
            return Ok(RunSessionContext {
                local_session_id: existing_session_id,
                local_session_title: title,
                task_session_ref,
            });
        }

        let session = self
            .armin
            .create_session_with_metadata(NewSession {
                id: SessionId::new(),
                repository_id: repository.id.clone(),
                title: title.clone(),
                agent_id: Some(agent.id.clone()),
                agent_name: Some(agent.name.clone()),
                issue_id: Some(issue.id.clone()),
                issue_title: Some(issue.title.clone()),
                issue_url: None,
                provider: Some(provider_name_for_cli_kind(agent_cli_kind(agent)).to_string()),
                provider_session_id: None,
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            })
            .map_err(|error| BoardError::Runtime(error.to_string()))?;

        let session_id = session.id.as_str().to_string();
        let now = now_rfc3339();
        let project_id = project.id.clone();
        let issue_id = issue.id.clone();
        let issue_identifier = issue
            .identifier
            .clone()
            .unwrap_or_else(|| session_id.clone());
        let workspace_repo_path = repo_path.clone();
        let workspace_branch = primary_workspace
            .repo_ref
            .clone()
            .or(repository.default_branch.clone());
        let session_id_for_db = session_id.clone();
        let company_id = agent.company_id.clone();
        let agent_id = agent.id.clone();
        let title_for_db = title.clone();
        let task_session_ref_for_db = task_session_ref.clone();
        self.db
            .call_with_operation("agent_run.issue_project_root.persist", move |conn| {
                let tx = conn.unchecked_transaction()?;
                tx.execute(
                    "UPDATE agent_coding_sessions
                     SET company_id = ?1,
                         project_id = ?2,
                         issue_id = ?3,
                         agent_id = ?4,
                         workspace_type = 'issue_project_root',
                         workspace_status = 'active',
                         workspace_repo_path = ?5,
                         workspace_branch = ?6,
                         workspace_metadata = ?7,
                         updated_at = ?8,
                         title = ?9
                     WHERE id = ?10",
                    params![
                        company_id,
                        project_id,
                        issue_id,
                        agent_id,
                        workspace_repo_path,
                        workspace_branch,
                        json!({
                            "scope": "issue_project_root",
                            "issue_id": issue_id,
                            "issue_identifier": issue_identifier,
                            "project_id": project_id,
                            "agent_id": agent_id,
                        })
                        .to_string(),
                        now,
                        title_for_db,
                        session_id_for_db,
                    ],
                )?;
                tx.execute(
                    "INSERT INTO agent_task_sessions (
                        id, company_id, agent_id, adapter_type, task_key, session_params_json,
                        session_display_id, last_run_id, last_error, created_at, updated_at
                     ) VALUES (
                        ?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, NULL, ?8, ?8
                     )
                     ON CONFLICT(company_id, agent_id, adapter_type, task_key) DO UPDATE SET
                        session_params_json = excluded.session_params_json,
                        session_display_id = excluded.session_display_id,
                        updated_at = excluded.updated_at",
                    params![
                        Uuid::new_v4().to_string(),
                        company_id,
                        agent_id,
                        task_session_ref_for_db.adapter_type,
                        task_session_ref_for_db.task_key,
                        json!({ "session_id": session_id_for_db, "issue_id": issue_id })
                            .to_string(),
                        issue_identifier,
                        now,
                    ],
                )?;
                tx.commit()?;
                Ok(())
            })
            .await?;

        Ok(RunSessionContext {
            local_session_id: session_id,
            local_session_title: title,
            task_session_ref,
        })
    }

    async fn ensure_agent_home_session(
        &self,
        agent: &Agent,
    ) -> Result<RunSessionContext, BoardError> {
        let home_path = agent
            .home_path
            .clone()
            .ok_or_else(|| BoardError::InvalidInput("Agent home path is missing".to_string()))?;
        let company_id = agent.company_id.clone();
        let agent_id = agent.id.clone();
        let title = format!("{} Agent Home", agent.name);
        let home_path_for_lookup = home_path.clone();

        let existing = self
            .db
            .call_with_operation("agent_run.home_session.lookup", move |conn| {
                let repository = queries::get_repository_by_path(conn, &home_path_for_lookup)?
                    .map(|repo| (repo.id, repo.default_branch));
                let session_id: Option<String> = conn
                    .query_row(
                        "SELECT json_extract(session_params_json, '$.session_id')
                         FROM agent_task_sessions
                         WHERE company_id = ?1
                           AND agent_id = ?2
                           AND adapter_type = 'agent_home'
                           AND task_key = 'home'
                         LIMIT 1",
                        params![company_id, agent_id],
                        |row| row.get(0),
                    )
                    .optional()?;
                Ok((repository, session_id))
            })
            .await?;

        if let Some(existing_session_id) = existing.1 {
            return Ok(RunSessionContext {
                local_session_id: existing_session_id,
                local_session_title: title,
                task_session_ref: RunTaskSessionRef::agent_home(),
            });
        }

        let repository_id = match existing.0 {
            Some((repository_id, _)) => repository_id,
            None => {
                let repo_name = Path::new(&home_path)
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or("agent-home")
                    .to_string();
                let repository_id = Uuid::new_v4().to_string();
                let repo = NewRepository {
                    id: repository_id.clone(),
                    path: home_path.clone(),
                    name: repo_name,
                    is_git_repository: false,
                    sessions_path: None,
                    default_branch: None,
                    default_remote: None,
                };
                let repo_for_insert = repo.clone();
                self.db
                    .call_with_operation("agent_run.home_session.repository", move |conn| {
                        let _ = queries::insert_repository(conn, &repo_for_insert)?;
                        Ok(())
                    })
                    .await?;
                repository_id
            }
        };

        let session = self
            .armin
            .create_session_with_metadata(NewSession {
                id: agent_session_sqlite_persist_core::SessionId::new(),
                repository_id: RepositoryId::from_string(&repository_id),
                title: title.clone(),
                agent_id: Some(agent.id.clone()),
                agent_name: Some(agent.name.clone()),
                issue_id: None,
                issue_title: None,
                issue_url: None,
                provider: Some(provider_name_for_cli_kind(agent_cli_kind(agent)).to_string()),
                provider_session_id: None,
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            })
            .map_err(|error| BoardError::Runtime(error.to_string()))?;

        let session_id = session.id.as_str().to_string();
        let now = now_rfc3339();
        let company_id = agent.company_id.clone();
        let agent_id = agent.id.clone();
        let home_path_for_db = home_path.clone();
        let session_id_for_db = session_id.clone();
        let title_for_db = title.clone();
        self.db
            .call_with_operation("agent_run.home_session.persist", move |conn| {
                let tx = conn.unchecked_transaction()?;
                tx.execute(
                    "UPDATE agent_coding_sessions
                     SET company_id = ?1,
                         agent_id = ?2,
                         workspace_type = 'agent_home',
                         workspace_status = 'active',
                         workspace_repo_path = ?3,
                         workspace_metadata = ?4,
                         updated_at = ?5,
                         title = ?6
                     WHERE id = ?7",
                    params![
                        company_id,
                        agent_id,
                        home_path_for_db,
                        json!({
                            "scope": "agent_home",
                            "agent_id": agent_id,
                        })
                        .to_string(),
                        now,
                        title_for_db,
                        session_id_for_db,
                    ],
                )?;
                tx.execute(
                    "INSERT INTO agent_task_sessions (
                        id, company_id, agent_id, adapter_type, task_key, session_params_json,
                        session_display_id, last_run_id, last_error, created_at, updated_at
                     ) VALUES (
                        ?1, ?2, ?3, 'agent_home', 'home', ?4, ?5, NULL, NULL, ?6, ?6
                     )
                     ON CONFLICT(company_id, agent_id, adapter_type, task_key) DO UPDATE SET
                        session_params_json = excluded.session_params_json,
                        session_display_id = excluded.session_display_id,
                        updated_at = excluded.updated_at",
                    params![
                        Uuid::new_v4().to_string(),
                        company_id,
                        agent_id,
                        json!({ "session_id": session_id_for_db }).to_string(),
                        session_id_for_db,
                        now,
                    ],
                )?;
                tx.commit()?;
                Ok(())
            })
            .await?;

        Ok(RunSessionContext {
            local_session_id: session_id,
            local_session_title: title,
            task_session_ref: RunTaskSessionRef::agent_home(),
        })
    }

    async fn approval_prompt_context(&self, run: &AgentRun) -> Result<Option<String>, BoardError> {
        let Some(snapshot) = run.context_snapshot.as_ref() else {
            return Ok(None);
        };
        let approval_id = snapshot
            .get("payload")
            .and_then(|payload| payload.get("approval_id"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let Some(approval_id) = approval_id else {
            return Ok(None);
        };

        let approval = service::get_approval(&self.db, approval_id)
            .await?
            .ok_or_else(|| BoardError::NotFound("Approval not found for run".to_string()))?;
        Ok(format_approval_prompt_context(&approval))
    }

    async fn maybe_create_agent_decision_approval(
        &self,
        run: &AgentRun,
        issue_id: Option<&str>,
        decision_request: &AgentDecisionRequest,
    ) -> Result<Approval, BoardError> {
        let request_key = decision_request_request_key(run, decision_request);
        service::create_agent_decision_approval(
            &self.db,
            CreateAgentDecisionApprovalInput {
                company_id: run.company_id.clone(),
                requested_by_agent_id: run.agent_id.clone(),
                requested_by_run_id: run.id.clone(),
                requested_by_user_id: None,
                source_issue_id: issue_id.map(ToOwned::to_owned),
                source_issue_ids: None,
                provider: Some(decision_request.provider.to_string()),
                provider_request_id: decision_request.provider_request_id.clone(),
                request_key,
                question: decision_request.question.clone(),
                options: Some(decision_request.options.clone()),
                questions: decision_request.questions.clone(),
                raw_request: Some(decision_request.raw_request.clone()),
            },
        )
        .await
    }

    async fn build_prompt(
        &self,
        run: &AgentRun,
        agent: &Agent,
        issue_id: Option<&str>,
        include_bootstrap_prompt: bool,
    ) -> Result<String, BoardError> {
        let governance_instructions =
            governance_instructions(self.paths.as_ref(), agent, run, issue_id);
        let issue_context = if let Some(issue_id) = issue_id {
            let issue = service::get_issue(&self.db, issue_id)
                .await?
                .ok_or_else(|| BoardError::NotFound("Issue not found for run".to_string()))?;
            let comments = service::list_issue_comments(&self.db, issue_id).await?;
            let attachments =
                service::list_issue_attachments(&self.db, self.paths.as_ref(), issue_id).await?;
            let attachment_summary = format_issue_attachment_summary(&attachments);
            let comment_summary = format_issue_comment_summary(&comments);
            format!(
                "Issue: {}\nTitle: {}\nStatus: {}\nPriority: {}\nDescription: {}\n{}\n{}\n",
                issue.identifier.clone().unwrap_or(issue.id.clone()),
                issue.title,
                issue.status,
                issue.priority,
                issue
                    .description
                    .unwrap_or_else(|| "No description.".to_string()),
                comment_summary,
                attachment_summary,
            )
        } else {
            let issue_list_command = format!(
                "{} --base-dir {} board issue-list --company-id {} --assignee-agent-id {}",
                shell_quote(&board_helper_binary_path()),
                shell_quote(&self.paths.base_dir().to_string_lossy()),
                shell_quote(&agent.company_id),
                shell_quote(&agent.id),
            );
            format!(
                "This run is not linked to a specific issue.\n\
                 Start by listing your assigned issues with:\n\
                 {issue_list_command}\n"
            )
        };
        let approval_context = self
            .approval_prompt_context(run)
            .await?
            .map(|context| format!("{context}\n"))
            .unwrap_or_default();
        let rendered_prompt_template = rendered_prompt_template(agent, run, issue_id)
            .unwrap_or_else(|| default_agent_run_prompt(agent, issue_id));
        let bootstrap_prompt = if include_bootstrap_prompt {
            agent
                .runtime_config
                .get("bootstrapPrompt")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| format!("{value}\n\n"))
                .unwrap_or_default()
        } else {
            String::new()
        };

        Ok(format!(
            "{bootstrap_prompt}You are {agent_name}, a {agent_role} agent inside Unbound.\n\
             Invocation source: {source}\n\
             Trigger detail: {trigger}\n\
             Wake reason: {wake_reason}\n\
             Agent home: {home_path}\n\
             Instructions: {instructions_path}\n\n\
             {rendered_prompt_template}\n\n\
             {governance_instructions}\n\
             {issue_context}\n\
             {approval_context}\
             Run operating rules:\n\
             - Treat each run as a focused execution window: inspect the assigned work, do the next useful step, and exit.\n\
             - If this run is linked to an issue, treat that issue as the primary work item for this run.\n\
             - If this run is not linked to an issue, list your assigned issues, work on in_progress first, then todo, and skip blocked work unless there is fresh context that lets you unblock it.\n\
             - Before doing issue work, make sure the issue worktree is ready with the board issue-checkout helper instead of creating ad hoc folders yourself.\n\
             - If you actively start a todo issue, move it to in_progress. If you finish it, mark it done with a concise summary. If you are blocked, mark it blocked and explain exactly what is needed.\n\
             - If you made progress but did not finish, leave a concise issue comment before exiting so the next run can continue cleanly.\n\
             - Work directly in the resolved local worktree. Only create or switch to a fresh git worktree when the issue or user explicitly asks for it.\n\
             - If this wake reason is approval_approved, continue the same provider session and treat the board decision as authoritative new input.\n\
             Finish with a concise summary that covers:\n\
             1. what you changed or concluded\n\
             2. any blockers or follow-up needed\n\
             3. whether the linked issue status should change\n",
            bootstrap_prompt = bootstrap_prompt,
            agent_name = agent.name,
            agent_role = agent.role,
            source = run.invocation_source,
            trigger = run.trigger_detail.clone().unwrap_or_else(|| "unknown".to_string()),
            wake_reason = run.wake_reason.clone().unwrap_or_else(|| "manual".to_string()),
            home_path = agent.home_path.clone().unwrap_or_else(|| "missing".to_string()),
            instructions_path = agent
                .instructions_path
                .clone()
                .unwrap_or_else(|| "missing".to_string()),
            rendered_prompt_template = rendered_prompt_template,
            governance_instructions = governance_instructions,
            issue_context = issue_context,
            approval_context = approval_context,
        ))
    }

    async fn agent_company_id(&self, agent_id: &str) -> Result<String, BoardError> {
        let agent_id = agent_id.to_string();
        self.db
            .call_with_operation("agent_run.agent_company", move |conn| {
                conn.query_row(
                    "SELECT company_id FROM agents WHERE id = ?1",
                    params![agent_id],
                    |row| row.get(0),
                )
                .optional()
                .map_err(Into::into)
            })
            .await?
            .ok_or_else(|| BoardError::NotFound("Agent not found".to_string()))
    }

    fn append_claude_message(&self, session_id: &SessionId, raw: &str, event_kind: &'static str) {
        let _guard = tracing::info_span!(
            "armin.append",
            session_id = %session_id,
            message_kind = event_kind
        )
        .entered();

        if let Err(error) = self.armin.append(
            session_id,
            NewMessage {
                content: raw.to_string(),
            },
        ) {
            warn!(error = %error, message_kind = event_kind, "Failed to append agent event");
        }
    }

    fn broadcast_session_event(&self, session_id: &str, raw_json: &str) {
        let mut event = Event::new(
            EventType::AgentEvent,
            session_id,
            serde_json::json!({ "raw_json": raw_json }),
            Utc::now().timestamp_millis(),
        );
        if let Some(trace_context) = current_trace_context() {
            event = event.with_context(trace_context);
        }
        let subscriptions = self.subscriptions.clone();
        let session_id = session_id.to_string();
        spawn_in_current_span(async move {
            subscriptions.broadcast_or_create(&session_id, event).await;
        });
    }

    fn write_runtime_status_if_changed(
        &self,
        session_id: &SessionId,
        status: CodingSessionStatus,
        error_message: Option<String>,
        reason: &str,
        last_status: &mut Option<CodingSessionStatus>,
        last_error_message: &mut Option<String>,
    ) {
        if *last_status == Some(status) && *last_error_message == error_message {
            return;
        }

        let device_id = {
            let guard = self.device_id.lock().unwrap();
            guard.clone()
        };
        let Some(device_id) = device_id else {
            warn!(session_id = %session_id, "Skipping runtime status update without device id");
            return;
        };

        match self.armin.update_runtime_status(
            session_id,
            &device_id,
            status,
            error_message.clone(),
        ) {
            Ok(()) => {
                *last_status = Some(status);
                *last_error_message = error_message;
            }
            Err(error) => {
                warn!(
                    session_id = %session_id,
                    reason,
                    error = %error,
                    "Failed to update runtime status"
                );
            }
        }
    }
}

fn now_rfc3339() -> String {
    Utc::now().to_rfc3339()
}

fn map_resolve_error(error: ResolveError) -> BoardError {
    match error {
        ResolveError::SessionNotFound(message)
        | ResolveError::RepositoryNotFound(message)
        | ResolveError::LegacyWorktreeUnsupported(message) => BoardError::NotFound(message),
        ResolveError::Armin(error) => BoardError::Runtime(error.to_string()),
    }
}

fn issue_id_from_value(payload: &Value) -> Option<String> {
    payload
        .get("issue_id")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

fn format_issue_attachment_summary(attachments: &[daemon_board::IssueAttachment]) -> String {
    if attachments.is_empty() {
        return "Attachments: None.".to_string();
    }

    let mut summary = String::from("Attachments:");
    for attachment in attachments {
        let name = attachment
            .original_filename
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(attachment.object_key.as_str());
        summary.push_str(&format!(
            "\n- {name} | {content_type} | {byte_size} bytes | Local path: {local_path}",
            content_type = attachment.content_type,
            byte_size = attachment.byte_size,
            local_path = attachment.local_path,
        ));
    }

    summary
}

fn format_issue_comment_summary(comments: &[IssueComment]) -> String {
    if comments.is_empty() {
        return "Recent comments: None.".to_string();
    }

    let mut summary = String::from("Recent comments:");
    let start = comments.len().saturating_sub(5);
    for comment in &comments[start..] {
        let author = comment
            .author_agent_id
            .as_deref()
            .or(comment.author_user_id.as_deref())
            .unwrap_or("unknown");
        let target = comment
            .target_agent_id
            .as_deref()
            .map(|value| format!(" -> {value}"))
            .unwrap_or_default();
        summary.push_str(&format!(
            "\n- {author}{target}: {}",
            compact_comment_body(&comment.body),
        ));
    }

    summary
}

fn compact_comment_body(body: &str) -> String {
    let trimmed = body.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut compact = trimmed.trim().to_string();
    if compact.len() > 280 {
        compact.truncate(277);
        compact.push_str("...");
    }
    if compact.is_empty() {
        "Empty comment.".to_string()
    } else {
        compact
    }
}

fn rendered_prompt_template(
    agent: &Agent,
    run: &AgentRun,
    issue_id: Option<&str>,
) -> Option<String> {
    let template = agent
        .metadata
        .as_ref()
        .and_then(|value| value.get("promptTemplate"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?;

    let issue = issue_id.map(|id| {
        json!({
            "id": id,
        })
    });
    let data = json!({
        "agentId": agent.id,
        "companyId": agent.company_id,
        "runId": run.id,
        "issueId": issue_id,
        "company": {
            "id": agent.company_id,
        },
        "agent": {
            "id": agent.id,
            "name": agent.name,
            "role": agent.role,
            "slug": agent.slug,
            "title": agent.title,
        },
        "run": {
            "id": run.id,
            "source": run.invocation_source,
            "invocationSource": run.invocation_source,
            "triggerDetail": run.trigger_detail,
            "wakeReason": run.wake_reason,
        },
        "issue": issue,
    });

    Some(render_template(template, &data))
}

fn default_agent_run_prompt(agent: &Agent, issue_id: Option<&str>) -> String {
    if let Some(issue_id) = issue_id {
        return format!(
            "This run is focused on issue {issue_id}. Read the issue context, do the next useful piece of work in the linked worktree, and update the issue before you exit."
        );
    }

    format!(
        "Inspect work assigned to {agent_name} ({agent_role}), pick the highest-value actionable issue, do useful work in its worktree, and update that issue before you exit.",
        agent_name = agent.name,
        agent_role = agent.role,
    )
}

fn render_template(template: &str, data: &Value) -> String {
    let mut rendered = String::with_capacity(template.len());
    let mut cursor = 0;

    while let Some(start_offset) = template[cursor..].find("{{") {
        let start = cursor + start_offset;
        rendered.push_str(&template[cursor..start]);

        let tag_start = start + 2;
        let Some(end_offset) = template[tag_start..].find("}}") else {
            rendered.push_str(&template[start..]);
            return rendered;
        };
        let end = tag_start + end_offset;
        let path = template[tag_start..end].trim();
        rendered.push_str(&resolve_template_value(data, path));
        cursor = end + 2;
    }

    rendered.push_str(&template[cursor..]);
    rendered
}

fn resolve_template_value(data: &Value, dotted_path: &str) -> String {
    if dotted_path.is_empty() {
        return String::new();
    }

    let mut cursor = data;
    for part in dotted_path.split('.') {
        let Value::Object(map) = cursor else {
            return String::new();
        };
        let Some(next) = map.get(part) else {
            return String::new();
        };
        cursor = next;
    }

    match cursor {
        Value::Null => String::new(),
        Value::String(value) => value.clone(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        other => serde_json::to_string(other).unwrap_or_default(),
    }
}

fn build_idempotency_key(
    agent_id: &str,
    invocation_source: &str,
    trigger_detail: Option<&str>,
    wake_reason: Option<&str>,
    issue_id: Option<&str>,
    prompt: Option<&str>,
) -> Option<String> {
    if is_issue_comment_wake_reason(wake_reason) {
        return None;
    }

    if invocation_source == SOURCE_ON_DEMAND && prompt.is_some() {
        return None;
    }

    Some(format!(
        "{agent_id}:{invocation_source}:{trigger_detail}:{wake_reason}:{issue_id}",
        trigger_detail = trigger_detail.unwrap_or(""),
        wake_reason = wake_reason.unwrap_or(""),
        issue_id = issue_id.unwrap_or(""),
    ))
}

fn should_resume_claude_session(
    invocation_source: &str,
    trigger_detail: Option<&str>,
    wake_reason: Option<&str>,
) -> bool {
    if wake_reason == Some("issue_assigned") {
        return false;
    }

    if invocation_source == SOURCE_TIMER {
        return false;
    }

    !(invocation_source == SOURCE_ON_DEMAND && trigger_detail == Some(TRIGGER_MANUAL))
}

fn is_issue_comment_wake_reason(wake_reason: Option<&str>) -> bool {
    matches!(
        wake_reason,
        Some("issue_commented" | "issue_comment_mentioned" | "issue_reopened_via_comment")
    )
}

fn queued_run_waits_for_prior_issue_runs(
    issue_id: Option<&str>,
    wake_reason: Option<&str>,
) -> bool {
    issue_id.is_some() && is_issue_comment_wake_reason(wake_reason)
}

fn has_older_pending_issue_runs(
    conn: &rusqlite::Connection,
    issue_id: &str,
    created_at: &str,
    rowid: i64,
) -> rusqlite::Result<bool> {
    let pending_count: i64 = conn.query_row(
        "SELECT COUNT(*)
         FROM agent_runs
         WHERE issue_id = ?1
           AND status IN ('queued', 'running')
           AND (
                created_at < ?2
                OR (created_at = ?2 AND rowid < ?3)
           )",
        params![issue_id, created_at, rowid],
        |row| row.get(0),
    )?;
    Ok(pending_count > 0)
}

fn push_excerpt(buffer: &mut String, line: &str) {
    if !buffer.is_empty() {
        buffer.push('\n');
    }
    buffer.push_str(line.trim());
    if buffer.len() > 4000 {
        let keep_from = buffer.len().saturating_sub(4000);
        let trimmed = buffer.split_off(keep_from);
        *buffer = trimmed;
    }
}

fn trim_excerpt(buffer: String) -> Option<String> {
    let trimmed = buffer.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn extract_agent_decision_request(
    cli_kind: AgentCliKind,
    json: &Value,
) -> Option<AgentDecisionRequest> {
    match cli_kind {
        AgentCliKind::Claude => extract_claude_decision_request(json),
        AgentCliKind::Codex => extract_codex_decision_request(json),
    }
}

fn extract_claude_decision_request(json: &Value) -> Option<AgentDecisionRequest> {
    let blocks = json
        .get("message")
        .and_then(|message| message.get("content"))
        .and_then(Value::as_array)?;
    blocks.iter().find_map(|block| {
        let name = block.get("name").and_then(Value::as_str)?;
        if !matches!(name, "AskUserQuestion" | "ask_user_question") {
            return None;
        }
        build_agent_decision_request(
            "claude",
            block.get("id").and_then(Value::as_str),
            block.get("input").unwrap_or(&Value::Null),
            block.clone(),
        )
    })
}

fn extract_codex_decision_request(json: &Value) -> Option<AgentDecisionRequest> {
    extract_codex_decision_request_from_value(json, 0)
}

fn extract_codex_decision_request_from_value(
    value: &Value,
    depth: usize,
) -> Option<AgentDecisionRequest> {
    if depth > 6 {
        return None;
    }

    if let Some(request) = maybe_build_codex_decision_request(value) {
        return Some(request);
    }

    match value {
        Value::Array(items) => items
            .iter()
            .find_map(|item| extract_codex_decision_request_from_value(item, depth + 1)),
        Value::Object(map) => map
            .values()
            .find_map(|item| extract_codex_decision_request_from_value(item, depth + 1)),
        _ => None,
    }
}

fn maybe_build_codex_decision_request(value: &Value) -> Option<AgentDecisionRequest> {
    let name = value
        .get("name")
        .or_else(|| value.get("tool_name"))
        .and_then(Value::as_str)?;
    if !name.eq_ignore_ascii_case("request_user_input") {
        return None;
    }

    let args = value
        .get("input")
        .cloned()
        .or_else(|| parse_tool_arguments(value.get("arguments")))
        .or_else(|| value.get("args").cloned())
        .unwrap_or(Value::Null);
    build_agent_decision_request(
        "codex",
        value
            .get("id")
            .or_else(|| value.get("call_id"))
            .or_else(|| value.get("tool_call_id"))
            .and_then(Value::as_str),
        &args,
        value.clone(),
    )
}

fn build_agent_decision_request(
    provider: &'static str,
    provider_request_id: Option<&str>,
    input: &Value,
    raw_request: Value,
) -> Option<AgentDecisionRequest> {
    let questions = normalize_agent_decision_questions(input);
    let primary_question = questions
        .first()
        .and_then(|question| question.get("question"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?
        .to_string();
    let options = questions
        .first()
        .and_then(|question| question.get("options"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.get("label").and_then(Value::as_str))
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Some(AgentDecisionRequest {
        provider,
        provider_request_id: provider_request_id
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned),
        question: primary_question,
        options,
        questions: Some(Value::Array(questions)),
        raw_request,
    })
}

fn normalize_agent_decision_questions(input: &Value) -> Vec<Value> {
    if let Some(questions) = input.get("questions").and_then(Value::as_array) {
        let normalized = questions
            .iter()
            .filter_map(normalize_agent_decision_question)
            .collect::<Vec<_>>();
        if !normalized.is_empty() {
            return normalized;
        }
    }

    normalize_agent_decision_question(input)
        .into_iter()
        .collect::<Vec<_>>()
}

fn normalize_agent_decision_question(value: &Value) -> Option<Value> {
    let question = first_non_empty_string([
        value.get("question"),
        value.get("prompt"),
        value.get("message"),
        value.get("title"),
    ])?;
    let mut normalized = serde_json::Map::new();
    if let Some(id) = first_non_empty_string([value.get("id"), value.get("key")]) {
        normalized.insert("id".to_string(), Value::String(id));
    }
    if let Some(header) = first_non_empty_string([value.get("header"), value.get("label")]) {
        normalized.insert("header".to_string(), Value::String(header));
    }
    normalized.insert("question".to_string(), Value::String(question));
    let options = normalize_agent_decision_options(
        value
            .get("options")
            .or_else(|| value.get("choices"))
            .or_else(|| value.get("items")),
    );
    if !options.is_empty() {
        normalized.insert("options".to_string(), Value::Array(options));
    }
    Some(Value::Object(normalized))
}

fn normalize_agent_decision_options(value: Option<&Value>) -> Vec<Value> {
    let Some(Value::Array(items)) = value else {
        return Vec::new();
    };

    items
        .iter()
        .filter_map(|item| match item {
            Value::String(label) => {
                let label = label.trim();
                if label.is_empty() {
                    None
                } else {
                    Some(json!({ "label": label }))
                }
            }
            Value::Object(_) => {
                let label = first_non_empty_string([
                    item.get("label"),
                    item.get("title"),
                    item.get("name"),
                    item.get("value"),
                ])?;
                let description =
                    first_non_empty_string([item.get("description"), item.get("hint")]);
                let mut option = serde_json::Map::new();
                option.insert("label".to_string(), Value::String(label));
                if let Some(description) = description {
                    option.insert("description".to_string(), Value::String(description));
                }
                Some(Value::Object(option))
            }
            _ => None,
        })
        .collect()
}

fn parse_tool_arguments(arguments: Option<&Value>) -> Option<Value> {
    match arguments? {
        Value::Object(map) => Some(Value::Object(map.clone())),
        Value::String(text) => serde_json::from_str::<Value>(text).ok(),
        _ => None,
    }
}

fn first_non_empty_string<const N: usize>(values: [Option<&Value>; N]) -> Option<String> {
    values.into_iter().find_map(|value| {
        value
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|candidate| !candidate.is_empty())
            .map(ToOwned::to_owned)
    })
}

fn decision_request_request_key(run: &AgentRun, decision_request: &AgentDecisionRequest) -> String {
    let mut hasher = Sha256::new();
    hasher.update(run.id.as_bytes());
    hasher.update(decision_request.provider.as_bytes());
    if let Some(provider_request_id) = decision_request.provider_request_id.as_deref() {
        hasher.update(provider_request_id.as_bytes());
    }
    hasher.update(decision_request.question.as_bytes());
    if let Some(questions) = decision_request.questions.as_ref() {
        hasher.update(questions.to_string().as_bytes());
    }
    format!("{:x}", hasher.finalize())
}

fn format_approval_prompt_context(approval: &Approval) -> Option<String> {
    let question = approval
        .payload
        .get("question")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .or_else(|| {
            approval
                .payload
                .pointer("/questions/0/question")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
        })?;
    let mut context = format!(
        "Board approval context:\nApproval ID: {}\nApproval type: {}\nDecision status: {}\nRequested decision: {}",
        approval.id,
        approval.approval_type,
        approval.status,
        question,
    );

    if let Some(questions) = approval.payload.get("questions").and_then(Value::as_array) {
        for question in questions {
            let prompt = question
                .get("question")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty());
            let Some(prompt) = prompt else {
                continue;
            };
            context.push_str(&format!("\n- {prompt}"));
            if let Some(options) = question.get("options").and_then(Value::as_array) {
                let labels = options
                    .iter()
                    .filter_map(|option| option.get("label").and_then(Value::as_str))
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .collect::<Vec<_>>();
                if !labels.is_empty() {
                    context.push_str(&format!("\n  Options: {}", labels.join(", ")));
                }
            }
        }
    }

    if let Some(decision_note) = approval
        .decision_note
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        context.push_str(&format!("\nBoard answer:\n{decision_note}"));
    } else {
        context.push_str("\nBoard answer: Approved without an explicit note.");
    }

    Some(context)
}

fn extract_result_error_message(raw_json: &str) -> String {
    let Ok(json) = serde_json::from_str::<Value>(raw_json) else {
        return "Claude reported an error result".to_string();
    };

    if let Some(content) = json.get("content").and_then(Value::as_str) {
        let trimmed = content.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    if let Some(text) = json
        .pointer("/result/content/0/text")
        .and_then(Value::as_str)
    {
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    "Claude reported an error result".to_string()
}

fn governance_instructions(
    paths: &Paths,
    agent: &Agent,
    run: &AgentRun,
    issue_id: Option<&str>,
) -> String {
    let helper_binary = shell_quote(&board_helper_binary_path());
    let base_dir = shell_quote(&paths.base_dir().to_string_lossy());
    let company_id = shell_quote(&agent.company_id);
    let agent_id = shell_quote(&agent.id);
    let run_id = shell_quote(&run.id);
    let hire_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board hire-agent --company-id {company_id} --name \"Founding Engineer\" --role \"founding_engineer\" --title \"Founding Engineer\" --source-issue-id {} --requested-by-agent-id {agent_id} --requested-by-run-id {run_id}",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board hire-agent --company-id {company_id} --name \"Founding Engineer\" --role \"founding_engineer\" --title \"Founding Engineer\" --requested-by-agent-id {agent_id} --requested-by-run-id {run_id}"
        ),
    };
    let issue_create_example = format!(
        "{helper_binary} --base-dir {base_dir} board issue-create --company-id {company_id} --title \"Describe the work\" --description-file ./issue.md --assignee-agent-id {agent_id}"
    );
    let issue_list_example = format!(
        "{helper_binary} --base-dir {base_dir} board issue-list --company-id {company_id} --assignee-agent-id {agent_id}"
    );
    let issue_get_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-get --issue-id {}",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-get --issue-id \"<issue-id>\""
        ),
    };
    let issue_comment_list_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-comment-list --issue-id {}",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-comment-list --issue-id \"<issue-id>\""
        ),
    };
    let issue_attachment_list_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-attachment-list --issue-id {}",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-attachment-list --issue-id \"<issue-id>\""
        ),
    };
    let issue_checkout_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-checkout --issue-id {}",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-checkout --issue-id \"<issue-id>\""
        ),
    };
    let issue_update_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-update --issue-id {} --status in_progress",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-update --issue-id \"<issue-id>\" --status in_progress"
        ),
    };
    let issue_comment_example = match issue_id {
        Some(issue_id) => format!(
            "{helper_binary} --base-dir {base_dir} board issue-comment-add --company-id {company_id} --issue-id {} --author-agent-id {agent_id} --body \"Need board approval for the new hire.\"",
            shell_quote(issue_id),
        ),
        None => format!(
            "{helper_binary} --base-dir {base_dir} board issue-comment-add --company-id {company_id} --issue-id \"<issue-id>\" --author-agent-id {agent_id} --body \"Need board approval for the new hire.\""
        ),
    };

    format!(
        "Governance rules:\n\
         - Hiring must use the board helper commands below.\n\
         - Never create sibling agent directories under companies/.../agents manually.\n\
         - Direct filesystem creation of agent homes does not create board records, linked approvals, or UI-visible agents.\n\
         - If company policy requires approval, a board hire request will create the approval automatically and leave the agent in pending_approval until approved.\n\n\
         Board helper commands:\n\
         - Hire agent: {hire_example}\n\
         - List assigned issues: {issue_list_example}\n\
         - Get issue details: {issue_get_example}\n\
         - List issue comments: {issue_comment_list_example}\n\
         - List issue attachments: {issue_attachment_list_example}\n\
         - Prepare the issue worktree: {issue_checkout_example}\n\
         - Create issue: {issue_create_example}\n\
         - Update issue: {issue_update_example}\n\
         - Add issue comment: {issue_comment_example}\n\
         - The board helper returns JSON you can inspect after each command.\n",
    )
}

fn board_helper_binary_path() -> String {
    std::env::current_exe()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_else(|_| "unbound-daemon".to_string())
}

fn shell_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

impl RunTaskSessionRef {
    fn agent_home() -> Self {
        Self {
            adapter_type: "agent_home".to_string(),
            task_key: "home".to_string(),
        }
    }

    fn issue_workspace(issue_id: &str) -> Self {
        Self {
            adapter_type: "issue_workspace".to_string(),
            task_key: format!("issue:{issue_id}"),
        }
    }

    fn issue_project_root(issue_id: &str) -> Self {
        Self {
            adapter_type: "issue_project_root".to_string(),
            task_key: format!("issue:{issue_id}"),
        }
    }
}

fn issue_run_session_strategy(issue: &Issue) -> IssueRunSessionStrategy {
    if issue_has_attached_workspace_target(issue) {
        IssueRunSessionStrategy::AttachedWorkspace
    } else if issue.project_id.is_some() {
        IssueRunSessionStrategy::ProjectRoot
    } else {
        IssueRunSessionStrategy::AgentHome
    }
}

fn task_session_ref_from_run(run: &AgentRun, issue_id: Option<&str>) -> Option<RunTaskSessionRef> {
    let snapshot = run.context_snapshot.as_ref()?;
    let adapter_type = snapshot
        .pointer("/task_session/adapter_type")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let task_key = snapshot
        .pointer("/task_session/task_key")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);

    match (adapter_type, task_key) {
        (Some(adapter_type), Some(task_key)) => Some(RunTaskSessionRef {
            adapter_type,
            task_key,
        }),
        _ => issue_id
            .map(RunTaskSessionRef::issue_workspace)
            .or_else(|| {
                if run.issue_id.is_none() {
                    Some(RunTaskSessionRef::agent_home())
                } else {
                    None
                }
            }),
    }
}

fn agent_cli_kind(agent: &Agent) -> AgentCliKind {
    let adapter_config = agent.adapter_config.as_object();
    detect_agent_cli_kind(
        adapter_config
            .and_then(|config| config.get("command"))
            .and_then(Value::as_str),
        adapter_config
            .and_then(|config| config.get("model"))
            .and_then(Value::as_str),
    )
}

fn agent_cli_label(kind: AgentCliKind) -> &'static str {
    shared_agent_cli_label(kind)
}

fn build_agent_cli_config(
    agent: &Agent,
    prompt: &str,
    working_dir: String,
    resume_session_id: Option<&str>,
) -> AgentCliConfig {
    let adapter_config = agent.adapter_config.as_object();
    let mut config =
        build_agent_cli_config_from_adapter(adapter_config, prompt, working_dir, resume_session_id);
    config.interrupt_grace_sec = agent_interrupt_grace_sec(agent);
    config
}

fn agent_timeout_sec(agent: &Agent) -> Option<u64> {
    agent
        .runtime_config
        .as_object()
        .and_then(|config| config.get("timeoutSec"))
        .and_then(Value::as_u64)
        .filter(|value| *value > 0)
}

fn agent_interrupt_grace_sec(agent: &Agent) -> Option<u64> {
    agent
        .runtime_config
        .as_object()
        .and_then(|config| config.get("interruptGraceSec"))
        .and_then(Value::as_u64)
        .filter(|value| *value > 0)
}

fn provider_name_for_cli_kind(kind: AgentCliKind) -> &'static str {
    match kind {
        AgentCliKind::Claude => "claude",
        AgentCliKind::Codex => "codex",
    }
}

fn stored_provider_session_id_for_kind(session: &Session, kind: AgentCliKind) -> Option<String> {
    match kind {
        AgentCliKind::Claude => {
            let provider = session.effective_provider();
            if provider.is_none() || provider == Some("claude") {
                session
                    .effective_provider_session_id()
                    .map(ToOwned::to_owned)
            } else {
                None
            }
        }
        AgentCliKind::Codex => {
            if session.effective_provider() == Some("codex") {
                session.provider_session_id.clone()
            } else {
                None
            }
        }
    }
}

fn process_event_type(json: &Value) -> String {
    let base = json
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("json")
        .to_string();

    if base.starts_with("item.") {
        if let Some(item_type) = json.pointer("/item/type").and_then(Value::as_str) {
            return format!("{base}.{item_type}");
        }
    }

    base
}

fn summarize_process_event(kind: AgentCliKind, json: &Value) -> Option<String> {
    match kind {
        AgentCliKind::Claude => summarize_agent_run_event(json)
            .or_else(|| summarize_agent_run_result(json))
            .or_else(|| summarize_agent_run_text(&json.to_string())),
        AgentCliKind::Codex => {
            let event_type = json.get("type").and_then(Value::as_str)?;
            match event_type {
                "thread.started" => json
                    .get("thread_id")
                    .and_then(Value::as_str)
                    .map(|thread_id| format!("Started Codex thread {thread_id}")),
                "item.completed" => {
                    let item = json.get("item")?;
                    match item.get("type").and_then(Value::as_str).unwrap_or("item") {
                        "agent_message" => item
                            .get("text")
                            .and_then(Value::as_str)
                            .and_then(summarize_agent_run_text),
                        "command_execution" => item
                            .get("aggregated_output")
                            .and_then(Value::as_str)
                            .and_then(summarize_agent_run_text)
                            .or_else(|| {
                                item.get("command")
                                    .and_then(Value::as_str)
                                    .map(|command| format!("Executed {command}"))
                            }),
                        _ => None,
                    }
                }
                "turn.completed" => Some("Codex turn completed".to_string()),
                _ => None,
            }
        }
    }
}

fn extract_process_session_id(kind: AgentCliKind, json: &Value) -> Option<String> {
    match kind {
        AgentCliKind::Claude => json
            .get("session_id")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        AgentCliKind::Codex => {
            if json.get("type").and_then(Value::as_str) == Some("thread.started") {
                json.get("thread_id")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned)
            } else {
                None
            }
        }
    }
}

fn extract_process_usage(kind: AgentCliKind, json: &Value) -> Option<Value> {
    match kind {
        AgentCliKind::Claude => json
            .get("usage")
            .cloned()
            .or_else(|| json.pointer("/result/usage").cloned()),
        AgentCliKind::Codex => {
            if json.get("type").and_then(Value::as_str) == Some("turn.completed") {
                json.get("usage").cloned()
            } else {
                None
            }
        }
    }
}

fn is_process_result_payload(kind: AgentCliKind, json: &Value) -> bool {
    match kind {
        AgentCliKind::Claude => json.get("type").and_then(Value::as_str) == Some("result"),
        AgentCliKind::Codex => json.get("type").and_then(Value::as_str) == Some("turn.completed"),
    }
}

fn extract_process_error(kind: AgentCliKind, json: &Value) -> Option<String> {
    match kind {
        AgentCliKind::Claude => {
            if json.get("type").and_then(Value::as_str) == Some("result")
                && json
                    .get("is_error")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
            {
                Some(extract_result_error_message(&json.to_string()))
            } else {
                None
            }
        }
        AgentCliKind::Codex => match json.get("type").and_then(Value::as_str) {
            Some("error") | Some("turn.failed") => json
                .get("message")
                .and_then(Value::as_str)
                .or_else(|| json.pointer("/error/message").and_then(Value::as_str))
                .map(ToOwned::to_owned)
                .or_else(|| Some(json.to_string())),
            _ => None,
        },
    }
}

fn compute_log_metadata(path: &Path) -> Result<(i64, Option<String>), BoardError> {
    if !path.exists() {
        return Ok((0, None));
    }
    let bytes = fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let digest = format!("{:x}", hasher.finalize());
    Ok((bytes.len() as i64, Some(digest)))
}

async fn next_run_seq(db: &AsyncDatabase, run_id: &str) -> Result<i64, BoardError> {
    let run_id = run_id.to_string();
    Ok(db
        .call_with_operation("agent_run.events.next_seq", move |conn| {
            let max_seq = conn.query_row(
                "SELECT MAX(seq) FROM agent_run_events WHERE run_id = ?1",
                params![run_id],
                |row| row.get::<_, Option<i64>>(0),
            )?;
            Ok(max_seq.unwrap_or(0) + 1)
        })
        .await?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_issue_for_strategy(
        project_id: Option<&str>,
        execution_workspace_settings: Option<Value>,
        workspace_session_id: Option<&str>,
    ) -> Issue {
        Issue {
            id: "issue-1".to_string(),
            company_id: "company-1".to_string(),
            project_id: project_id.map(ToOwned::to_owned),
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
    fn governance_instructions_forbid_filesystem_hiring_and_include_board_helper() {
        let paths = Paths::with_base_dir(
            std::env::temp_dir().join(format!("unbound-governance-{}", Uuid::new_v4())),
        );
        let agent = Agent {
            id: "agent-1".to_string(),
            company_id: "company-1".to_string(),
            name: "CEO".to_string(),
            slug: "ceo".to_string(),
            role: "ceo".to_string(),
            title: Some("Chief Executive Officer".to_string()),
            icon: Some("crown".to_string()),
            status: "idle".to_string(),
            reports_to: None,
            capabilities: None,
            adapter_type: "process".to_string(),
            adapter_config: json!({}),
            runtime_config: json!({}),
            budget_monthly_cents: 0,
            spent_monthly_cents: 0,
            permissions: json!({}),
            last_heartbeat_at: None,
            metadata: None,
            home_path: Some("/tmp/company/agents/ceo".to_string()),
            instructions_path: Some("/tmp/company/agents/ceo/AGENTS.md".to_string()),
            created_at: "2026-03-14T00:00:00Z".to_string(),
            updated_at: "2026-03-14T00:00:00Z".to_string(),
        };
        let run = AgentRun {
            id: "run-1".to_string(),
            company_id: "company-1".to_string(),
            agent_id: "agent-1".to_string(),
            issue_id: Some("issue-1".to_string()),
            invocation_source: "assignment".to_string(),
            trigger_detail: Some("system".to_string()),
            wake_reason: Some("issue_assigned".to_string()),
            status: "queued".to_string(),
            started_at: None,
            finished_at: None,
            error: None,
            wakeup_request_id: None,
            exit_code: None,
            signal: None,
            usage_json: None,
            result_json: None,
            session_id_before: None,
            session_id_after: None,
            log_store: None,
            log_ref: None,
            log_bytes: None,
            log_sha256: None,
            log_compressed: false,
            stdout_excerpt: None,
            stderr_excerpt: None,
            error_code: None,
            external_run_id: None,
            context_snapshot: None,
            created_at: "2026-03-14T00:00:00Z".to_string(),
            updated_at: "2026-03-14T00:00:00Z".to_string(),
        };

        let instructions = governance_instructions(&paths, &agent, &run, Some("issue-1"));

        assert!(instructions.contains("Hiring must use the board helper"));
        assert!(instructions.contains("Never create sibling agent directories"));
        assert!(instructions.contains("board hire-agent"));
        assert!(instructions.contains("--source-issue-id \"issue-1\""));
    }

    #[test]
    fn issue_assignment_wakes_start_fresh_claude_session() {
        assert!(!should_resume_claude_session(
            "assignment",
            Some("system"),
            Some("issue_assigned")
        ));
    }

    #[test]
    fn timer_and_manual_wakes_start_fresh_claude_session() {
        assert!(!should_resume_claude_session("timer", Some("system"), None));
        assert!(!should_resume_claude_session(
            SOURCE_ON_DEMAND,
            Some(TRIGGER_MANUAL),
            None
        ));
    }

    #[test]
    fn comment_driven_issue_wakes_can_resume_existing_session() {
        assert!(should_resume_claude_session(
            "automation",
            Some("system"),
            Some("issue_commented")
        ));
    }

    #[test]
    fn approval_driven_issue_wakes_can_resume_existing_session() {
        assert!(should_resume_claude_session(
            "automation",
            Some("system"),
            Some("approval_approved")
        ));
    }

    #[test]
    fn extract_agent_decision_request_reads_claude_question_blocks() {
        let json = json!({
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_123",
                        "name": "AskUserQuestion",
                        "input": {
                            "question": "Ship the migration?",
                            "options": ["Ship it", "Hold"]
                        }
                    }
                ]
            }
        });

        let request =
            extract_agent_decision_request(AgentCliKind::Claude, &json).expect("decision request");

        assert_eq!(request.provider, "claude");
        assert_eq!(request.provider_request_id.as_deref(), Some("toolu_123"));
        assert_eq!(request.question, "Ship the migration?");
        assert_eq!(request.options, vec!["Ship it", "Hold"]);
        assert_eq!(
            request
                .questions
                .as_ref()
                .and_then(|questions| questions.pointer("/0/question"))
                .and_then(Value::as_str),
            Some("Ship the migration?")
        );
    }

    #[test]
    fn extract_agent_decision_request_reads_codex_request_user_input_questions() {
        let json = json!({
            "type": "response.output_item.added",
            "item": {
                "id": "call_456",
                "type": "function_call",
                "name": "request_user_input",
                "arguments": "{\"questions\":[{\"id\":\"ship_it\",\"header\":\"Migration\",\"question\":\"Ship the migration?\",\"options\":[{\"label\":\"Ship it\",\"description\":\"Deploy now\"},{\"label\":\"Hold\",\"description\":\"Wait for review\"}]}]}"
            }
        });

        let request =
            extract_agent_decision_request(AgentCliKind::Codex, &json).expect("decision request");

        assert_eq!(request.provider, "codex");
        assert_eq!(request.provider_request_id.as_deref(), Some("call_456"));
        assert_eq!(request.question, "Ship the migration?");
        assert_eq!(request.options, vec!["Ship it", "Hold"]);
        assert_eq!(
            request
                .questions
                .as_ref()
                .and_then(|questions| questions.pointer("/0/header"))
                .and_then(Value::as_str),
            Some("Migration")
        );
    }

    #[test]
    fn approval_prompt_context_includes_board_answer() {
        let approval = Approval {
            id: "approval-1".to_string(),
            company_id: "company-1".to_string(),
            approval_type: "agent_decision".to_string(),
            requested_by_agent_id: Some("agent-1".to_string()),
            requested_by_user_id: None,
            status: "approved".to_string(),
            payload: json!({
                "question": "Ship the migration?",
                "questions": [
                    {
                        "header": "Migration",
                        "question": "Ship the migration?",
                        "options": [
                            { "label": "Ship it" },
                            { "label": "Hold" }
                        ]
                    }
                ]
            }),
            decision_note: Some("Migration: Ship it".to_string()),
            decided_by_user_id: Some("local-board".to_string()),
            decided_at: Some("2026-03-20T10:05:00Z".to_string()),
            created_at: "2026-03-20T10:00:00Z".to_string(),
            updated_at: "2026-03-20T10:05:00Z".to_string(),
        };

        let context = format_approval_prompt_context(&approval).expect("approval context");

        assert!(context.contains("Approval ID: approval-1"));
        assert!(context.contains("Ship the migration?"));
        assert!(context.contains("Ship it, Hold"));
        assert!(context.contains("Migration: Ship it"));
    }

    #[test]
    fn comment_driven_runs_skip_idempotency_coalescing() {
        assert_eq!(
            build_idempotency_key(
                "agent-1",
                "automation",
                Some("system"),
                Some("issue_commented"),
                Some("issue-1"),
                None,
            ),
            None
        );
        assert_eq!(
            build_idempotency_key(
                "agent-1",
                "automation",
                Some("system"),
                Some("issue_comment_mentioned"),
                Some("issue-1"),
                None,
            ),
            None
        );
        assert_eq!(
            build_idempotency_key(
                "agent-1",
                "automation",
                Some("system"),
                Some("issue_reopened_via_comment"),
                Some("issue-1"),
                None,
            ),
            None
        );
    }

    #[test]
    fn only_comment_runs_wait_for_prior_issue_queue() {
        assert!(queued_run_waits_for_prior_issue_runs(
            Some("issue-1"),
            Some("issue_commented")
        ));
        assert!(queued_run_waits_for_prior_issue_runs(
            Some("issue-1"),
            Some("issue_comment_mentioned")
        ));
        assert!(!queued_run_waits_for_prior_issue_runs(
            Some("issue-1"),
            Some("issue_assigned")
        ));
        assert!(!queued_run_waits_for_prior_issue_runs(
            None,
            Some("issue_commented")
        ));
    }

    #[test]
    fn older_pending_issue_runs_block_comment_claims() {
        let conn = rusqlite::Connection::open_in_memory().expect("in-memory db");
        conn.execute_batch(
            "CREATE TABLE agent_runs (
                id TEXT PRIMARY KEY,
                issue_id TEXT,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL
            );",
        )
        .expect("create agent_runs table");

        conn.execute(
            "INSERT INTO agent_runs (id, issue_id, status, created_at)
             VALUES (?1, ?2, 'running', ?3)",
            params!["run-1", "issue-1", "2026-03-20T10:00:00Z"],
        )
        .expect("seed running run");
        conn.execute(
            "INSERT INTO agent_runs (id, issue_id, status, created_at)
             VALUES (?1, ?2, 'queued', ?3)",
            params!["run-2", "issue-1", "2026-03-20T10:01:00Z"],
        )
        .expect("seed candidate run");
        conn.execute(
            "INSERT INTO agent_runs (id, issue_id, status, created_at)
             VALUES (?1, ?2, 'queued', ?3)",
            params!["run-3", "issue-2", "2026-03-20T09:59:00Z"],
        )
        .expect("seed unrelated run");
        conn.execute(
            "INSERT INTO agent_runs (id, issue_id, status, created_at)
             VALUES (?1, ?2, 'succeeded', ?3)",
            params!["run-4", "issue-1", "2026-03-20T09:58:00Z"],
        )
        .expect("seed finished run");

        let candidate_rowid: i64 = conn
            .query_row(
                "SELECT rowid FROM agent_runs WHERE id = 'run-2'",
                [],
                |row| row.get(0),
            )
            .expect("candidate rowid");

        assert!(has_older_pending_issue_runs(
            &conn,
            "issue-1",
            "2026-03-20T10:01:00Z",
            candidate_rowid,
        )
        .expect("older pending runs query"));

        assert!(!has_older_pending_issue_runs(
            &conn,
            "issue-2",
            "2026-03-20T09:59:00Z",
            conn.query_row(
                "SELECT rowid FROM agent_runs WHERE id = 'run-3'",
                [],
                |row| row.get(0)
            )
            .expect("other issue rowid"),
        )
        .expect("other issue pending query"));
    }

    #[test]
    fn render_template_replaces_nested_values() {
        let rendered = render_template(
            "Agent {{ agent.name }} on {{ issue.id }} via {{ run.id }}",
            &json!({
                "agent": { "name": "CEO" },
                "issue": { "id": "issue-1" },
                "run": { "id": "run-1" },
            }),
        );

        assert_eq!(rendered, "Agent CEO on issue-1 via run-1");
    }

    #[test]
    fn issue_run_strategy_prefers_attached_workspace_targets() {
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(
                Some("project-1"),
                Some(json!({ "mode": "main" })),
                None,
            )),
            IssueRunSessionStrategy::AttachedWorkspace
        );
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(
                Some("project-1"),
                Some(json!({ "mode": "new_worktree" })),
                None,
            )),
            IssueRunSessionStrategy::AttachedWorkspace
        );
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(
                Some("project-1"),
                Some(json!({
                    "mode": "existing_worktree",
                    "worktree_path": "/tmp/existing-worktree"
                })),
                None,
            )),
            IssueRunSessionStrategy::AttachedWorkspace
        );
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(
                Some("project-1"),
                None,
                Some("session-1"),
            )),
            IssueRunSessionStrategy::AttachedWorkspace
        );
    }

    #[test]
    fn issue_run_strategy_uses_project_root_without_attached_workspace() {
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(Some("project-1"), None, None,)),
            IssueRunSessionStrategy::ProjectRoot
        );
    }

    #[test]
    fn issue_run_strategy_falls_back_to_agent_home_without_project() {
        assert_eq!(
            issue_run_session_strategy(&test_issue_for_strategy(None, None, None)),
            IssueRunSessionStrategy::AgentHome
        );
    }

    #[test]
    fn task_session_ref_reads_snapshot_and_legacy_fallbacks() {
        let run = AgentRun {
            id: "run-1".to_string(),
            company_id: "company-1".to_string(),
            agent_id: "agent-1".to_string(),
            issue_id: Some("issue-1".to_string()),
            invocation_source: "assignment".to_string(),
            trigger_detail: Some("system".to_string()),
            wake_reason: Some("issue_assigned".to_string()),
            status: "running".to_string(),
            started_at: None,
            finished_at: None,
            error: None,
            wakeup_request_id: None,
            exit_code: None,
            signal: None,
            usage_json: None,
            result_json: None,
            session_id_before: None,
            session_id_after: None,
            log_store: None,
            log_ref: None,
            log_bytes: None,
            log_sha256: None,
            log_compressed: false,
            stdout_excerpt: None,
            stderr_excerpt: None,
            error_code: None,
            external_run_id: None,
            context_snapshot: Some(json!({
                "task_session": {
                    "adapter_type": "issue_project_root",
                    "task_key": "issue:issue-1"
                }
            })),
            created_at: "2026-03-20T00:00:00Z".to_string(),
            updated_at: "2026-03-20T00:00:00Z".to_string(),
        };

        let restored = task_session_ref_from_run(&run, Some("issue-1"))
            .expect("expected task session ref from snapshot");
        assert_eq!(restored.adapter_type, "issue_project_root");
        assert_eq!(restored.task_key, "issue:issue-1");

        let legacy_issue_run = AgentRun {
            context_snapshot: Some(json!({})),
            ..run.clone()
        };
        let legacy_issue_ref = task_session_ref_from_run(&legacy_issue_run, Some("issue-2"))
            .expect("expected legacy issue workspace fallback");
        assert_eq!(legacy_issue_ref.adapter_type, "issue_workspace");
        assert_eq!(legacy_issue_ref.task_key, "issue:issue-2");

        let home_run = AgentRun {
            issue_id: None,
            context_snapshot: Some(json!({})),
            ..run
        };
        let home_ref =
            task_session_ref_from_run(&home_run, None).expect("expected agent home fallback");
        assert_eq!(home_ref.adapter_type, "agent_home");
        assert_eq!(home_ref.task_key, "home");
    }
}
