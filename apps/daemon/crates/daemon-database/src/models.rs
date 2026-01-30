//! Database model types.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Repository record - a registered git repository.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Repository {
    pub id: String,
    pub path: String,
    pub name: String,
    pub last_accessed_at: DateTime<Utc>,
    pub added_at: DateTime<Utc>,
    pub is_git_repository: bool,
    pub sessions_path: Option<String>,
    pub default_branch: Option<String>,
    pub default_remote: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Agent coding session - a Claude conversation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentCodingSession {
    pub id: String,
    pub repository_id: String,
    pub title: String,
    pub claude_session_id: Option<String>,
    pub status: SessionStatus,
    pub is_worktree: bool,
    pub worktree_path: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_accessed_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Session status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Active,
    Archived,
    Deleted,
}

impl Default for SessionStatus {
    fn default() -> Self {
        Self::Active
    }
}

impl SessionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Archived => "archived",
            Self::Deleted => "deleted",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "archived" => Self::Archived,
            "deleted" => Self::Deleted,
            _ => Self::Active,
        }
    }
}

/// Agent coding session state - runtime state for a session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentCodingSessionState {
    pub session_id: String,
    pub agent_status: AgentStatus,
    pub queued_commands: Option<String>, // JSON array
    pub diff_summary: Option<String>,     // JSON array
    pub updated_at: DateTime<Utc>,
}

/// Agent status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentStatus {
    Idle,
    Running,
    Waiting,
    Error,
}

impl Default for AgentStatus {
    fn default() -> Self {
        Self::Idle
    }
}

impl AgentStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Running => "running",
            Self::Waiting => "waiting",
            Self::Error => "error",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "running" => Self::Running,
            "waiting" => Self::Waiting,
            "error" => Self::Error,
            _ => Self::Idle,
        }
    }
}

/// Agent coding session message - encrypted message content.
/// The role/type is embedded in the encrypted JSON payload.
#[derive(Debug, Clone)]
pub struct AgentCodingSessionMessage {
    pub id: String,
    pub session_id: String,
    pub content_encrypted: Vec<u8>,
    pub content_nonce: Vec<u8>,
    pub timestamp: DateTime<Utc>,
    pub is_streaming: bool,
    pub sequence_number: i64,
    pub created_at: DateTime<Utc>,
    /// Raw unencrypted JSON for debugging (only populated in debug builds).
    pub debugging_decrypted_payload: Option<String>,
}

/// Message role - maps Claude event types to storage roles.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Result,
    Unknown,
}

impl MessageRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Assistant => "assistant",
            Self::System => "system",
            Self::Result => "result",
            Self::Unknown => "unknown",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "assistant" => Self::Assistant,
            "system" => Self::System,
            "result" => Self::Result,
            "user" => Self::User,
            _ => Self::Unknown,
        }
    }
}

/// Agent coding session event outbox - message delivery queue for relay sync.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentCodingSessionEventOutbox {
    pub event_id: String,
    pub session_id: String,
    pub sequence_number: i64,
    pub relay_send_batch_id: Option<String>,
    pub message_id: String,
    pub status: OutboxStatus,
    pub retry_count: i32,
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub acked_at: Option<DateTime<Utc>>,
}

/// Outbox event status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutboxStatus {
    Pending,
    Sent,
    Acked,
    Failed,
}

impl Default for OutboxStatus {
    fn default() -> Self {
        Self::Pending
    }
}

impl OutboxStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Sent => "sent",
            Self::Acked => "acked",
            Self::Failed => "failed",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "sent" => Self::Sent,
            "acked" => Self::Acked,
            "failed" => Self::Failed,
            _ => Self::Pending,
        }
    }
}

/// User settings - key-value configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSetting {
    pub key: String,
    pub value: String,
    pub value_type: String,
    pub updated_at: DateTime<Utc>,
}

/// New repository for insertion.
#[derive(Debug, Clone)]
pub struct NewRepository {
    pub id: String,
    pub path: String,
    pub name: String,
    pub is_git_repository: bool,
    pub sessions_path: Option<String>,
    pub default_branch: Option<String>,
    pub default_remote: Option<String>,
}

/// New session for insertion.
#[derive(Debug, Clone)]
pub struct NewAgentCodingSession {
    pub id: String,
    pub repository_id: String,
    pub title: String,
    pub claude_session_id: Option<String>,
    pub is_worktree: bool,
    pub worktree_path: Option<String>,
}

/// New message for insertion.
#[derive(Debug, Clone)]
pub struct NewAgentCodingSessionMessage {
    pub id: String,
    pub session_id: String,
    pub content_encrypted: Vec<u8>,
    pub content_nonce: Vec<u8>,
    pub sequence_number: i64,
    pub is_streaming: bool,
    /// Raw unencrypted JSON for debugging.
    pub debugging_decrypted_payload: Option<String>,
}

/// New outbox event for insertion.
#[derive(Debug, Clone)]
pub struct NewOutboxEvent {
    pub event_id: String,
    pub session_id: String,
    pub sequence_number: i64,
    pub message_id: String,
}

/// Session secret - encrypted session encryption key stored in SQLite.
/// The secret is encrypted with the device private key from keychain.
#[derive(Debug, Clone)]
pub struct SessionSecret {
    pub session_id: String,
    pub encrypted_secret: Vec<u8>,
    pub nonce: Vec<u8>,
    pub created_at: DateTime<Utc>,
}

/// New session secret for insertion.
#[derive(Debug, Clone)]
pub struct NewSessionSecret {
    pub session_id: String,
    pub encrypted_secret: Vec<u8>,
    pub nonce: Vec<u8>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_status_from_str() {
        assert_eq!(SessionStatus::from_str("active"), SessionStatus::Active);
        assert_eq!(SessionStatus::from_str("ACTIVE"), SessionStatus::Active);
        assert_eq!(SessionStatus::from_str("archived"), SessionStatus::Archived);
        assert_eq!(SessionStatus::from_str("ARCHIVED"), SessionStatus::Archived);
        assert_eq!(SessionStatus::from_str("deleted"), SessionStatus::Deleted);
        assert_eq!(SessionStatus::from_str("DELETED"), SessionStatus::Deleted);
        // Unknown defaults to Active
        assert_eq!(SessionStatus::from_str("unknown"), SessionStatus::Active);
        assert_eq!(SessionStatus::from_str(""), SessionStatus::Active);
    }

    #[test]
    fn test_session_status_as_str() {
        assert_eq!(SessionStatus::Active.as_str(), "active");
        assert_eq!(SessionStatus::Archived.as_str(), "archived");
        assert_eq!(SessionStatus::Deleted.as_str(), "deleted");
    }

    #[test]
    fn test_agent_status_from_str() {
        assert_eq!(AgentStatus::from_str("idle"), AgentStatus::Idle);
        assert_eq!(AgentStatus::from_str("IDLE"), AgentStatus::Idle);
        assert_eq!(AgentStatus::from_str("running"), AgentStatus::Running);
        assert_eq!(AgentStatus::from_str("RUNNING"), AgentStatus::Running);
        assert_eq!(AgentStatus::from_str("waiting"), AgentStatus::Waiting);
        assert_eq!(AgentStatus::from_str("WAITING"), AgentStatus::Waiting);
        assert_eq!(AgentStatus::from_str("error"), AgentStatus::Error);
        assert_eq!(AgentStatus::from_str("ERROR"), AgentStatus::Error);
        // Unknown defaults to Idle
        assert_eq!(AgentStatus::from_str("unknown"), AgentStatus::Idle);
        assert_eq!(AgentStatus::from_str(""), AgentStatus::Idle);
    }

    #[test]
    fn test_agent_status_as_str() {
        assert_eq!(AgentStatus::Idle.as_str(), "idle");
        assert_eq!(AgentStatus::Running.as_str(), "running");
        assert_eq!(AgentStatus::Waiting.as_str(), "waiting");
        assert_eq!(AgentStatus::Error.as_str(), "error");
    }

    #[test]
    fn test_message_role_from_str() {
        assert_eq!(MessageRole::from_str("user"), MessageRole::User);
        assert_eq!(MessageRole::from_str("USER"), MessageRole::User);
        assert_eq!(MessageRole::from_str("assistant"), MessageRole::Assistant);
        assert_eq!(MessageRole::from_str("ASSISTANT"), MessageRole::Assistant);
        assert_eq!(MessageRole::from_str("system"), MessageRole::System);
        assert_eq!(MessageRole::from_str("SYSTEM"), MessageRole::System);
        assert_eq!(MessageRole::from_str("result"), MessageRole::Result);
        assert_eq!(MessageRole::from_str("RESULT"), MessageRole::Result);
        // Unknown types map to Unknown
        assert_eq!(MessageRole::from_str("other"), MessageRole::Unknown);
        assert_eq!(MessageRole::from_str(""), MessageRole::Unknown);
    }

    #[test]
    fn test_message_role_as_str() {
        assert_eq!(MessageRole::User.as_str(), "user");
        assert_eq!(MessageRole::Assistant.as_str(), "assistant");
        assert_eq!(MessageRole::System.as_str(), "system");
        assert_eq!(MessageRole::Result.as_str(), "result");
        assert_eq!(MessageRole::Unknown.as_str(), "unknown");
    }

    #[test]
    fn test_outbox_status_from_str() {
        assert_eq!(OutboxStatus::from_str("pending"), OutboxStatus::Pending);
        assert_eq!(OutboxStatus::from_str("PENDING"), OutboxStatus::Pending);
        assert_eq!(OutboxStatus::from_str("sent"), OutboxStatus::Sent);
        assert_eq!(OutboxStatus::from_str("SENT"), OutboxStatus::Sent);
        assert_eq!(OutboxStatus::from_str("acked"), OutboxStatus::Acked);
        assert_eq!(OutboxStatus::from_str("ACKED"), OutboxStatus::Acked);
        assert_eq!(OutboxStatus::from_str("failed"), OutboxStatus::Failed);
        assert_eq!(OutboxStatus::from_str("FAILED"), OutboxStatus::Failed);
        // Unknown defaults to Pending
        assert_eq!(OutboxStatus::from_str("unknown"), OutboxStatus::Pending);
        assert_eq!(OutboxStatus::from_str(""), OutboxStatus::Pending);
    }

    #[test]
    fn test_outbox_status_as_str() {
        assert_eq!(OutboxStatus::Pending.as_str(), "pending");
        assert_eq!(OutboxStatus::Sent.as_str(), "sent");
        assert_eq!(OutboxStatus::Acked.as_str(), "acked");
        assert_eq!(OutboxStatus::Failed.as_str(), "failed");
    }

    #[test]
    fn test_session_status_default() {
        assert_eq!(SessionStatus::default(), SessionStatus::Active);
    }

    #[test]
    fn test_agent_status_default() {
        assert_eq!(AgentStatus::default(), AgentStatus::Idle);
    }

    #[test]
    fn test_outbox_status_default() {
        assert_eq!(OutboxStatus::default(), OutboxStatus::Pending);
    }
}
