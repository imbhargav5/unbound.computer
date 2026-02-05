//! Core types for the Armin session engine.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Unique identifier for a session (UUID string).
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SessionId(pub String);

impl SessionId {
    /// Creates a new random session ID using UUID v4.
    ///
    /// Generates a cryptographically random UUID and converts it to a string
    /// representation for use as a unique session identifier.
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    /// Creates a session ID from an existing string value.
    ///
    /// Accepts any type that can be converted into a String, allowing
    /// flexibility when constructing IDs from various string sources.
    pub fn from_string(s: impl Into<String>) -> Self {
        Self(s.into())
    }

    /// Returns the session ID as a string slice reference.
    ///
    /// Provides a borrowed view of the underlying string without allocation,
    /// useful for comparisons and passing to APIs that accept string slices.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for SessionId {
    /// Returns a new random SessionId as the default value.
    ///
    /// Delegates to `SessionId::new()` to generate a unique UUID-based identifier.
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for SessionId {
    /// Formats the session ID for display by writing its underlying string value.
    ///
    /// Enables using SessionId with format macros like `format!()` and `println!()`.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for SessionId {
    /// Converts an owned String into a SessionId.
    ///
    /// Wraps the String directly without additional allocation.
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for SessionId {
    /// Converts a string slice into a SessionId.
    ///
    /// Clones the string slice into an owned String for the SessionId.
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// Unique identifier for a message (UUID string).
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct MessageId(pub String);

impl MessageId {
    /// Creates a new random message ID using UUID v4.
    ///
    /// Generates a cryptographically random UUID and converts it to a string
    /// representation for use as a unique message identifier within a session.
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    /// Creates a message ID from an existing string value.
    ///
    /// Accepts any type that can be converted into a String, allowing
    /// flexibility when constructing IDs from database results or external sources.
    pub fn from_string(s: impl Into<String>) -> Self {
        Self(s.into())
    }

    /// Returns the message ID as a string slice reference.
    ///
    /// Provides a borrowed view of the underlying string without allocation,
    /// useful for database queries and API calls.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for MessageId {
    /// Returns a new random MessageId as the default value.
    ///
    /// Delegates to `MessageId::new()` to generate a unique UUID-based identifier.
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for MessageId {
    /// Formats the message ID for display by writing its underlying string value.
    ///
    /// Enables using MessageId with format macros like `format!()` and `println!()`.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for MessageId {
    /// Converts an owned String into a MessageId.
    ///
    /// Wraps the String directly without additional allocation.
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for MessageId {
    /// Converts a string slice into a MessageId.
    ///
    /// Clones the string slice into an owned String for the MessageId.
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// A message in a session.
///
/// Messages store raw content (typically JSON from Claude events).
/// No role interpretation is done - content is stored as-is.
#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub id: MessageId,
    pub content: String,
    pub sequence_number: i64,
}

impl Message {
    /// Creates a new message payload for insertion into a session.
    ///
    /// Returns a `NewMessage` struct containing only the content. The ID and
    /// sequence number are assigned atomically by Armin during the actual insertion.
    pub fn new(content: impl Into<String>) -> NewMessage {
        NewMessage {
            content: content.into(),
        }
    }
}

/// A message to be inserted.
///
/// The sequence number is assigned atomically by Armin during insertion.
/// Callers must NOT provide a sequence number - Armin owns all sequencing.
#[derive(Clone, Debug)]
pub struct NewMessage {
    pub content: String,
}

// ============================================================================
// Repository types
// ============================================================================

/// Unique identifier for a repository (UUID string).
#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct RepositoryId(pub String);

impl RepositoryId {
    /// Creates a new random repository ID using UUID v4.
    ///
    /// Generates a cryptographically random UUID and converts it to a string
    /// representation for use as a unique repository identifier.
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    /// Creates a repository ID from an existing string value.
    ///
    /// Accepts any type that can be converted into a String, allowing
    /// flexibility when constructing IDs from database results or file paths.
    pub fn from_string(s: impl Into<String>) -> Self {
        Self(s.into())
    }

    /// Returns the repository ID as a string slice reference.
    ///
    /// Provides a borrowed view of the underlying string without allocation,
    /// useful for database queries and file system operations.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for RepositoryId {
    /// Returns a new random RepositoryId as the default value.
    ///
    /// Delegates to `RepositoryId::new()` to generate a unique UUID-based identifier.
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for RepositoryId {
    /// Formats the repository ID for display by writing its underlying string value.
    ///
    /// Enables using RepositoryId with format macros like `format!()` and `println!()`.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for RepositoryId {
    /// Converts an owned String into a RepositoryId.
    ///
    /// Wraps the String directly without additional allocation.
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for RepositoryId {
    /// Converts a string slice into a RepositoryId.
    ///
    /// Clones the string slice into an owned String for the RepositoryId.
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// A registered git repository.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Repository {
    pub id: RepositoryId,
    pub path: String,
    pub name: String,
    pub is_git_repository: bool,
    pub sessions_path: Option<String>,
    pub default_branch: Option<String>,
    pub default_remote: Option<String>,
    pub last_accessed_at: DateTime<Utc>,
    pub added_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A new repository to be inserted.
#[derive(Debug, Clone)]
pub struct NewRepository {
    pub id: RepositoryId,
    pub path: String,
    pub name: String,
    pub is_git_repository: bool,
    pub sessions_path: Option<String>,
    pub default_branch: Option<String>,
    pub default_remote: Option<String>,
}

impl NewRepository {
    /// Creates a new repository instance with an auto-generated UUID.
    ///
    /// Initializes a repository with the provided path, name, and git status.
    /// Optional fields (sessions_path, default_branch, default_remote) are set to None
    /// and can be configured separately after creation.
    pub fn new(path: impl Into<String>, name: impl Into<String>, is_git_repository: bool) -> Self {
        Self {
            id: RepositoryId::new(),
            path: path.into(),
            name: name.into(),
            is_git_repository,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        }
    }
}

// ============================================================================
// Session types (extended with full metadata)
// ============================================================================

/// Session status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    #[default]
    Active,
    Archived,
    Deleted,
}

impl SessionStatus {
    /// Converts the session status to its string representation.
    ///
    /// Returns a static string slice matching the database/API representation
    /// of each status variant (lowercase).
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Archived => "archived",
            Self::Deleted => "deleted",
        }
    }

    /// Parses a string into a SessionStatus variant.
    ///
    /// Performs case-insensitive matching. Returns `Active` as the default
    /// for any unrecognized string values (fail-safe behavior).
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "archived" => Self::Archived,
            "deleted" => Self::Deleted,
            _ => Self::Active,
        }
    }
}

/// A full agent coding session with all metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: SessionId,
    pub repository_id: RepositoryId,
    pub title: String,
    pub claude_session_id: Option<String>,
    pub status: SessionStatus,
    pub is_worktree: bool,
    pub worktree_path: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_accessed_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A new session to be inserted.
#[derive(Debug, Clone)]
pub struct NewSession {
    pub id: SessionId,
    pub repository_id: RepositoryId,
    pub title: String,
    pub claude_session_id: Option<String>,
    pub is_worktree: bool,
    pub worktree_path: Option<String>,
}

impl NewSession {
    /// Creates a new session instance with an auto-generated UUID.
    ///
    /// Initializes a standard (non-worktree) session associated with the given
    /// repository. The session starts without a Claude session ID, which can
    /// be set later when the Claude CLI process is spawned.
    pub fn new(repository_id: impl Into<RepositoryId>, title: impl Into<String>) -> Self {
        Self {
            id: SessionId::new(),
            repository_id: repository_id.into(),
            title: title.into(),
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        }
    }

    /// Creates a new worktree session with an auto-generated UUID.
    ///
    /// Worktree sessions operate in a separate git worktree directory,
    /// allowing isolated work without affecting the main repository state.
    /// The worktree_path specifies the filesystem location of the worktree.
    pub fn new_worktree(
        repository_id: impl Into<RepositoryId>,
        title: impl Into<String>,
        worktree_path: impl Into<String>,
    ) -> Self {
        Self {
            id: SessionId::new(),
            repository_id: repository_id.into(),
            title: title.into(),
            claude_session_id: None,
            is_worktree: true,
            worktree_path: Some(worktree_path.into()),
        }
    }
}

/// Session update fields.
#[derive(Debug, Clone, Default)]
pub struct SessionUpdate {
    pub title: Option<String>,
    pub claude_session_id: Option<String>,
    pub status: Option<SessionStatus>,
    pub last_accessed_at: Option<DateTime<Utc>>,
}

// ============================================================================
// Session state types
// ============================================================================

/// Agent status for a session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum AgentStatus {
    #[default]
    Idle,
    Running,
    Waiting,
    Error,
}

impl AgentStatus {
    /// Converts the agent status to its string representation.
    ///
    /// Returns a static string slice matching the database/API representation
    /// of each status variant (lowercase).
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Running => "running",
            Self::Waiting => "waiting",
            Self::Error => "error",
        }
    }

    /// Parses a string into an AgentStatus variant.
    ///
    /// Performs case-insensitive matching. Returns `Idle` as the default
    /// for any unrecognized string values (fail-safe behavior).
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "running" => Self::Running,
            "waiting" => Self::Waiting,
            "error" => Self::Error,
            _ => Self::Idle,
        }
    }
}

/// Runtime state for a session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionState {
    pub session_id: SessionId,
    pub agent_status: AgentStatus,
    pub queued_commands: Option<String>,
    pub diff_summary: Option<String>,
    pub updated_at: DateTime<Utc>,
}

// ============================================================================
// Session secret types
// ============================================================================

/// An encrypted session secret stored in SQLite.
#[derive(Debug, Clone)]
pub struct SessionSecret {
    pub session_id: SessionId,
    pub encrypted_secret: Vec<u8>,
    pub nonce: Vec<u8>,
    pub created_at: DateTime<Utc>,
}

/// A new session secret to be inserted.
#[derive(Debug, Clone)]
pub struct NewSessionSecret {
    pub session_id: SessionId,
    pub encrypted_secret: Vec<u8>,
    pub nonce: Vec<u8>,
}

// ============================================================================
// Outbox types
// ============================================================================

/// Outbox event status.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum OutboxStatus {
    #[default]
    Pending,
    Sent,
    Acked,
    Failed,
}

impl OutboxStatus {
    /// Converts the outbox status to its string representation.
    ///
    /// Returns a static string slice matching the database representation
    /// of each status variant (lowercase).
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Sent => "sent",
            Self::Acked => "acked",
            Self::Failed => "failed",
        }
    }

    /// Parses a string into an OutboxStatus variant.
    ///
    /// Performs case-insensitive matching. Returns `Pending` as the default
    /// for any unrecognized string values (fail-safe behavior for retry logic).
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "sent" => Self::Sent,
            "acked" => Self::Acked,
            "failed" => Self::Failed,
            _ => Self::Pending,
        }
    }
}

/// An outbox event for relay sync.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    pub event_id: String,
    pub session_id: SessionId,
    pub sequence_number: i64,
    pub relay_send_batch_id: Option<String>,
    pub message_id: MessageId,
    pub status: OutboxStatus,
    pub retry_count: i32,
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub acked_at: Option<DateTime<Utc>>,
}

/// A new outbox event to be inserted.
#[derive(Debug, Clone)]
pub struct NewOutboxEvent {
    pub event_id: String,
    pub session_id: SessionId,
    pub sequence_number: i64,
    pub message_id: MessageId,
}

impl NewOutboxEvent {
    /// Creates a new outbox event with an auto-generated UUID.
    ///
    /// Constructs an outbox entry linking a message to its session with a
    /// sequence number for ordering. The event_id is generated automatically
    /// to ensure uniqueness for relay sync tracking.
    pub fn new(session_id: impl Into<SessionId>, sequence_number: i64, message_id: impl Into<MessageId>) -> Self {
        Self {
            event_id: Uuid::new_v4().to_string(),
            session_id: session_id.into(),
            sequence_number,
            message_id: message_id.into(),
        }
    }
}

/// Supabase message outbox entry for sync tracking.
#[derive(Debug, Clone)]
pub struct SupabaseMessageOutboxEntry {
    pub message_id: MessageId,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub last_attempt_at: Option<DateTime<Utc>>,
    pub retry_count: i32,
    pub last_error: Option<String>,
}

/// Pending Supabase message payload for sync.
#[derive(Debug, Clone)]
pub struct PendingSupabaseMessage {
    pub message_id: MessageId,
    pub session_id: SessionId,
    pub sequence_number: i64,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub last_attempt_at: Option<DateTime<Utc>>,
    pub retry_count: i32,
    pub last_error: Option<String>,
}

// ============================================================================
// Supabase sync state types (cursor-based sync per session)
// ============================================================================

/// Supabase sync state for a session (cursor-based sync tracking).
///
/// Tracks the last synced sequence number per session, replacing
/// the per-message outbox approach with a more efficient cursor-based model.
#[derive(Debug, Clone)]
pub struct SupabaseSyncState {
    pub session_id: SessionId,
    pub last_synced_sequence_number: i64,
    pub last_sync_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
    pub retry_count: i32,
    pub last_attempt_at: Option<DateTime<Utc>>,
}

/// A message pending sync to Supabase (derived from sync state cursor).
#[derive(Debug, Clone)]
pub struct PendingSyncMessage {
    pub session_id: SessionId,
    pub message_id: MessageId,
    pub sequence_number: i64,
    pub content: String,
}

/// Sessions with pending messages to sync, along with their sync state.
#[derive(Debug, Clone)]
pub struct SessionPendingSync {
    pub session_id: SessionId,
    pub last_synced_sequence_number: i64,
    pub retry_count: i32,
    pub last_attempt_at: Option<DateTime<Utc>>,
    pub messages: Vec<PendingSyncMessage>,
}

// ============================================================================
// User settings types
// ============================================================================

/// A user setting (key-value configuration).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSetting {
    pub key: String,
    pub value: String,
    pub value_type: String,
    pub updated_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_id_equality() {
        let id1 = SessionId::from_string("test-session-1");
        let id2 = SessionId::from_string("test-session-1");
        let id3 = SessionId::from_string("test-session-2");
        assert_eq!(id1, id2);
        assert_ne!(id1, id3);
    }

    #[test]
    fn message_id_equality() {
        let id1 = MessageId::from_string("test-message-1");
        let id2 = MessageId::from_string("test-message-1");
        let id3 = MessageId::from_string("test-message-2");
        assert_eq!(id1, id2);
        assert_ne!(id1, id3);
    }

    #[test]
    fn session_id_new_is_unique() {
        let id1 = SessionId::new();
        let id2 = SessionId::new();
        assert_ne!(id1, id2);
    }

    #[test]
    fn message_id_new_is_unique() {
        let id1 = MessageId::new();
        let id2 = MessageId::new();
        assert_ne!(id1, id2);
    }

    #[test]
    fn session_id_display() {
        let id = SessionId::from_string("my-session");
        assert_eq!(format!("{}", id), "my-session");
    }

    #[test]
    fn session_id_from_string() {
        let id: SessionId = "test".into();
        assert_eq!(id.as_str(), "test");
    }
}
