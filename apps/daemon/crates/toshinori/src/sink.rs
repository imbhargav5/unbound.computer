//! Toshinori SideEffectSink implementation.
//!
//! This module provides the main `SideEffectSink` that syncs Armin's
//! side-effects to Supabase.

use crate::client::SupabaseClient;
use armin::{SideEffect, SideEffectSink};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info};

/// Context required for Supabase sync operations.
#[derive(Clone)]
pub struct SyncContext {
    /// Supabase access token for API authentication.
    pub access_token: String,
    /// User ID for ownership tracking.
    pub user_id: String,
    /// Device ID for this daemon instance.
    pub device_id: String,
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
            runtime,
        }
    }

    /// Set the sync context (call after authentication).
    ///
    /// Until this is called, side-effects will be logged but not synced.
    pub async fn set_context(&self, context: SyncContext) {
        let mut ctx = self.context.write().await;
        *ctx = Some(context);
        info!("Toshinori sync context set");
    }

    /// Clear the sync context (call on logout).
    pub async fn clear_context(&self) {
        let mut ctx = self.context.write().await;
        *ctx = None;
        info!("Toshinori sync context cleared");
    }

    /// Check if sync is enabled (context is set).
    pub async fn is_enabled(&self) -> bool {
        self.context.read().await.is_some()
    }

    /// Handle a side-effect asynchronously.
    fn handle_effect(&self, effect: SideEffect) {
        let client = self.client.clone();
        let context = self.context.clone();

        self.runtime.spawn(async move {
            // Get context (if not set, just log and return)
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

            // Sync based on effect type
            let result = match &effect {
                SideEffect::RepositoryCreated { repository_id } => {
                    client
                        .upsert_repository(
                            repository_id.as_str(),
                            &ctx.user_id,
                            &ctx.device_id,
                            &ctx.access_token,
                        )
                        .await
                }

                SideEffect::RepositoryDeleted { repository_id } => {
                    client
                        .delete_repository(repository_id.as_str(), &ctx.access_token)
                        .await
                }

                SideEffect::SessionCreated { session_id } => {
                    client
                        .upsert_session(
                            session_id.as_str(),
                            &ctx.user_id,
                            &ctx.device_id,
                            "active",
                            &ctx.access_token,
                        )
                        .await
                }

                SideEffect::SessionClosed { session_id } => {
                    client
                        .update_session_status(session_id.as_str(), "closed", &ctx.access_token)
                        .await
                }

                SideEffect::SessionDeleted { session_id } => {
                    client
                        .delete_session(session_id.as_str(), &ctx.access_token)
                        .await
                }

                SideEffect::SessionUpdated { session_id } => {
                    // Session metadata update - just touch the heartbeat
                    client
                        .update_session_status(session_id.as_str(), "active", &ctx.access_token)
                        .await
                }

                SideEffect::MessageAppended {
                    session_id,
                    message_id,
                } => {
                    // Note: We don't have the message content here.
                    // The actual sync would need to fetch from Armin or
                    // we need to extend the SideEffect to include content.
                    debug!(
                        session_id = session_id.as_str(),
                        message_id = message_id.as_str(),
                        "Toshinori: MessageAppended (content sync TBD)"
                    );
                    Ok(())
                }

                SideEffect::AgentStatusChanged { session_id, status } => {
                    client
                        .update_agent_status(
                            session_id.as_str(),
                            status.as_str(),
                            &ctx.access_token,
                        )
                        .await
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
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ToshinoriSink").finish_non_exhaustive()
    }
}

impl SideEffectSink for ToshinoriSink {
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
