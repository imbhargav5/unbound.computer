//! Supabase REST API client for Toshinori.

use crate::error::{ToshinoriError, ToshinoriResult};
use serde::Serialize;
use tracing::{debug, error, warn};

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
        status: &str,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = self.rest_url("agent_coding_sessions");

        let now = chrono::Utc::now().to_rfc3339();

        let body = serde_json::json!({
            "id": session_id,
            "user_id": user_id,
            "device_id": device_id,
            "status": status,
            "last_heartbeat_at": now
        });

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
        message_id: &str,
        session_id: &str,
        content: &str,
        sequence_number: i64,
        access_token: &str,
    ) -> ToshinoriResult<()> {
        let url = self.rest_url("agent_coding_session_messages");

        let now = chrono::Utc::now().to_rfc3339();

        let body = serde_json::json!({
            "id": message_id,
            "session_id": session_id,
            "content": content,
            "sequence_number": sequence_number,
            "created_at": now
        });

        debug!(message_id, session_id, "Syncing message to Supabase");

        self.upsert(&url, &body, access_token).await?;

        debug!(message_id, "Message synced to Supabase");
        Ok(())
    }

    /// Update agent status in Supabase.
    pub async fn update_agent_status(
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

        let body = serde_json::json!({
            "agent_status": status,
            "last_heartbeat_at": now
        });

        debug!(session_id, status, "Updating agent status in Supabase");

        self.patch(&url, &body, access_token).await?;

        debug!(session_id, "Agent status updated in Supabase");
        Ok(())
    }

    // =========================================================================
    // HTTP helpers
    // =========================================================================

    /// Perform an upsert (POST with merge-duplicates).
    async fn upsert<T: Serialize>(
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
