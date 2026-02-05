//! Toshinori SideEffectSink implementation.
//!
//! This module provides the main `SideEffectSink` that syncs Armin's
//! side-effects to Supabase for cross-device visibility.

use crate::client::SupabaseClient;
use armin::{SideEffect, SideEffectSink};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

/// Authentication and identity context required for Supabase sync operations.
///
/// Contains the credentials and identifiers needed to attribute synced data
/// to the correct user and device.
#[derive(Clone)]
pub struct SyncContext {
    /// JWT access token for Supabase API authentication.
    pub access_token: String,
    /// User ID for ownership tracking in multi-user scenarios.
    pub user_id: String,
    /// Device ID identifying this daemon instance for multi-device sync.
    pub device_id: String,
}

/// Additional metadata required to sync a session to Supabase.
///
/// Contains repository and git-related information that isn't available
/// in the core SideEffect but is needed for the Supabase schema.
#[derive(Clone, Debug)]
pub struct SessionMetadata {
    /// The repository this session belongs to.
    pub repository_id: String,
    /// The git branch being worked on (if applicable).
    pub current_branch: Option<String>,
    /// The working directory path within the repository.
    pub working_directory: Option<String>,
    /// Whether this session operates in a git worktree.
    pub is_worktree: bool,
    /// The worktree path if is_worktree is true.
    pub worktree_path: Option<String>,
}

/// Trait for providing session metadata required by Supabase sync.
///
/// Implementors (typically the daemon's state manager) provide access to
/// session metadata that isn't included in the core SideEffect payloads.
pub trait SessionMetadataProvider: Send + Sync {
    /// Retrieves metadata for a session by its ID.
    ///
    /// Returns None if the session doesn't exist or metadata is unavailable.
    fn get_session_metadata(&self, session_id: &str) -> Option<SessionMetadata>;
}

/// Represents a message that needs to be synced to Supabase.
///
/// Encapsulates all the information needed to enqueue a message for
/// async sync processing by the message syncer component.
#[derive(Clone, Debug)]
pub struct MessageSyncRequest {
    /// The session this message belongs to.
    pub session_id: String,
    /// Unique identifier for this message.
    pub message_id: String,
    /// The message's position in the session sequence.
    pub sequence_number: i64,
    /// The raw message content to be encrypted and synced.
    pub content: String,
}

/// Trait for async message sync processing.
///
/// Implementors (e.g., Levi) handle the actual encryption and upload
/// of messages to Supabase, potentially with batching and retry logic.
pub trait MessageSyncer: Send + Sync {
    /// Enqueues a message for async sync to Supabase.
    ///
    /// The implementation should handle encryption, batching, and retries.
    fn enqueue(&self, request: MessageSyncRequest);
}

/// Toshinori: A SideEffectSink that syncs to Supabase.
///
/// When Armin commits facts to SQLite, Toshinori asynchronously syncs
/// those changes to Supabase for cross-device visibility.
///
/// # Thread Safety
///
/// Toshinori is thread-safe and can be shared across tasks. The sync
/// context can be updated at runtime (e.g., after token refresh).
pub struct ToshinoriSink {
    /// Supabase API client.
    client: SupabaseClient,
    /// Sync context (token, user_id, device_id).
    context: Arc<RwLock<Option<SyncContext>>>,
    /// Optional metadata provider for session upserts.
    metadata_provider: Arc<RwLock<Option<Arc<dyn SessionMetadataProvider>>>>,
    /// Optional message syncer for Supabase message writes.
    message_syncer: Arc<RwLock<Option<Arc<dyn MessageSyncer>>>>,
    /// Tokio runtime handle for spawning async tasks.
    runtime: tokio::runtime::Handle,
}

impl ToshinoriSink {
    /// Create a new Toshinori sink.
    ///
    /// # Arguments
    /// * `api_url` - Supabase API URL
    /// * `anon_key` - Supabase anonymous key
    /// * `runtime` - Tokio runtime handle for async operations
    pub fn new(
        api_url: impl Into<String>,
        anon_key: impl Into<String>,
        runtime: tokio::runtime::Handle,
    ) -> Self {
        Self {
            client: SupabaseClient::new(api_url, anon_key),
            context: Arc::new(RwLock::new(None)),
            metadata_provider: Arc::new(RwLock::new(None)),
            message_syncer: Arc::new(RwLock::new(None)),
            runtime,
        }
    }

    /// Configures the sync context with authentication credentials.
    ///
    /// Must be called after user authentication before side-effects will be
    /// synced. Until this is called, side-effects are logged but not sent.
    pub async fn set_context(&self, context: SyncContext) {
        let mut ctx = self.context.write().await;
        *ctx = Some(context);
        info!("Toshinori sync context set");
    }

    /// Removes the sync context, disabling Supabase sync.
    ///
    /// Call this on user logout to stop syncing and clear credentials.
    /// Pending syncs in flight may still complete.
    pub async fn clear_context(&self) {
        let mut ctx = self.context.write().await;
        *ctx = None;
        info!("Toshinori sync context cleared");
    }

    /// Registers a provider for session metadata lookups.
    ///
    /// Required for SessionCreated and SessionUpdated side-effects to
    /// include full metadata in Supabase sync.
    pub async fn set_metadata_provider(&self, provider: Arc<dyn SessionMetadataProvider>) {
        let mut guard = self.metadata_provider.write().await;
        *guard = Some(provider);
    }

    /// Removes the metadata provider reference.
    ///
    /// After calling, session syncs will be skipped with a warning.
    pub async fn clear_metadata_provider(&self) {
        let mut guard = self.metadata_provider.write().await;
        *guard = None;
    }

    /// Registers a message syncer for handling MessageAppended side-effects.
    ///
    /// The syncer (e.g., Levi) handles encryption, batching, and upload
    /// of messages to Supabase asynchronously.
    pub async fn set_message_syncer(&self, syncer: Arc<dyn MessageSyncer>) {
        let mut guard = self.message_syncer.write().await;
        *guard = Some(syncer);
    }

    /// Removes the message syncer reference.
    ///
    /// After calling, message appends will be logged but not synced.
    pub async fn clear_message_syncer(&self) {
        let mut guard = self.message_syncer.write().await;
        *guard = None;
    }

    /// Checks if Supabase sync is currently enabled.
    ///
    /// Returns true if a sync context has been set (user is authenticated).
    pub async fn is_enabled(&self) -> bool {
        self.context.read().await.is_some()
    }

    /// Spawns an async task to process a side-effect.
    ///
    /// Clones necessary references and spawns on the Tokio runtime to avoid
    /// blocking the synchronous emit() call. Handles each effect type with
    /// appropriate Supabase operations and logs errors without failing.
    fn handle_effect(&self, effect: SideEffect) {
        // Clone Arc references for the spawned task
        let client = self.client.clone();
        let context = self.context.clone();
        let metadata_provider = self.metadata_provider.clone();
        let message_syncer = self.message_syncer.clone();

        self.runtime.spawn(async move {
            // Early exit if no sync context is configured
            let ctx = {
                let guard = context.read().await;
                match guard.as_ref() {
                    Some(ctx) => ctx.clone(),
                    None => {
                        debug!(?effect, "Toshinori: skipping sync (no context)");
                        return;
                    }
                }
            };

            // Dispatch to appropriate handler based on effect type
            let result = match &effect {
                SideEffect::RepositoryCreated { repository_id } => {
                    warn!(
                        repository_id = repository_id.as_str(),
                        "Repository sync skipped (missing metadata: name/local_path)"
                    );
                    Ok(())
                }

                SideEffect::RepositoryDeleted { repository_id } => {
                    client
                        .delete_repository(repository_id.as_str(), &ctx.access_token)
                        .await
                }

                SideEffect::SessionCreated { session_id } => {
                    let metadata = {
                        let guard = metadata_provider.read().await;
                        guard
                            .as_ref()
                            .and_then(|provider| provider.get_session_metadata(session_id.as_str()))
                    };

                    if let Some(metadata) = metadata {
                        client
                            .upsert_session(
                                session_id.as_str(),
                                &ctx.user_id,
                                &ctx.device_id,
                                &metadata.repository_id,
                                "active",
                                metadata.current_branch.as_deref(),
                                metadata.working_directory.as_deref(),
                                metadata.is_worktree,
                                metadata.worktree_path.as_deref(),
                                &ctx.access_token,
                            )
                            .await
                    } else {
                        warn!(
                            session_id = session_id.as_str(),
                            "Session sync skipped (missing metadata provider or metadata)"
                        );
                        Ok(())
                    }
                }

                SideEffect::SessionClosed { session_id } => {
                    client
                        .update_session_status(session_id.as_str(), "ended", &ctx.access_token)
                        .await
                }

                SideEffect::SessionDeleted { session_id } => {
                    client
                        .delete_session(session_id.as_str(), &ctx.access_token)
                        .await
                }

                SideEffect::SessionUpdated { session_id } => {
                    let metadata = {
                        let guard = metadata_provider.read().await;
                        guard
                            .as_ref()
                            .and_then(|provider| provider.get_session_metadata(session_id.as_str()))
                    };

                    if let Some(metadata) = metadata {
                        client
                            .upsert_session(
                                session_id.as_str(),
                                &ctx.user_id,
                                &ctx.device_id,
                                &metadata.repository_id,
                                "active",
                                metadata.current_branch.as_deref(),
                                metadata.working_directory.as_deref(),
                                metadata.is_worktree,
                                metadata.worktree_path.as_deref(),
                                &ctx.access_token,
                            )
                            .await
                    } else {
                        warn!(
                            session_id = session_id.as_str(),
                            "Session update skipped (missing metadata provider or metadata)"
                        );
                        Ok(())
                    }
                }

                SideEffect::MessageAppended {
                    session_id,
                    message_id,
                    sequence_number,
                    content,
                } => {
                    let syncer = {
                        let guard = message_syncer.read().await;
                        guard.as_ref().cloned()
                    };

                    if let Some(syncer) = syncer {
                        syncer.enqueue(MessageSyncRequest {
                            session_id: session_id.as_str().to_string(),
                            message_id: message_id.as_str().to_string(),
                            sequence_number: *sequence_number,
                            content: content.clone(),
                        });
                        Ok(())
                    } else {
                        debug!(
                            session_id = session_id.as_str(),
                            message_id = message_id.as_str(),
                            "Toshinori: MessageAppended (no message syncer)"
                        );
                        Ok(())
                    }
                }

                SideEffect::AgentStatusChanged { session_id, status } => {
                    warn!(
                        session_id = session_id.as_str(),
                        status = status.as_str(),
                        "Agent status sync skipped (no agent_status column in Supabase schema)"
                    );
                    Ok(())
                }

                SideEffect::OutboxEventsSent { batch_id } => {
                    debug!(batch_id, "Toshinori: OutboxEventsSent (no sync needed)");
                    Ok(())
                }

                SideEffect::OutboxEventsAcked { batch_id } => {
                    debug!(batch_id, "Toshinori: OutboxEventsAcked (no sync needed)");
                    Ok(())
                }
            };

            // Log errors but don't fail
            if let Err(e) = result {
                error!(?effect, error = %e, "Toshinori: failed to sync side-effect");
            }
        });
    }
}

impl std::fmt::Debug for ToshinoriSink {
    /// Provides minimal debug output without exposing internal state.
    ///
    /// Uses finish_non_exhaustive to indicate internal fields are omitted
    /// for security (credentials) and brevity.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ToshinoriSink").finish_non_exhaustive()
    }
}

impl SideEffectSink for ToshinoriSink {
    /// Receives a side-effect from Armin and queues it for async sync.
    ///
    /// Logs the effect for debugging and delegates to handle_effect() which
    /// spawns an async task. This method returns immediately without waiting
    /// for the sync to complete (fire-and-forget).
    fn emit(&self, effect: SideEffect) {
        debug!(?effect, "Toshinori: received side-effect");
        self.handle_effect(effect);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use armin::types::SessionId;

    #[tokio::test]
    async fn test_sink_without_context() {
        let runtime = tokio::runtime::Handle::current();
        let sink = ToshinoriSink::new("https://test.supabase.co", "test-key", runtime);

        // Should not be enabled without context
        assert!(!sink.is_enabled().await);

        // Emitting should not panic (just logs)
        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("test-session"),
        });
    }

    #[tokio::test]
    async fn test_context_management() {
        let runtime = tokio::runtime::Handle::current();
        let sink = ToshinoriSink::new("https://test.supabase.co", "test-key", runtime);

        assert!(!sink.is_enabled().await);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-123".to_string(),
            device_id: "device-456".to_string(),
        })
        .await;

        assert!(sink.is_enabled().await);

        sink.clear_context().await;

        assert!(!sink.is_enabled().await);
    }
}
