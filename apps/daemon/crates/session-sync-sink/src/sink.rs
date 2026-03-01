//! Session sync SideEffectSink implementation.
//!
//! This module provides the main `SideEffectSink` that syncs Armin's
//! side-effects to Supabase and dispatches hot-path message sync notifications.

use crate::client::SupabaseClient;
use agent_session_sqlite_persist_core::{RuntimeStatusEnvelope, SideEffect, SideEffectSink};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, RwLock};
use tokio::time::{interval, Duration};
use tracing::{debug, error, info, warn};

/// Buffer size for queued runtime status updates.
const RUNTIME_STATUS_QUEUE_CAPACITY: usize = 256;
/// Flush cadence for runtime status coalescing worker.
const RUNTIME_STATUS_FLUSH_INTERVAL: Duration = Duration::from_millis(120);

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
    /// Human-readable session title (for cross-device rename sync).
    pub title: Option<String>,
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

/// Represents a message that needs to be synced by a downstream worker.
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
/// Implementors (e.g., MessageSyncWorker/Ably workers) handle encryption and delivery
/// with their own batching/retry strategies.
pub trait MessageSyncer: Send + Sync {
    /// Enqueues a message for async sync.
    ///
    /// The implementation should handle encryption, batching, and retries.
    fn enqueue(&self, request: MessageSyncRequest);
}

/// Represents a runtime status envelope update that needs fanout.
///
/// The same request is fanned out to:
/// - Hot path: optional realtime status syncer (LiveObjects transport)
/// - Cold path: Supabase runtime_status JSON mirror
#[derive(Clone, Debug)]
pub struct RuntimeStatusSyncRequest {
    /// Session identifier for routing and LWW coalescing.
    pub session_id: String,
    /// Canonical runtime status envelope payload.
    pub runtime_status: RuntimeStatusEnvelope,
}

/// Trait for async runtime status fanout processing.
pub trait RuntimeStatusSyncer: Send + Sync {
    /// Enqueues a runtime status update for realtime publish.
    fn enqueue(&self, request: RuntimeStatusSyncRequest);
}

/// Session sync: A SideEffectSink that syncs to Supabase.
///
/// When Armin commits facts to SQLite, Session sync asynchronously syncs
/// those changes to Supabase for cross-device visibility.
///
/// # Thread Safety
///
/// Session sync is thread-safe and can be shared across tasks. The sync
/// context can be updated at runtime (e.g., after token refresh).
pub struct SessionSyncSink {
    /// Supabase API client.
    client: SupabaseClient,
    /// Sync context (token, user_id, device_id).
    context: Arc<RwLock<Option<SyncContext>>>,
    /// Optional metadata provider for session upserts.
    metadata_provider: Arc<RwLock<Option<Arc<dyn SessionMetadataProvider>>>>,
    /// Optional message syncer for Supabase message writes.
    message_syncer: Arc<RwLock<Option<Arc<dyn MessageSyncer>>>>,
    /// Optional realtime message syncer for Ably hot-path publish.
    realtime_message_syncer: Arc<RwLock<Option<Arc<dyn MessageSyncer>>>>,
    /// Optional realtime runtime-status syncer for LiveObjects hot-path publish.
    realtime_runtime_status_syncer: Arc<RwLock<Option<Arc<dyn RuntimeStatusSyncer>>>>,
    /// Runtime-status queue sender.
    runtime_status_sender: mpsc::Sender<RuntimeStatusSyncRequest>,
    /// Runtime-status queue receiver, consumed exactly once by worker startup.
    runtime_status_receiver: Mutex<Option<mpsc::Receiver<RuntimeStatusSyncRequest>>>,
    /// Tokio runtime handle for spawning async tasks.
    runtime: tokio::runtime::Handle,
}

impl SessionSyncSink {
    /// Create a new Session sync sink.
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
        let (runtime_status_sender, runtime_status_receiver) =
            mpsc::channel(RUNTIME_STATUS_QUEUE_CAPACITY);
        let sink = Self {
            client: SupabaseClient::new(api_url, anon_key),
            context: Arc::new(RwLock::new(None)),
            metadata_provider: Arc::new(RwLock::new(None)),
            message_syncer: Arc::new(RwLock::new(None)),
            realtime_message_syncer: Arc::new(RwLock::new(None)),
            realtime_runtime_status_syncer: Arc::new(RwLock::new(None)),
            runtime_status_sender,
            runtime_status_receiver: Mutex::new(Some(runtime_status_receiver)),
            runtime: runtime.clone(),
        };
        sink.start_runtime_status_worker();
        sink
    }

    /// Configures the sync context with authentication credentials.
    ///
    /// Must be called after user authentication before side-effects will be
    /// synced. Until this is called, side-effects are logged but not sent.
    pub async fn set_context(&self, context: SyncContext) {
        let mut ctx = self.context.write().await;
        *ctx = Some(context);
        info!("Session sync sync context set");
    }

    /// Removes the sync context, disabling Supabase sync.
    ///
    /// Call this on user logout to stop syncing and clear credentials.
    /// Pending syncs in flight may still complete.
    pub async fn clear_context(&self) {
        let mut ctx = self.context.write().await;
        *ctx = None;
        info!("Session sync sync context cleared");
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
    /// The syncer (e.g., MessageSyncWorker) handles encryption, batching, and upload
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

    /// Registers a realtime message syncer for hot-path publish (e.g., Ably).
    pub async fn set_realtime_message_syncer(&self, syncer: Arc<dyn MessageSyncer>) {
        let mut guard = self.realtime_message_syncer.write().await;
        *guard = Some(syncer);
    }

    /// Removes the realtime message syncer reference.
    pub async fn clear_realtime_message_syncer(&self) {
        let mut guard = self.realtime_message_syncer.write().await;
        *guard = None;
    }

    /// Registers a realtime runtime-status syncer for hot-path publish.
    pub async fn set_realtime_runtime_status_syncer(&self, syncer: Arc<dyn RuntimeStatusSyncer>) {
        let mut guard = self.realtime_runtime_status_syncer.write().await;
        *guard = Some(syncer);
    }

    /// Removes the realtime runtime-status syncer reference.
    pub async fn clear_realtime_runtime_status_syncer(&self) {
        let mut guard = self.realtime_runtime_status_syncer.write().await;
        *guard = None;
    }

    /// Checks if Supabase sync is currently enabled.
    ///
    /// Returns true if a sync context has been set (user is authenticated).
    pub async fn is_enabled(&self) -> bool {
        self.context.read().await.is_some()
    }

    fn enqueue_runtime_status_update(&self, request: RuntimeStatusSyncRequest) {
        match self.runtime_status_sender.try_send(request.clone()) {
            Ok(()) => {}
            Err(tokio::sync::mpsc::error::TrySendError::Full(request)) => {
                let sender = self.runtime_status_sender.clone();
                self.runtime.spawn(async move {
                    if let Err(err) = sender.send(request).await {
                        warn!(error = %err, "Session sync runtime-status enqueue failed (channel closed)");
                    }
                });
            }
            Err(tokio::sync::mpsc::error::TrySendError::Closed(_)) => {
                warn!("Session sync runtime-status worker channel is closed");
            }
        }
    }

    fn start_runtime_status_worker(&self) {
        let Some(mut receiver) = self
            .runtime_status_receiver
            .lock()
            .expect("lock poisoned")
            .take()
        else {
            panic!("Session sync runtime-status worker already started");
        };

        let client = self.client.clone();
        let context = self.context.clone();
        let realtime_runtime_status_syncer = self.realtime_runtime_status_syncer.clone();

        self.runtime.spawn(async move {
            let mut ticker = interval(RUNTIME_STATUS_FLUSH_INTERVAL);
            let mut pending: HashMap<String, RuntimeStatusSyncRequest> = HashMap::new();
            let mut last_synced_by_session: HashMap<String, i64> = HashMap::new();
            let mut last_hot_path_by_session: HashMap<String, i64> = HashMap::new();

            loop {
                tokio::select! {
                    maybe_request = receiver.recv() => {
                        match maybe_request {
                            Some(request) => {
                                coalesce_runtime_status_request(
                                    &mut pending,
                                    &last_synced_by_session,
                                    request,
                                );
                            }
                            None => {
                                debug!("Session sync runtime-status worker stopped (channel closed)");
                                break;
                            }
                        }
                    }
                    _ = ticker.tick() => {
                        if pending.is_empty() {
                            continue;
                        }

                        let ctx = {
                            let guard = context.read().await;
                            guard.clone()
                        };
                        let Some(ctx) = ctx else {
                            debug!(
                                queued = pending.len(),
                                "Session sync runtime-status worker dropped queued updates (no context)"
                            );
                            pending.clear();
                            continue;
                        };

                        let realtime_syncer = {
                            let guard = realtime_runtime_status_syncer.read().await;
                            guard.as_ref().cloned()
                        };

                        let batch = std::mem::take(&mut pending);
                        for request in batch.into_values() {
                            if let Some(last_synced) = last_synced_by_session.get(&request.session_id)
                            {
                                if request.runtime_status.updated_at_ms < *last_synced {
                                    debug!(
                                        session_id = %request.session_id,
                                        incoming_updated_at_ms = request.runtime_status.updated_at_ms,
                                        last_synced_updated_at_ms = *last_synced,
                                        "Skipping stale runtime status update"
                                    );
                                    continue;
                                }
                            }

                            if let Some(syncer) = &realtime_syncer {
                                let incoming_ms = request.runtime_status.updated_at_ms;
                                let hot_path_ms =
                                    last_hot_path_by_session.get(&request.session_id).copied();
                                if hot_path_ms.map_or(true, |last_ms| incoming_ms > last_ms) {
                                    syncer.enqueue(request.clone());
                                    last_hot_path_by_session
                                        .insert(request.session_id.clone(), incoming_ms);
                                }
                            }

                            match client
                                .update_runtime_status(
                                    &request.session_id,
                                    &request.runtime_status,
                                    &ctx.access_token,
                                )
                                .await
                            {
                                Ok(()) => {
                                    last_synced_by_session.insert(
                                        request.session_id.clone(),
                                        request.runtime_status.updated_at_ms,
                                    );
                                }
                                Err(err) => {
                                    warn!(
                                        session_id = %request.session_id,
                                        status = request.runtime_status.coding_session.status.as_str(),
                                        updated_at_ms = request.runtime_status.updated_at_ms,
                                        error = %err,
                                        "Session sync runtime-status Supabase sync failed"
                                    );
                                    coalesce_runtime_status_request(
                                        &mut pending,
                                        &last_synced_by_session,
                                        request,
                                    );
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    /// Spawns an async task to process a side-effect.
    ///
    /// Clones necessary references and spawns on the Tokio runtime to avoid
    /// blocking the synchronous emit() call. Handles each effect type with
    /// appropriate Supabase operations and logs errors without failing.
    fn handle_effect(&self, effect: SideEffect) {
        if let SideEffect::RuntimeStatusUpdated {
            session_id,
            runtime_status,
        } = effect
        {
            self.enqueue_runtime_status_update(RuntimeStatusSyncRequest {
                session_id: session_id.as_str().to_string(),
                runtime_status,
            });
            return;
        }

        // Clone Arc references for the spawned task
        let client = self.client.clone();
        let context = self.context.clone();
        let metadata_provider = self.metadata_provider.clone();
        let message_syncer = self.message_syncer.clone();
        let realtime_message_syncer = self.realtime_message_syncer.clone();

        self.runtime.spawn(async move {
            // Early exit if no sync context is configured
            let ctx = {
                let guard = context.read().await;
                match guard.as_ref() {
                    Some(ctx) => ctx.clone(),
                    None => {
                        debug!(?effect, "Session sync: skipping sync (no context)");
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
                                metadata.title.as_deref(),
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
                                metadata.title.as_deref(),
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
                    let supabase_syncer = {
                        let guard = message_syncer.read().await;
                        guard.as_ref().cloned()
                    };
                    let realtime_syncer = {
                        let guard = realtime_message_syncer.read().await;
                        guard.as_ref().cloned()
                    };

                    let request = MessageSyncRequest {
                        session_id: session_id.as_str().to_string(),
                        message_id: message_id.as_str().to_string(),
                        sequence_number: *sequence_number,
                        content: content.clone(),
                    };

                    let mut dispatched = false;
                    if let Some(syncer) = supabase_syncer {
                        syncer.enqueue(request.clone());
                        dispatched = true;
                    }
                    if let Some(syncer) = realtime_syncer {
                        syncer.enqueue(request);
                        dispatched = true;
                    }

                    if dispatched {
                        Ok(())
                    } else {
                        debug!(
                            session_id = session_id.as_str(),
                            message_id = message_id.as_str(),
                            "Session sync: MessageAppended (no message syncers)"
                        );
                        Ok(())
                    }
                }

                SideEffect::RuntimeStatusUpdated { .. } => Ok(()),
            };

            // Log errors but don't fail
            if let Err(e) = result {
                error!(?effect, error = %e, "Session sync: failed to sync side-effect");
            }
        });
    }
}

fn coalesce_runtime_status_request(
    pending: &mut HashMap<String, RuntimeStatusSyncRequest>,
    last_synced_by_session: &HashMap<String, i64>,
    request: RuntimeStatusSyncRequest,
) {
    let session_id = request.session_id.clone();
    let incoming_ms = request.runtime_status.updated_at_ms;

    if let Some(last_synced_ms) = last_synced_by_session.get(&session_id) {
        if incoming_ms < *last_synced_ms {
            return;
        }
    }

    match pending.get(&session_id) {
        Some(existing) if existing.runtime_status.updated_at_ms > incoming_ms => {}
        _ => {
            pending.insert(session_id, request);
        }
    }
}

impl std::fmt::Debug for SessionSyncSink {
    /// Provides minimal debug output without exposing internal state.
    ///
    /// Uses finish_non_exhaustive to indicate internal fields are omitted
    /// for security (credentials) and brevity.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionSyncSink").finish_non_exhaustive()
    }
}

impl SideEffectSink for SessionSyncSink {
    /// Receives a side-effect from Armin and queues it for async sync.
    ///
    /// Logs the effect for debugging and delegates to handle_effect() which
    /// spawns an async task. This method returns immediately without waiting
    /// for the sync to complete (fire-and-forget).
    fn emit(&self, effect: SideEffect) {
        debug!(?effect, "Session sync: received side-effect");
        self.handle_effect(effect);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_session_sqlite_persist_core::types::{
        CodingSessionRuntimeState, CodingSessionStatus, MessageId, RepositoryId,
        RuntimeStatusEnvelope, SessionId, RUNTIME_STATUS_SCHEMA_VERSION,
    };
    use std::sync::atomic::{AtomicUsize, Ordering};

    // =========================================================================
    // Mock implementations
    // =========================================================================

    struct MockMetadataProvider {
        metadata: std::sync::Mutex<HashMap<String, SessionMetadata>>,
    }

    impl MockMetadataProvider {
        fn new() -> Self {
            Self {
                metadata: std::sync::Mutex::new(HashMap::new()),
            }
        }

        fn insert(&self, session_id: &str, metadata: SessionMetadata) {
            self.metadata
                .lock()
                .unwrap()
                .insert(session_id.to_string(), metadata);
        }
    }

    impl SessionMetadataProvider for MockMetadataProvider {
        fn get_session_metadata(&self, session_id: &str) -> Option<SessionMetadata> {
            self.metadata.lock().unwrap().get(session_id).cloned()
        }
    }

    struct RecordingMessageSyncer {
        requests: std::sync::Mutex<Vec<MessageSyncRequest>>,
        call_count: AtomicUsize,
    }

    impl RecordingMessageSyncer {
        fn new() -> Self {
            Self {
                requests: std::sync::Mutex::new(Vec::new()),
                call_count: AtomicUsize::new(0),
            }
        }

        fn count(&self) -> usize {
            self.call_count.load(Ordering::SeqCst)
        }

        fn requests(&self) -> Vec<MessageSyncRequest> {
            self.requests.lock().unwrap().clone()
        }
    }

    impl MessageSyncer for RecordingMessageSyncer {
        fn enqueue(&self, request: MessageSyncRequest) {
            self.call_count.fetch_add(1, Ordering::SeqCst);
            self.requests.lock().unwrap().push(request);
        }
    }

    struct RecordingRuntimeStatusSyncer {
        requests: std::sync::Mutex<Vec<RuntimeStatusSyncRequest>>,
        call_count: AtomicUsize,
    }

    impl RecordingRuntimeStatusSyncer {
        fn new() -> Self {
            Self {
                requests: std::sync::Mutex::new(Vec::new()),
                call_count: AtomicUsize::new(0),
            }
        }

        fn count(&self) -> usize {
            self.call_count.load(Ordering::SeqCst)
        }

        fn requests(&self) -> Vec<RuntimeStatusSyncRequest> {
            self.requests.lock().unwrap().clone()
        }
    }

    impl RuntimeStatusSyncer for RecordingRuntimeStatusSyncer {
        fn enqueue(&self, request: RuntimeStatusSyncRequest) {
            self.call_count.fetch_add(1, Ordering::SeqCst);
            self.requests.lock().unwrap().push(request);
        }
    }

    use std::collections::HashMap;

    // =========================================================================
    // Context management
    // =========================================================================

    #[tokio::test]
    async fn test_sink_without_context() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

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
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

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

    #[tokio::test]
    async fn context_can_be_replaced() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token-1".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;
        assert!(sink.is_enabled().await);

        // Replace with new context
        sink.set_context(SyncContext {
            access_token: "token-2".to_string(),
            user_id: "user-2".to_string(),
            device_id: "device-2".to_string(),
        })
        .await;
        assert!(sink.is_enabled().await);
    }

    // =========================================================================
    // Metadata provider lifecycle
    // =========================================================================

    #[tokio::test]
    async fn metadata_provider_set_and_clear() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        let provider = Arc::new(MockMetadataProvider::new());
        sink.set_metadata_provider(provider).await;

        // Verify it was set by checking the internal state
        {
            let guard = sink.metadata_provider.read().await;
            assert!(guard.is_some());
        }

        sink.clear_metadata_provider().await;
        {
            let guard = sink.metadata_provider.read().await;
            assert!(guard.is_none());
        }
    }

    // =========================================================================
    // Message syncer lifecycle
    // =========================================================================

    #[tokio::test]
    async fn message_syncer_set_and_clear() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        let syncer = Arc::new(RecordingMessageSyncer::new());
        sink.set_message_syncer(syncer).await;

        {
            let guard = sink.message_syncer.read().await;
            assert!(guard.is_some());
        }

        sink.clear_message_syncer().await;
        {
            let guard = sink.message_syncer.read().await;
            assert!(guard.is_none());
        }
    }

    #[tokio::test]
    async fn realtime_syncer_set_and_clear() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        let syncer = Arc::new(RecordingMessageSyncer::new());
        sink.set_realtime_message_syncer(syncer).await;

        {
            let guard = sink.realtime_message_syncer.read().await;
            assert!(guard.is_some());
        }

        sink.clear_realtime_message_syncer().await;
        {
            let guard = sink.realtime_message_syncer.read().await;
            assert!(guard.is_none());
        }
    }

    #[tokio::test]
    async fn runtime_status_syncer_set_and_clear() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        let syncer = Arc::new(RecordingRuntimeStatusSyncer::new());
        sink.set_realtime_runtime_status_syncer(syncer).await;

        {
            let guard = sink.realtime_runtime_status_syncer.read().await;
            assert!(guard.is_some());
        }

        sink.clear_realtime_runtime_status_syncer().await;
        {
            let guard = sink.realtime_runtime_status_syncer.read().await;
            assert!(guard.is_none());
        }
    }

    // =========================================================================
    // Message dispatch to syncers
    // =========================================================================

    #[tokio::test]
    async fn message_appended_dispatches_to_message_syncer() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        let syncer = Arc::new(RecordingMessageSyncer::new());
        sink.set_message_syncer(syncer.clone()).await;

        sink.emit(SideEffect::MessageAppended {
            session_id: SessionId::from_string("sess-1"),
            message_id: MessageId::from_string("msg-1"),
            sequence_number: 1,
            content: "hello world".to_string(),
        });

        // Give spawned task time to execute
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        assert_eq!(syncer.count(), 1);
        let requests = syncer.requests();
        assert_eq!(requests[0].session_id, "sess-1");
        assert_eq!(requests[0].message_id, "msg-1");
        assert_eq!(requests[0].sequence_number, 1);
        assert_eq!(requests[0].content, "hello world");
    }

    #[tokio::test]
    async fn message_appended_dispatches_to_both_syncers() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        let supabase_syncer = Arc::new(RecordingMessageSyncer::new());
        let realtime_syncer = Arc::new(RecordingMessageSyncer::new());
        sink.set_message_syncer(supabase_syncer.clone()).await;
        sink.set_realtime_message_syncer(realtime_syncer.clone())
            .await;

        sink.emit(SideEffect::MessageAppended {
            session_id: SessionId::from_string("sess-1"),
            message_id: MessageId::from_string("msg-1"),
            sequence_number: 1,
            content: "hello".to_string(),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        assert_eq!(supabase_syncer.count(), 1);
        assert_eq!(realtime_syncer.count(), 1);
    }

    #[tokio::test]
    async fn message_appended_without_syncers_does_not_panic() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        // No syncers set — should not panic
        sink.emit(SideEffect::MessageAppended {
            session_id: SessionId::from_string("sess-1"),
            message_id: MessageId::from_string("msg-1"),
            sequence_number: 1,
            content: "hello".to_string(),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    #[tokio::test]
    async fn message_appended_without_context_skips_dispatch() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);
        // No context set

        let syncer = Arc::new(RecordingMessageSyncer::new());
        sink.set_message_syncer(syncer.clone()).await;

        sink.emit(SideEffect::MessageAppended {
            session_id: SessionId::from_string("sess-1"),
            message_id: MessageId::from_string("msg-1"),
            sequence_number: 1,
            content: "hello".to_string(),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;

        // Syncer should NOT have been called because context is missing
        assert_eq!(syncer.count(), 0);
    }

    // =========================================================================
    // Runtime status fanout and coalescing
    // =========================================================================

    fn runtime_envelope(
        session_id: &str,
        status: CodingSessionStatus,
        updated_at_ms: i64,
    ) -> RuntimeStatusEnvelope {
        RuntimeStatusEnvelope {
            schema_version: RUNTIME_STATUS_SCHEMA_VERSION,
            coding_session: CodingSessionRuntimeState {
                status,
                error_message: None,
            },
            device_id: "device-1".to_string(),
            session_id: SessionId::from_string(session_id),
            updated_at_ms,
        }
    }

    #[tokio::test]
    async fn runtime_status_updated_dispatches_to_realtime_syncer() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);
        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        let syncer = Arc::new(RecordingRuntimeStatusSyncer::new());
        sink.set_realtime_runtime_status_syncer(syncer.clone())
            .await;

        sink.emit(SideEffect::RuntimeStatusUpdated {
            session_id: SessionId::from_string("sess-1"),
            runtime_status: runtime_envelope("sess-1", CodingSessionStatus::Running, 1000),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(180)).await;

        assert_eq!(syncer.count(), 1);
        let requests = syncer.requests();
        assert_eq!(requests[0].session_id, "sess-1");
        assert_eq!(
            requests[0].runtime_status.coding_session.status,
            CodingSessionStatus::Running
        );
    }

    #[tokio::test]
    async fn runtime_status_worker_coalesces_and_drops_stale_updates() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);
        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        let syncer = Arc::new(RecordingRuntimeStatusSyncer::new());
        sink.set_realtime_runtime_status_syncer(syncer.clone())
            .await;

        sink.emit(SideEffect::RuntimeStatusUpdated {
            session_id: SessionId::from_string("sess-1"),
            runtime_status: runtime_envelope("sess-1", CodingSessionStatus::Running, 1_000),
        });
        sink.emit(SideEffect::RuntimeStatusUpdated {
            session_id: SessionId::from_string("sess-1"),
            runtime_status: runtime_envelope("sess-1", CodingSessionStatus::Waiting, 1_050),
        });
        sink.emit(SideEffect::RuntimeStatusUpdated {
            session_id: SessionId::from_string("sess-1"),
            runtime_status: runtime_envelope("sess-1", CodingSessionStatus::Idle, 900),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(220)).await;

        assert_eq!(syncer.count(), 1);
        let requests = syncer.requests();
        assert_eq!(
            requests[0].runtime_status.coding_session.status,
            CodingSessionStatus::Waiting
        );
        assert_eq!(requests[0].runtime_status.updated_at_ms, 1_050);
    }

    // =========================================================================
    // Emit all side-effect variants without panic (smoke tests)
    // =========================================================================

    #[tokio::test]
    async fn emit_all_side_effect_variants_without_context() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        // Emit every variant — none should panic
        sink.emit(SideEffect::RepositoryCreated {
            repository_id: RepositoryId::from_string("repo-1"),
        });
        sink.emit(SideEffect::RepositoryDeleted {
            repository_id: RepositoryId::from_string("repo-1"),
        });
        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("sess-1"),
        });
        sink.emit(SideEffect::SessionClosed {
            session_id: SessionId::from_string("sess-1"),
        });
        sink.emit(SideEffect::SessionDeleted {
            session_id: SessionId::from_string("sess-1"),
        });
        sink.emit(SideEffect::SessionUpdated {
            session_id: SessionId::from_string("sess-1"),
        });
        sink.emit(SideEffect::MessageAppended {
            session_id: SessionId::from_string("sess-1"),
            message_id: MessageId::from_string("msg-1"),
            sequence_number: 1,
            content: "test".to_string(),
        });
        sink.emit(SideEffect::RuntimeStatusUpdated {
            session_id: SessionId::from_string("sess-1"),
            runtime_status: RuntimeStatusEnvelope {
                schema_version: RUNTIME_STATUS_SCHEMA_VERSION,
                coding_session: CodingSessionRuntimeState {
                    status: CodingSessionStatus::Running,
                    error_message: None,
                },
                device_id: "device-1".to_string(),
                session_id: SessionId::from_string("sess-1"),
                updated_at_ms: 1,
            },
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    #[tokio::test]
    async fn emit_session_created_without_metadata_provider() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        // No metadata provider set — should not panic, just warn
        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("sess-1"),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    #[tokio::test]
    async fn emit_session_updated_without_metadata_provider() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        sink.emit(SideEffect::SessionUpdated {
            session_id: SessionId::from_string("sess-1"),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    #[tokio::test]
    async fn emit_session_created_with_provider_but_missing_metadata() {
        let runtime = tokio::runtime::Handle::current();
        let sink = SessionSyncSink::new("https://test.supabase.co", "test-key", runtime);

        sink.set_context(SyncContext {
            access_token: "token".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        let provider = Arc::new(MockMetadataProvider::new());
        // Provider exists but has no metadata for "sess-1"
        sink.set_metadata_provider(provider).await;

        sink.emit(SideEffect::SessionCreated {
            session_id: SessionId::from_string("sess-1"),
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    // =========================================================================
    // Debug impl
    // =========================================================================

    #[test]
    fn session_sync_sink_debug_is_opaque() {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let sink = SessionSyncSink::new(
            "https://test.supabase.co",
            "secret-key",
            runtime.handle().clone(),
        );
        let debug = format!("{:?}", sink);
        assert!(debug.contains("SessionSyncSink"));
        assert!(!debug.contains("secret-key"));
    }

    // =========================================================================
    // SyncContext / SessionMetadata / MessageSyncRequest struct tests
    // =========================================================================

    #[test]
    fn sync_context_is_cloneable() {
        let ctx = SyncContext {
            access_token: "token".to_string(),
            user_id: "user".to_string(),
            device_id: "device".to_string(),
        };
        let cloned = ctx.clone();
        assert_eq!(cloned.access_token, "token");
        assert_eq!(cloned.user_id, "user");
        assert_eq!(cloned.device_id, "device");
    }

    #[test]
    fn session_metadata_is_cloneable_and_debuggable() {
        let meta = SessionMetadata {
            repository_id: "repo-1".to_string(),
            title: Some("Session Title".to_string()),
            current_branch: Some("main".to_string()),
            working_directory: Some("/home/user/project".to_string()),
            is_worktree: false,
            worktree_path: None,
        };
        let cloned = meta.clone();
        assert_eq!(cloned.repository_id, "repo-1");
        assert_eq!(cloned.current_branch, Some("main".to_string()));
        assert!(!cloned.is_worktree);
        assert!(cloned.worktree_path.is_none());
        // Debug should not panic
        let _ = format!("{:?}", cloned);
    }

    #[test]
    fn message_sync_request_is_cloneable_and_debuggable() {
        let req = MessageSyncRequest {
            session_id: "sess-1".to_string(),
            message_id: "msg-1".to_string(),
            sequence_number: 42,
            content: "test content".to_string(),
        };
        let cloned = req.clone();
        assert_eq!(cloned.session_id, "sess-1");
        assert_eq!(cloned.message_id, "msg-1");
        assert_eq!(cloned.sequence_number, 42);
        assert_eq!(cloned.content, "test content");
        let _ = format!("{:?}", cloned);
    }

    // =========================================================================
    // Mock metadata provider
    // =========================================================================

    #[test]
    fn mock_metadata_provider_returns_none_for_unknown() {
        let provider = MockMetadataProvider::new();
        assert!(provider.get_session_metadata("unknown").is_none());
    }

    #[test]
    fn mock_metadata_provider_returns_inserted_metadata() {
        let provider = MockMetadataProvider::new();
        provider.insert(
            "sess-1",
            SessionMetadata {
                repository_id: "repo-1".to_string(),
                title: Some("Session Title".to_string()),
                current_branch: Some("main".to_string()),
                working_directory: None,
                is_worktree: false,
                worktree_path: None,
            },
        );
        let meta = provider.get_session_metadata("sess-1").unwrap();
        assert_eq!(meta.repository_id, "repo-1");
    }
}
