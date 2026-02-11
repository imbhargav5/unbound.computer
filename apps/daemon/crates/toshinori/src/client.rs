//! Supabase REST API client for Toshinori.
//!
//! Provides a typed HTTP client for interacting with Supabase PostgREST API
//! to sync Armin's local state with the cloud database.

use crate::error::{ToshinoriError, ToshinoriResult};
use serde::Serialize;
use tracing::{debug, error, warn};

/// Represents a message payload formatted for Supabase upsert operations.
///
/// Contains the encrypted message content and metadata required for
/// inserting or updating messages in the remote database. Optional fields
/// are omitted from serialization when None.
#[derive(Debug, Serialize)]
pub struct MessageUpsert {
    /// The session this message belongs to.
    pub session_id: String,
    /// The message's position in the session's message sequence.
    pub sequence_number: i64,
    /// Base64-encoded encrypted message content (omitted if None).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_encrypted: Option<String>,
    /// Base64-encoded nonce used for encryption (omitted if None).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_nonce: Option<String>,
}

/// HTTP client for Supabase REST API operations.
///
/// Handles authentication, request building, and error handling for all
/// Supabase sync operations. Cloneable for sharing across async tasks.
#[derive(Clone)]
pub struct SupabaseClient {
    /// The underlying HTTP client for making requests.
    http_client: reqwest::Client,
    /// The Supabase project API URL (e.g., https://xyz.supabase.co).
    api_url: String,
    /// The Supabase anonymous API key for public access.
    anon_key: String,
}

impl SupabaseClient {
    /// Create a new Supabase client.
    ///
    /// # Arguments
    /// * `api_url` - The Supabase project API URL (e.g., `https://xyz.supabase.co`)
    /// * `anon_key` - The Supabase anonymous API key
    pub fn new(api_url: impl Into<String>, anon_key: impl Into<String>) -> Self {
        Self {
            http_client: reqwest::Client::new(),
            api_url: api_url.into(),
            anon_key: anon_key.into(),
        }
    }

    /// Constructs the full REST API URL for a given table name.
    ///
    /// Combines the base API URL with the PostgREST path to form the
    /// complete endpoint URL for table operations.
    fn rest_url(&self, table: &str) -> String {
        format!("{}/rest/v1/{}", self.api_url, table)
    }

    /// Creates or updates a repository record in Supabase.
    ///
    /// Performs an upsert operation that either creates a new repository entry
    /// or updates an existing one if the ID matches. Sets the status to "active".
    pub async fn upsert_repository(
        &self,
        repository_id: &str,
        user_id: &str,
        device_id: &str,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = self.rest_url("repositories");

        let body = serde_json::json!({
            "id": repository_id,
            "user_id": user_id,
            "device_id": device_id,
            "status": "active"
        });

        debug!(repository_id, "Syncing repository to Supabase");

        self.upsert(&url, &body, access_token).await?;

        debug!(repository_id, "Repository synced to Supabase");
        Ok(())
    }

    /// Removes a repository record from Supabase.
    ///
    /// Deletes the repository with the given ID. Does not fail if the
    /// repository doesn't exist (idempotent delete behavior).
    pub async fn delete_repository(
        &self,
        repository_id: &str,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = format!("{}?id=eq.{}", self.rest_url("repositories"), repository_id);

        debug!(repository_id, "Deleting repository from Supabase");

        self.delete(&url, access_token).await?;

        debug!(repository_id, "Repository deleted from Supabase");
        Ok(())
    }

    /// Creates or updates a coding session record in Supabase.
    ///
    /// Performs an upsert with full session metadata including worktree info,
    /// branch, and working directory. Updates the heartbeat timestamp to track
    /// session liveness.
    pub async fn upsert_session(
        &self,
        session_id: &str,
        user_id: &str,
        device_id: &str,
        repository_id: &str,
        status: &str,
        current_branch: Option<&str>,
        working_directory: Option<&str>,
        is_worktree: bool,
        worktree_path: Option<&str>,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = self.rest_url("agent_coding_sessions");

        // Set current timestamp for heartbeat tracking
        let now = chrono::Utc::now().to_rfc3339();

        // Build the base JSON payload with required fields
        let mut body = serde_json::json!({
            "id": session_id,
            "user_id": user_id,
            "device_id": device_id,
            "repository_id": repository_id,
            "status": status,
            "is_worktree": is_worktree,
            "last_heartbeat_at": now
        });

        // Add optional fields only if provided
        if let Some(branch) = current_branch {
            body["current_branch"] = serde_json::json!(branch);
        }
        if let Some(dir) = working_directory {
            body["working_directory"] = serde_json::json!(dir);
        }
        if let Some(path) = worktree_path {
            body["worktree_path"] = serde_json::json!(path);
        }

        debug!(session_id, status, "Syncing session to Supabase");

        self.upsert(&url, &body, access_token).await?;

        debug!(session_id, "Session synced to Supabase");
        Ok(())
    }

    /// Updates only the status field of an existing session.
    ///
    /// Performs a PATCH operation to update the session status without
    /// touching other fields. Converts "closed" status to "ended" for
    /// Supabase schema compatibility. Also updates the heartbeat timestamp.
    pub async fn update_session_status(
        &self,
        session_id: &str,
        status: &str,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = format!(
            "{}?id=eq.{}",
            self.rest_url("agent_coding_sessions"),
            session_id
        );

        let now = chrono::Utc::now().to_rfc3339();
        // Map "closed" to "ended" for Supabase schema compatibility
        let status = if status == "closed" { "ended" } else { status };

        let body = serde_json::json!({
            "status": status,
            "last_heartbeat_at": now
        });

        debug!(session_id, status, "Updating session status in Supabase");

        self.patch(&url, &body, access_token).await?;

        debug!(session_id, "Session status updated in Supabase");
        Ok(())
    }

    /// Removes a session record from Supabase.
    ///
    /// Deletes the session with the given ID. Does not fail if the session
    /// doesn't exist (idempotent delete behavior for crash recovery).
    pub async fn delete_session(
        &self,
        session_id: &str,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = format!(
            "{}?id=eq.{}",
            self.rest_url("agent_coding_sessions"),
            session_id
        );

        debug!(session_id, "Deleting session from Supabase");

        self.delete(&url, access_token).await?;

        debug!(session_id, "Session deleted from Supabase");
        Ok(())
    }

    /// Creates or updates a single message in Supabase.
    ///
    /// Convenience wrapper around upsert_messages_batch for single-message
    /// operations. The message is identified by session_id + sequence_number.
    pub async fn upsert_message(
        &self,
        session_id: &str,
        content_encrypted: Option<&str>,
        content_nonce: Option<&str>,
        sequence_number: i64,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let message = MessageUpsert {
            session_id: session_id.to_string(),
            sequence_number,
            content_encrypted: content_encrypted.map(|v| v.to_string()),
            content_nonce: content_nonce.map(|v| v.to_string()),
        };

        self.upsert_messages_batch(&[message], access_token).await
    }

    /// Creates or updates multiple messages in a single request.
    ///
    /// Performs a batch upsert using on_conflict for the (session_id, sequence_number)
    /// compound key. Empty batches are handled as no-ops. More efficient than
    /// individual upserts for bulk sync operations.
    pub async fn upsert_messages_batch(
        &self,
        messages: &[MessageUpsert],
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = format!(
            "{}?on_conflict=session_id,sequence_number",
            self.rest_url("agent_coding_session_messages")
        );

        // Early return for empty batches to avoid unnecessary network calls
        if messages.is_empty() {
            return Ok(());
        }

        debug!(count = messages.len(), "Syncing message batch to Supabase");

        self.upsert(&url, messages, access_token).await?;

        debug!(count = messages.len(), "Message batch synced to Supabase");
        Ok(())
    }

    /// Placeholder for agent status updates (not yet implemented in Supabase schema).
    ///
    /// Currently logs a warning and returns Ok. The agent_status column does not
    /// exist in the current Supabase schema, so this is a no-op that allows the
    /// calling code to remain forward-compatible.
    pub async fn update_agent_status(
        &self,
        session_id: &str,
        status: &str,
        _access_token: &str,
    ) -> ToshinoriResult<()> {
        warn!(
            session_id,
            status, "Agent status sync skipped (no agent_status column in Supabase schema)"
        );
        Ok(())
    }

    // =========================================================================
    // HTTP helpers
    // =========================================================================

    /// Performs a POST request with merge-duplicates conflict resolution.
    ///
    /// Sends the body as JSON with Supabase-specific headers for authentication
    /// and upsert behavior. Returns an error if the response indicates failure.
    async fn upsert<T: Serialize + ?Sized>(
        &self,
        url: &str,
        body: &T,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let response = self
            .http_client
            .post(url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates")
            .json(body)
            .send()
            .await?;

        self.check_response(response).await
    }

    /// Performs a PATCH request to update existing records.
    ///
    /// Sends the body as JSON to update matching records (filtered by URL query).
    /// Returns an error if the response indicates failure.
    async fn patch<T: Serialize>(
        &self,
        url: &str,
        body: &T,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let response = self
            .http_client
            .patch(url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .json(body)
            .send()
            .await?;

        self.check_response(response).await
    }

    /// Performs a DELETE request to remove matching records.
    ///
    /// Uses lenient error handling - logs failures but returns Ok to support
    /// idempotent deletes where the resource may already be gone.
    async fn delete(&self, url: &str, access_token: &str) -> ToshinoriResult<()> {
        let response = self
            .http_client
            .delete(url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await?;

        // Log but don't fail on delete errors for idempotency
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!("Delete request failed: {} - {}", status, body);
        }

        Ok(())
    }

    /// Validates HTTP response and converts errors to ToshinoriError.
    ///
    /// Reads the response body for error details and logs failures before
    /// returning a structured error with status code and message.
    async fn check_response(&self, response: reqwest::Response) -> ToshinoriResult<()> {
        if !response.status().is_success() {
            let status = response.status().as_u16();
            let body = response.text().await.unwrap_or_default();
            error!("Supabase request failed: {} - {}", status, body);
            return Err(ToshinoriError::Supabase {
                status,
                message: body,
            });
        }
        Ok(())
    }
}

impl std::fmt::Debug for SupabaseClient {
    /// Provides debug output that includes the API URL but omits sensitive keys.
    ///
    /// Uses finish_non_exhaustive to indicate that some fields are intentionally
    /// hidden (anon_key, http_client) for security and brevity.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SupabaseClient")
            .field("api_url", &self.api_url)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = SupabaseClient::new("https://test.supabase.co", "test-key");
        assert_eq!(client.api_url, "https://test.supabase.co");
        assert_eq!(client.anon_key, "test-key");
    }

    #[test]
    fn test_rest_url() {
        let client = SupabaseClient::new("https://test.supabase.co", "test-key");
        assert_eq!(
            client.rest_url("repositories"),
            "https://test.supabase.co/rest/v1/repositories"
        );
    }

    #[test]
    fn rest_url_for_sessions_table() {
        let client = SupabaseClient::new("https://abc.supabase.co", "key");
        assert_eq!(
            client.rest_url("agent_coding_sessions"),
            "https://abc.supabase.co/rest/v1/agent_coding_sessions"
        );
    }

    #[test]
    fn rest_url_for_messages_table() {
        let client = SupabaseClient::new("https://abc.supabase.co", "key");
        assert_eq!(
            client.rest_url("agent_coding_session_messages"),
            "https://abc.supabase.co/rest/v1/agent_coding_session_messages"
        );
    }

    #[test]
    fn message_upsert_serialization_all_fields() {
        let msg = MessageUpsert {
            session_id: "sess-1".to_string(),
            sequence_number: 42,
            content_encrypted: Some("encrypted-data".to_string()),
            content_nonce: Some("nonce-data".to_string()),
        };
        let json = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["session_id"], "sess-1");
        assert_eq!(json["sequence_number"], 42);
        assert_eq!(json["content_encrypted"], "encrypted-data");
        assert_eq!(json["content_nonce"], "nonce-data");
    }

    #[test]
    fn message_upsert_serialization_none_fields_omitted() {
        let msg = MessageUpsert {
            session_id: "sess-2".to_string(),
            sequence_number: 1,
            content_encrypted: None,
            content_nonce: None,
        };
        let json = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["session_id"], "sess-2");
        assert_eq!(json["sequence_number"], 1);
        // None fields should be absent, not null
        assert!(json.get("content_encrypted").is_none());
        assert!(json.get("content_nonce").is_none());
    }

    #[test]
    fn message_upsert_serialization_partial_fields() {
        let msg = MessageUpsert {
            session_id: "sess-3".to_string(),
            sequence_number: 10,
            content_encrypted: Some("data".to_string()),
            content_nonce: None,
        };
        let json = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["content_encrypted"], "data");
        assert!(json.get("content_nonce").is_none());
    }

    #[test]
    fn debug_impl_hides_anon_key() {
        let client = SupabaseClient::new("https://test.supabase.co", "super-secret-key");
        let debug = format!("{:?}", client);
        assert!(debug.contains("https://test.supabase.co"));
        assert!(!debug.contains("super-secret-key"));
    }

    #[test]
    fn client_is_cloneable() {
        let client = SupabaseClient::new("https://test.supabase.co", "key");
        let cloned = client.clone();
        assert_eq!(cloned.api_url, "https://test.supabase.co");
        assert_eq!(cloned.anon_key, "key");
    }

    #[tokio::test]
    async fn upsert_messages_batch_empty_is_noop() {
        let client = SupabaseClient::new("https://test.supabase.co", "key");
        // Empty batch should return Ok without making any HTTP request
        let result = client.upsert_messages_batch(&[], "fake-token").await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn update_agent_status_is_noop() {
        let client = SupabaseClient::new("https://test.supabase.co", "key");
        // This is a placeholder that always returns Ok
        let result = client
            .update_agent_status("session-1", "running", "token")
            .await;
        assert!(result.is_ok());
    }
}
