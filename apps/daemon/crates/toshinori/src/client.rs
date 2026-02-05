//! Supabase REST API client for Toshinori.

use crate::error::{ToshinoriError, ToshinoriResult};
use serde::Serialize;
use tracing::{debug, error, warn};

/// Message payload for Supabase upsert.
#[derive(Debug, Serialize)]
pub struct MessageUpsert {
    pub session_id: String,
    pub sequence_number: i64,
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_encrypted: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_nonce: Option<String>,
}

/// Supabase REST API client for syncing Armin data.
#[derive(Clone)]
pub struct SupabaseClient {
    http_client: reqwest::Client,
    api_url: String,
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

    /// Build the REST API URL for a table.
    fn rest_url(&self, table: &str) -> String {
        format!("{}/rest/v1/{}", self.api_url, table)
    }

    /// Upsert a repository to Supabase.
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

    /// Delete a repository from Supabase.
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

    /// Upsert a coding session to Supabase.
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

        let now = chrono::Utc::now().to_rfc3339();

        let mut body = serde_json::json!({
            "id": session_id,
            "user_id": user_id,
            "device_id": device_id,
            "repository_id": repository_id,
            "status": status,
            "is_worktree": is_worktree,
            "last_heartbeat_at": now
        });

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

    /// Update session status in Supabase.
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

    /// Delete a session from Supabase.
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

    /// Upsert a message to Supabase.
    pub async fn upsert_message(
        &self,
        session_id: &str,
        content_encrypted: Option<&str>,
        content_nonce: Option<&str>,
        role: &str,
        sequence_number: i64,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let message = MessageUpsert {
            session_id: session_id.to_string(),
            sequence_number,
            role: role.to_string(),
            content_encrypted: content_encrypted.map(|v| v.to_string()),
            content_nonce: content_nonce.map(|v| v.to_string()),
        };

        self.upsert_messages_batch(&[message], access_token).await
    }

    /// Upsert a batch of messages to Supabase.
    pub async fn upsert_messages_batch(
        &self,
        messages: &[MessageUpsert],
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = format!(
            "{}?on_conflict=session_id,sequence_number",
            self.rest_url("agent_coding_session_messages")
        );

        if messages.is_empty() {
            return Ok(());
        }

        debug!(count = messages.len(), "Syncing message batch to Supabase");

        self.upsert(&url, messages, access_token).await?;

        debug!(count = messages.len(), "Message batch synced to Supabase");
        Ok(())
    }

    /// Update agent status in Supabase.
    pub async fn update_agent_status(
        &self,
        session_id: &str,
        status: &str,
        _access_token: &str,
    ) -> ToshinoriResult<()> {
        warn!(
            session_id,
            status,
            "Agent status sync skipped (no agent_status column in Supabase schema)"
        );
        Ok(())
    }

    // =========================================================================
    // HTTP helpers
    // =========================================================================

    /// Perform an upsert (POST with merge-duplicates).
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

    /// Perform a PATCH update.
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

    /// Perform a DELETE.
    async fn delete(&self, url: &str, access_token: &str) -> ToshinoriResult<()> {
        let response = self
            .http_client
            .delete(url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await?;

        // Don't fail on delete errors (resource may not exist)
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!("Delete request failed: {} - {}", status, body);
        }

        Ok(())
    }

    /// Check HTTP response for errors.
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
}
