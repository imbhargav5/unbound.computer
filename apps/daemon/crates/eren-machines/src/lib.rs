//! Process lifecycle management (Claude CLI, terminal) for the Unbound daemon.
//!
//! Owns the process registry (tracking running processes by session ID)
//! and the event bridge (converting process events to Armin messages).

use armin::{AgentStatus, ArminError, NewMessage, SessionId, SessionWriter};
use std::collections::HashMap;
use std::sync::Mutex;
use thiserror::Error;
use tokio::sync::broadcast;

/// Errors from process management.
#[derive(Error, Debug)]
pub enum ProcessError {
    #[error("Process already running for session: {0}")]
    AlreadyRunning(String),
    #[error("No process running for session: {0}")]
    NotRunning(String),
    #[error("Armin error: {0}")]
    Armin(#[from] ArminError),
}

/// Status of a managed process.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProcessStatus {
    Running,
    NotRunning,
}

/// A registry of running processes indexed by session ID.
pub struct ProcessRegistry {
    /// Maps session_id -> stop channel sender.
    processes: Mutex<HashMap<String, broadcast::Sender<()>>>,
}

impl ProcessRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {
        Self {
            processes: Mutex::new(HashMap::new()),
        }
    }

    /// Register a process for a session. Returns the stop sender for the caller to hold.
    ///
    /// Returns error if a process is already running for this session.
    pub fn register(&self, session_id: &str) -> Result<broadcast::Sender<()>, ProcessError> {
        let mut procs = self.processes.lock().unwrap();
        if procs.contains_key(session_id) {
            return Err(ProcessError::AlreadyRunning(session_id.to_string()));
        }
        let (tx, _) = broadcast::channel(1);
        procs.insert(session_id.to_string(), tx.clone());
        Ok(tx)
    }

    /// Stop a process by session ID. Returns true if the process was found and stopped.
    pub fn stop(&self, session_id: &str) -> bool {
        let mut procs = self.processes.lock().unwrap();
        if let Some(tx) = procs.remove(session_id) {
            let _ = tx.send(());
            true
        } else {
            false
        }
    }

    /// Remove a process from the registry (called after process exits).
    pub fn remove(&self, session_id: &str) {
        let mut procs = self.processes.lock().unwrap();
        procs.remove(session_id);
    }

    /// Check the status of a process.
    pub fn status(&self, session_id: &str) -> ProcessStatus {
        let procs = self.processes.lock().unwrap();
        if procs.contains_key(session_id) {
            ProcessStatus::Running
        } else {
            ProcessStatus::NotRunning
        }
    }

    /// Get the number of running processes.
    pub fn count(&self) -> usize {
        let procs = self.processes.lock().unwrap();
        procs.len()
    }

    /// Check if any processes are running.
    pub fn is_empty(&self) -> bool {
        self.count() == 0
    }

    /// List all session IDs with running processes.
    pub fn session_ids(&self) -> Vec<String> {
        let procs = self.processes.lock().unwrap();
        procs.keys().cloned().collect()
    }
}

impl Default for ProcessRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Bridge functions for converting Claude JSON events into Armin messages.
///
/// Extracted from `machines/claude/stream.rs`. These free functions take
/// a `&impl SessionWriter` so they work with both owned and shared writers.
pub mod claude_bridge {
    use super::*;

    /// Store a raw JSON event as a message in the session.
    pub fn store_event(
        writer: &impl SessionWriter,
        session_id: &SessionId,
        raw_json: &str,
    ) -> Result<armin::Message, ArminError> {
        writer.append(
            session_id,
            NewMessage {
                content: raw_json.to_string(),
            },
        )
    }

    /// Update the Claude session ID on the session.
    pub fn update_claude_session_id(
        writer: &impl SessionWriter,
        session_id: &SessionId,
        claude_session_id: &str,
    ) -> Result<bool, ArminError> {
        writer.update_session_claude_id(session_id, claude_session_id)
    }

    /// Set agent status to running.
    pub fn set_running(
        writer: &impl SessionWriter,
        session_id: &SessionId,
    ) -> Result<(), ArminError> {
        writer.update_agent_status(session_id, AgentStatus::Running)
    }

    /// Set agent status to idle.
    pub fn set_idle(
        writer: &impl SessionWriter,
        session_id: &SessionId,
    ) -> Result<(), ArminError> {
        writer.update_agent_status(session_id, AgentStatus::Idle)
    }
}

/// Bridge functions for converting terminal output into Armin messages.
///
/// Extracted from `machines/terminal/stream.rs`.
pub mod terminal_bridge {
    use super::*;

    /// Store a stdout line as a message.
    pub fn store_stdout(
        writer: &impl SessionWriter,
        session_id: &SessionId,
        line: &str,
    ) -> Result<armin::Message, ArminError> {
        let content = serde_json::json!({
            "type": "terminal_output",
            "stream": "stdout",
            "content": line,
        })
        .to_string();
        writer.append(session_id, NewMessage { content })
    }

    /// Store a stderr line as a message.
    pub fn store_stderr(
        writer: &impl SessionWriter,
        session_id: &SessionId,
        line: &str,
    ) -> Result<armin::Message, ArminError> {
        let content = serde_json::json!({
            "type": "terminal_output",
            "stream": "stderr",
            "content": line,
        })
        .to_string();
        writer.append(session_id, NewMessage { content })
    }

    /// Store the terminal finished event with exit code.
    pub fn store_finished(
        writer: &impl SessionWriter,
        session_id: &SessionId,
        exit_code: i32,
    ) -> Result<armin::Message, ArminError> {
        let content = serde_json::json!({
            "type": "terminal_finished",
            "exit_code": exit_code,
        })
        .to_string();
        writer.append(session_id, NewMessage { content })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use armin::SessionReader;

    // =========================================================================
    // ProcessRegistry tests
    // =========================================================================

    #[test]
    fn registry_starts_empty() {
        let reg = ProcessRegistry::new();
        assert!(reg.is_empty());
        assert_eq!(reg.count(), 0);
    }

    #[test]
    fn registry_register_adds_process() {
        let reg = ProcessRegistry::new();
        let _tx = reg.register("sess-1").unwrap();
        assert_eq!(reg.count(), 1);
        assert_eq!(reg.status("sess-1"), ProcessStatus::Running);
    }

    #[test]
    fn registry_register_duplicate_fails() {
        let reg = ProcessRegistry::new();
        let _tx = reg.register("sess-1").unwrap();
        let result = reg.register("sess-1");
        assert!(matches!(result, Err(ProcessError::AlreadyRunning(_))));
    }

    #[test]
    fn registry_stop_removes_and_signals() {
        let reg = ProcessRegistry::new();
        let tx = reg.register("sess-1").unwrap();
        let mut rx = tx.subscribe();

        assert!(reg.stop("sess-1"));
        assert_eq!(reg.status("sess-1"), ProcessStatus::NotRunning);
        assert!(rx.try_recv().is_ok());
    }

    #[test]
    fn registry_stop_nonexistent_returns_false() {
        let reg = ProcessRegistry::new();
        assert!(!reg.stop("nonexistent"));
    }

    #[test]
    fn registry_remove_cleans_up() {
        let reg = ProcessRegistry::new();
        let _tx = reg.register("sess-1").unwrap();
        reg.remove("sess-1");
        assert!(reg.is_empty());
    }

    #[test]
    fn registry_remove_nonexistent_is_noop() {
        let reg = ProcessRegistry::new();
        reg.remove("nonexistent"); // should not panic
        assert!(reg.is_empty());
    }

    #[test]
    fn registry_status_not_running_for_unknown() {
        let reg = ProcessRegistry::new();
        assert_eq!(reg.status("unknown"), ProcessStatus::NotRunning);
    }

    #[test]
    fn registry_multiple_processes() {
        let reg = ProcessRegistry::new();
        let _tx1 = reg.register("sess-1").unwrap();
        let _tx2 = reg.register("sess-2").unwrap();
        let _tx3 = reg.register("sess-3").unwrap();

        assert_eq!(reg.count(), 3);
        assert_eq!(reg.status("sess-1"), ProcessStatus::Running);
        assert_eq!(reg.status("sess-2"), ProcessStatus::Running);
        assert_eq!(reg.status("sess-3"), ProcessStatus::Running);
    }

    #[test]
    fn registry_stop_one_of_many() {
        let reg = ProcessRegistry::new();
        let _tx1 = reg.register("sess-1").unwrap();
        let _tx2 = reg.register("sess-2").unwrap();

        reg.stop("sess-1");
        assert_eq!(reg.count(), 1);
        assert_eq!(reg.status("sess-1"), ProcessStatus::NotRunning);
        assert_eq!(reg.status("sess-2"), ProcessStatus::Running);
    }

    #[test]
    fn registry_session_ids() {
        let reg = ProcessRegistry::new();
        let _tx1 = reg.register("alpha").unwrap();
        let _tx2 = reg.register("beta").unwrap();

        let mut ids = reg.session_ids();
        ids.sort();
        assert_eq!(ids, vec!["alpha", "beta"]);
    }

    #[test]
    fn registry_re_register_after_remove() {
        let reg = ProcessRegistry::new();
        let _tx = reg.register("sess-1").unwrap();
        reg.remove("sess-1");
        let _tx2 = reg.register("sess-1").unwrap();
        assert_eq!(reg.count(), 1);
    }

    #[test]
    fn registry_re_register_after_stop() {
        let reg = ProcessRegistry::new();
        let _tx = reg.register("sess-1").unwrap();
        reg.stop("sess-1");
        let _tx2 = reg.register("sess-1").unwrap();
        assert_eq!(reg.status("sess-1"), ProcessStatus::Running);
    }

    #[test]
    fn registry_default_is_empty() {
        let reg = ProcessRegistry::default();
        assert!(reg.is_empty());
    }

    // =========================================================================
    // claude_bridge tests using Armin in-memory
    // =========================================================================

    fn make_armin() -> armin::Armin<armin::NullSink> {
        armin::Armin::in_memory(armin::NullSink).unwrap()
    }

    #[test]
    fn claude_bridge_store_event() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = claude_bridge::store_event(
            &armin,
            &session_id,
            r#"{"type":"assistant","content":"hi"}"#,
        )
        .unwrap();
        assert_eq!(msg.content, r#"{"type":"assistant","content":"hi"}"#);
    }

    #[test]
    fn claude_bridge_store_multiple_events_increments_sequence() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let m1 = claude_bridge::store_event(&armin, &session_id, "event-1").unwrap();
        let m2 = claude_bridge::store_event(&armin, &session_id, "event-2").unwrap();
        let m3 = claude_bridge::store_event(&armin, &session_id, "event-3").unwrap();

        assert!(m2.sequence_number > m1.sequence_number);
        assert!(m3.sequence_number > m2.sequence_number);
    }

    #[test]
    fn claude_bridge_set_running_and_idle() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        claude_bridge::set_running(&armin, &session_id).unwrap();
        let state = armin.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(state.agent_status, AgentStatus::Running);

        claude_bridge::set_idle(&armin, &session_id).unwrap();
        let state = armin.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(state.agent_status, AgentStatus::Idle);
    }

    #[test]
    fn claude_bridge_update_claude_session_id() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        claude_bridge::update_claude_session_id(&armin, &session_id, "claude-abc-123").unwrap();

        let session = armin.get_session(&session_id).unwrap().unwrap();
        assert_eq!(session.claude_session_id.as_deref(), Some("claude-abc-123"));
    }

    #[test]
    fn claude_bridge_store_event_to_nonexistent_session_fails() {
        let armin = make_armin();
        let fake_id = SessionId::from_string("nonexistent");

        let result = claude_bridge::store_event(&armin, &fake_id, "data");
        assert!(result.is_err());
    }

    // =========================================================================
    // terminal_bridge tests using Armin in-memory
    // =========================================================================

    #[test]
    fn terminal_bridge_store_stdout() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = terminal_bridge::store_stdout(&armin, &session_id, "hello from stdout").unwrap();

        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["type"], "terminal_output");
        assert_eq!(parsed["stream"], "stdout");
        assert_eq!(parsed["content"], "hello from stdout");
    }

    #[test]
    fn terminal_bridge_store_stderr() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg =
            terminal_bridge::store_stderr(&armin, &session_id, "error: something failed").unwrap();

        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["type"], "terminal_output");
        assert_eq!(parsed["stream"], "stderr");
        assert_eq!(parsed["content"], "error: something failed");
    }

    #[test]
    fn terminal_bridge_store_finished() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = terminal_bridge::store_finished(&armin, &session_id, 0).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["type"], "terminal_finished");
        assert_eq!(parsed["exit_code"], 0);
    }

    #[test]
    fn terminal_bridge_store_finished_with_error_code() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = terminal_bridge::store_finished(&armin, &session_id, 127).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["exit_code"], 127);
    }

    #[test]
    fn terminal_bridge_store_finished_with_negative_code() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = terminal_bridge::store_finished(&armin, &session_id, -1).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["exit_code"], -1);
    }

    #[test]
    fn terminal_bridge_interleaved_stdout_stderr() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let m1 = terminal_bridge::store_stdout(&armin, &session_id, "out-1").unwrap();
        let m2 = terminal_bridge::store_stderr(&armin, &session_id, "err-1").unwrap();
        let m3 = terminal_bridge::store_stdout(&armin, &session_id, "out-2").unwrap();
        let m4 = terminal_bridge::store_finished(&armin, &session_id, 0).unwrap();

        assert!(m2.sequence_number > m1.sequence_number);
        assert!(m3.sequence_number > m2.sequence_number);
        assert!(m4.sequence_number > m3.sequence_number);
    }

    #[test]
    fn terminal_bridge_empty_line() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        let msg = terminal_bridge::store_stdout(&armin, &session_id, "").unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&msg.content).unwrap();
        assert_eq!(parsed["content"], "");
    }
}
