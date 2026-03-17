use crate::app::ensure_issue_workspace;
use crate::armin_adapter::DaemonArmin;
use crate::observability::{current_trace_context, spawn_in_current_span};
use crate::utils::SessionSecretCache;
use agent_session_sqlite_persist_core::{
    CodingSessionStatus, NewMessage, NewSession, RepositoryId, SessionId, SessionWriter,
};
use chrono::Utc;
use claude_process_manager::{ClaudeConfig, ClaudeEvent, ClaudeProcess};
use daemon_board::{service, Agent, AgentRun, BoardError, Issue, IssueComment, IssueListFilter};
use daemon_config_and_utils::Paths;
use daemon_database::{queries, AsyncDatabase, NewRepository};
use daemon_ipc::{Event, EventType, SubscriptionManager};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::cmp::Ordering;
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

const REASON_HEARTBEAT_TIMER: &str = "heartbeat_timer";
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

        let timer_runner = self.clone();
        spawn_in_current_span(async move {
            timer_runner.timer_loop().await;
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

    async fn timer_loop(self: Arc<Self>) {
        loop {
            if let Err(error) = self.enqueue_due_timer_runs().await {
                warn!(error = %error, "Failed to enqueue timer runs");
            }
            sleep(Duration::from_secs(5)).await;
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

    async fn enqueue_due_timer_runs(&self) -> Result<(), BoardError> {
        let agents = self
            .db
            .call_with_operation("agent_run.timer.agents", move |conn| {
                let mut stmt = conn.prepare(
                    "SELECT id, company_id, runtime_config, last_heartbeat_at, created_at
                     FROM agents
                     WHERE status NOT IN ('pending_approval', 'disabled')",
                )?;
                let rows = stmt
                    .query_map([], |row| {
                        Ok((
                            row.get::<_, String>(0)?,
                            row.get::<_, String>(1)?,
                            row.get::<_, String>(2)?,
                            row.get::<_, Option<String>>(3)?,
                            row.get::<_, String>(4)?,
                        ))
                    })?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(rows)
            })
            .await?;

        for (agent_id, company_id, runtime_config_text, last_heartbeat_at, created_at) in agents {
            let runtime_config = serde_json::from_str::<Value>(&runtime_config_text).ok();
            let heartbeat_config = runtime_config
                .as_ref()
                .and_then(|config| config.get("heartbeat"));
            let heartbeat_enabled = heartbeat_config
                .and_then(|config| config.get("enabled"))
                .and_then(Value::as_bool)
                .unwrap_or(true);
            let interval_sec = heartbeat_config
                .and_then(|config| config.get("intervalSec"))
                .and_then(Value::as_i64)
                .or_else(|| {
                    runtime_config
                        .as_ref()
                        .and_then(|config| config.get("intervalSec"))
                        .and_then(Value::as_i64)
                });
            if !heartbeat_enabled {
                continue;
            }
            let Some(interval_sec) = interval_sec else {
                continue;
            };
            if interval_sec <= 0 {
                continue;
            }

            let baseline = last_heartbeat_at.as_deref().unwrap_or(created_at.as_str());
            let due = match parse_rfc3339(baseline) {
                Some(date) => (Utc::now() - date).num_seconds() >= interval_sec,
                None => true,
            };
            if !due {
                continue;
            }

            let agent_id_for_due = agent_id.clone();
            let active_count: i64 = self
                .db
                .call_with_operation("agent_run.timer.active", move |conn| {
                    Ok(conn.query_row(
                        "SELECT COUNT(*) FROM agent_runs
                         WHERE agent_id = ?1
                           AND status IN ('queued', 'running')",
                        params![agent_id_for_due],
                        |row| row.get(0),
                    )?)
                })
                .await?;
            if active_count > 0 {
                continue;
            }

            let heartbeat_issue = self
                .next_heartbeat_issue_for_agent(&company_id, &agent_id)
                .await?;
            let payload = heartbeat_issue
                .as_ref()
                .map(|issue| json!({ "issue_id": issue.id }));

            let _ = self
                .enqueue_run(AgentRunEnqueueRequest {
                    agent_id: agent_id.clone(),
                    company_id: Some(company_id),
                    invocation_source: SOURCE_TIMER.to_string(),
                    trigger_detail: Some(TRIGGER_SYSTEM.to_string()),
                    wake_reason: Some(REASON_HEARTBEAT_TIMER.to_string()),
                    payload,
                    prompt: None,
                    requested_by_actor_type: Some("system".to_string()),
                    requested_by_actor_id: Some("scheduler".to_string()),
                })
                .await?;
        }

        Ok(())
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

    async fn next_heartbeat_issue_for_agent(
        &self,
        company_id: &str,
        agent_id: &str,
    ) -> Result<Option<Issue>, BoardError> {
        let issues = service::list_issues(
            &self.db,
            IssueListFilter {
                company_id: company_id.to_string(),
                assignee_agent_id: Some(agent_id.to_string()),
                include_hidden: Some(false),
                ..IssueListFilter::default()
            },
        )
        .await?;

        Ok(select_heartbeat_issue(issues))
    }

    async fn try_claim_run(&self, run_id: &str) -> Result<Option<RunLaunchContext>, BoardError> {
        let run_id = run_id.to_string();
        let run_id_for_fetch = run_id.clone();
        let now = now_rfc3339();
        let claimed = self
            .db
            .call_with_operation("agent_run.queue.claim", move |conn| {
                let tx = conn.unchecked_transaction()?;
                let agent_id: Option<String> = tx
                    .query_row(
                        "SELECT agent_id FROM agent_runs WHERE id = ?1 AND status = 'queued'",
                        params![run_id],
                        |row| row.get(0),
                    )
                    .optional()?;
                let Some(agent_id) = agent_id else {
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
        let claude_session_id_before = resolved_workspace.session.claude_session_id.clone();
        let resumes_existing_session = claude_session_id_before.as_ref().is_some_and(|_| {
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
                let session_id_before = claude_session_id_before.clone();
                let local_session_id = session.local_session_id.clone();
                move |conn| {
                    conn.execute(
                        "UPDATE agent_runs
                         SET session_id_before = ?1,
                             updated_at = ?2,
                             context_snapshot = json_set(
                                 COALESCE(context_snapshot, '{}'),
                                 '$.local_session_id', ?3
                             )
                         WHERE id = ?4",
                        params![session_id_before, now_rfc3339(), local_session_id, run_id],
                    )?;
                    Ok(())
                }
            })
            .await?;

        let armin_session_id = SessionId::from_string(&session.local_session_id);
        self.append_claude_message(&armin_session_id, &prompt, "agent_run_prompt");

        let mut config = ClaudeConfig::new(&prompt, resolved_workspace.working_dir);
        if let Some(ref previous_session_id) = claude_session_id_before {
            if resumes_existing_session {
                config = config.with_resume_session(previous_session_id);
            }
        }

        let mut process = match ClaudeProcess::spawn(config).await {
            Ok(process) => process,
            Err(error) => {
                self.finalize_run(
                    &run,
                    issue_id.as_deref(),
                    RunCompletion {
                        status: STATUS_FAILED.to_string(),
                        error: Some(format!("Failed to spawn claude: {error}")),
                        error_code: Some("spawn_failed".to_string()),
                        exit_code: None,
                        signal: None,
                        usage_json: None,
                        result_json: None,
                        session_id_after: claude_session_id_before.clone(),
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

        let mut stream = process
            .take_stream()
            .ok_or_else(|| BoardError::Runtime("Claude stream was unavailable".to_string()))?;
        let mut seq = 1_i64;
        let mut last_status: Option<CodingSessionStatus> = None;
        let mut last_error_message: Option<String> = None;
        let mut terminal_status_written = false;
        let mut stdout_excerpt = String::new();
        let mut stderr_excerpt = String::new();
        let mut usage_json: Option<Value> = None;
        let mut result_json: Option<Value> = None;
        let mut session_id_after = claude_session_id_before.clone();
        let mut external_run_id: Option<String> = None;
        let mut completion = RunCompletion {
            status: STATUS_FAILED.to_string(),
            error: Some("Claude run exited unexpectedly".to_string()),
            error_code: Some(ERROR_CODE_PROCESS_LOST.to_string()),
            exit_code: None,
            signal: None,
            usage_json: None,
            result_json: None,
            session_id_after: claude_session_id_before,
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

        while let Some(event) = stream.next().await {
            match &event {
                ClaudeEvent::Json {
                    event_type,
                    raw,
                    json,
                } => {
                    self.append_claude_message(&armin_session_id, raw, "claude_json");
                    self.broadcast_session_event(&session.local_session_id, raw);
                    if is_ask_user_question(json) {
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Waiting,
                            None,
                            "ask-user-question",
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
                    push_excerpt(&mut stdout_excerpt, raw);
                    self.record_run_event(
                        &run,
                        seq,
                        event_type,
                        Some("stdout"),
                        Some("info"),
                        Some(raw),
                        Some(json.clone()),
                    )
                    .await?;
                    if external_run_id.is_none() {
                        external_run_id = json
                            .get("session_id")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned)
                            .or_else(|| {
                                json.get("id")
                                    .and_then(Value::as_str)
                                    .map(ToOwned::to_owned)
                            });
                    }
                }
                ClaudeEvent::SystemWithSessionId {
                    claude_session_id,
                    raw,
                } => {
                    self.append_claude_message(&armin_session_id, raw, "claude_system");
                    if let Err(error) = self
                        .armin
                        .update_session_claude_id(&armin_session_id, claude_session_id)
                    {
                        warn!(error = %error, "Failed to update Claude session id");
                    }
                    self.broadcast_session_event(&session.local_session_id, raw);
                    self.write_runtime_status_if_changed(
                        &armin_session_id,
                        CodingSessionStatus::Running,
                        None,
                        "system-event",
                        &mut last_status,
                        &mut last_error_message,
                    );
                    session_id_after = Some(claude_session_id.clone());
                    external_run_id = Some(claude_session_id.clone());
                    push_excerpt(&mut stdout_excerpt, raw);
                    self.record_run_event(
                        &run,
                        seq,
                        "system",
                        Some("stdout"),
                        Some("info"),
                        Some(raw),
                        serde_json::from_str::<Value>(raw).ok(),
                    )
                    .await?;
                }
                ClaudeEvent::Result { is_error, raw } => {
                    self.append_claude_message(&armin_session_id, raw, "claude_result");
                    self.broadcast_session_event(&session.local_session_id, raw);
                    let parsed = serde_json::from_str::<Value>(raw).ok();
                    if let Some(parsed) = parsed.as_ref() {
                        usage_json = parsed
                            .get("usage")
                            .cloned()
                            .or_else(|| parsed.pointer("/result/usage").cloned());
                        result_json = Some(parsed.clone());
                    }
                    if *is_error {
                        let error_message = extract_result_error_message(raw);
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Error,
                            Some(error_message.clone()),
                            "result-error",
                            &mut last_status,
                            &mut last_error_message,
                        );
                        completion.status = STATUS_FAILED.to_string();
                        completion.error = Some(error_message);
                        completion.error_code = Some("result_error".to_string());
                    } else {
                        self.write_runtime_status_if_changed(
                            &armin_session_id,
                            CodingSessionStatus::Idle,
                            None,
                            "result-success",
                            &mut last_status,
                            &mut last_error_message,
                        );
                        completion.status = STATUS_SUCCEEDED.to_string();
                        completion.error = None;
                        completion.error_code = None;
                    }
                    terminal_status_written = true;
                    push_excerpt(&mut stdout_excerpt, raw);
                    self.record_run_event(
                        &run,
                        seq,
                        "result",
                        Some("stdout"),
                        Some(if *is_error { "error" } else { "info" }),
                        Some(raw),
                        parsed,
                    )
                    .await?;
                }
                ClaudeEvent::Stderr { line } => {
                    push_excerpt(&mut stderr_excerpt, line);
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
                ClaudeEvent::Finished { success, exit_code } => {
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
                        completion.status = STATUS_SUCCEEDED.to_string();
                        completion.error = None;
                        completion.error_code = None;
                    } else {
                        let error_message = match exit_code {
                            Some(code) => format!("Claude process exited with status {code}"),
                            None => "Claude process exited with non-zero status".to_string(),
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
                            "Claude process finished successfully"
                        } else {
                            "Claude process finished with an error"
                        }),
                        Some(json!({ "success": success, "exit_code": exit_code })),
                    )
                    .await?;
                }
                ClaudeEvent::Stopped => {
                    self.write_runtime_status_if_changed(
                        &armin_session_id,
                        CodingSessionStatus::NotAvailable,
                        None,
                        "process-stopped",
                        &mut last_status,
                        &mut last_error_message,
                    );
                    completion.status = STATUS_CANCELLED.to_string();
                    completion.error = Some("Run was cancelled".to_string());
                    completion.error_code = Some("cancelled".to_string());
                    terminal_status_written = true;
                    self.record_run_event(
                        &run,
                        seq,
                        "stopped",
                        Some("system"),
                        Some("info"),
                        Some("Run was cancelled"),
                        Some(json!({ "cancelled": true })),
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

        self.finalize_run(&run, issue_id.as_deref(), completion)
            .await?;
        self.queue_notify.notify_waiters();
        Ok(())
    }

    async fn finalize_run(
        &self,
        run: &AgentRun,
        issue_id: Option<&str>,
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

                let task_key = match issue_id_owned.as_ref() {
                    Some(issue_id) => format!("issue:{issue_id}"),
                    None => "home".to_string(),
                };
                let updated_issue_workspace_session = if issue_id_owned.is_some() {
                    tx.execute(
                        "UPDATE agent_task_sessions
                         SET last_run_id = ?1, last_error = ?2, updated_at = ?3
                         WHERE company_id = ?4 AND agent_id = ?5 AND adapter_type = 'issue_workspace' AND task_key = ?6",
                        params![run_id, error, now, company_id, agent_id, task_key],
                    )?
                } else {
                    0
                };
                if updated_issue_workspace_session == 0 {
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
            if issue.project_id.is_some() {
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
                });
            }
        }

        self.ensure_agent_home_session(agent).await
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
        })
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
        let rendered_prompt_template = rendered_prompt_template(agent, run, issue_id)
            .unwrap_or_else(|| default_heartbeat_prompt(agent, issue_id));
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
             Heartbeat operating rules:\n\
             - Heartbeats are short execution windows: wake up, inspect the assigned work, do the next useful step, and exit.\n\
             - If this run is linked to an issue, treat that issue as the primary work item for this heartbeat.\n\
             - If this run is not linked to an issue, list your assigned issues, work on in_progress first, then todo, and skip blocked work unless there is fresh context that lets you unblock it.\n\
             - Before doing issue work, make sure the issue worktree is ready with the board issue-checkout helper instead of creating ad hoc folders yourself.\n\
             - If you actively start a todo issue, move it to in_progress. If you finish it, mark it done with a concise summary. If you are blocked, mark it blocked and explain exactly what is needed.\n\
             - If you made progress but did not finish, leave a concise issue comment before exiting so the next heartbeat can continue cleanly.\n\
             - Work directly in the resolved local worktree. Only create or switch to a fresh git worktree when the issue or user explicitly asks for it.\n\
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
            warn!(error = %error, message_kind = event_kind, "Failed to append Claude event");
        }
    }

    fn broadcast_session_event(&self, session_id: &str, raw_json: &str) {
        let mut event = Event::new(
            EventType::ClaudeEvent,
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

fn parse_rfc3339(value: &str) -> Option<chrono::DateTime<Utc>> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| date.with_timezone(&Utc))
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

fn select_heartbeat_issue(mut issues: Vec<Issue>) -> Option<Issue> {
    issues.sort_by(compare_heartbeat_issue_priority);
    issues
        .into_iter()
        .find(|issue| heartbeat_issue_status_rank(&issue.status).is_some())
}

fn compare_heartbeat_issue_priority(left: &Issue, right: &Issue) -> Ordering {
    heartbeat_issue_status_rank(&left.status)
        .unwrap_or(i32::MAX)
        .cmp(&heartbeat_issue_status_rank(&right.status).unwrap_or(i32::MAX))
        .then_with(|| {
            heartbeat_priority_rank(&left.priority).cmp(&heartbeat_priority_rank(&right.priority))
        })
        .then_with(|| {
            left.issue_number
                .unwrap_or(i64::MAX)
                .cmp(&right.issue_number.unwrap_or(i64::MAX))
        })
        .then_with(|| left.created_at.cmp(&right.created_at))
}

fn heartbeat_issue_status_rank(status: &str) -> Option<i32> {
    match status {
        "in_progress" => Some(0),
        "todo" => Some(1),
        _ => None,
    }
}

fn heartbeat_priority_rank(priority: &str) -> i32 {
    match priority {
        "critical" => 0,
        "high" => 1,
        "medium" => 2,
        "low" => 3,
        _ => 4,
    }
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

fn default_heartbeat_prompt(agent: &Agent, issue_id: Option<&str>) -> String {
    if let Some(issue_id) = issue_id {
        return format!(
            "You run in short heartbeats. This heartbeat is focused on issue {issue_id}. Read the issue context, do the next useful piece of work in the linked worktree, and update the issue before you exit."
        );
    }

    format!(
        "You run in short heartbeats. Use this heartbeat to inspect work assigned to {agent_name} ({agent_role}), pick the highest-value actionable issue, do useful work in its worktree, and update that issue before you exit.",
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

fn is_ask_user_question(json: &Value) -> bool {
    json.get("message")
        .and_then(|message| message.get("content"))
        .and_then(Value::as_array)
        .map(|blocks| {
            blocks.iter().any(|block| {
                block.get("type").and_then(Value::as_str) == Some("tool_use")
                    && block.get("name").and_then(Value::as_str) == Some("AskUserQuestion")
            })
        })
        .unwrap_or(false)
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
    fn heartbeat_issue_selection_prefers_in_progress_then_priority() {
        let todo_high = Issue {
            id: "issue-todo-high".to_string(),
            company_id: "company-1".to_string(),
            project_id: None,
            goal_id: None,
            parent_id: None,
            title: "Todo high".to_string(),
            description: None,
            status: "todo".to_string(),
            priority: "high".to_string(),
            assignee_agent_id: Some("agent-1".to_string()),
            assignee_user_id: None,
            checkout_run_id: None,
            execution_run_id: None,
            execution_agent_name_key: None,
            execution_locked_at: None,
            created_by_agent_id: None,
            created_by_user_id: None,
            issue_number: Some(3),
            identifier: Some("ISS-3".to_string()),
            request_depth: 0,
            billing_code: None,
            assignee_adapter_overrides: None,
            execution_workspace_settings: None,
            started_at: None,
            completed_at: None,
            cancelled_at: None,
            hidden_at: None,
            workspace_session_id: None,
            created_at: "2026-03-18T10:00:00Z".to_string(),
            updated_at: "2026-03-18T10:00:00Z".to_string(),
        };
        let in_progress_medium = Issue {
            id: "issue-in-progress".to_string(),
            status: "in_progress".to_string(),
            priority: "medium".to_string(),
            issue_number: Some(4),
            identifier: Some("ISS-4".to_string()),
            created_at: "2026-03-18T09:00:00Z".to_string(),
            updated_at: "2026-03-18T09:00:00Z".to_string(),
            ..todo_high.clone()
        };
        let blocked_critical = Issue {
            id: "issue-blocked".to_string(),
            status: "blocked".to_string(),
            priority: "critical".to_string(),
            issue_number: Some(1),
            identifier: Some("ISS-1".to_string()),
            created_at: "2026-03-18T08:00:00Z".to_string(),
            updated_at: "2026-03-18T08:00:00Z".to_string(),
            ..todo_high.clone()
        };

        let selected =
            select_heartbeat_issue(vec![todo_high, in_progress_medium, blocked_critical])
                .expect("expected issue selection");

        assert_eq!(selected.id, "issue-in-progress");
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
}
