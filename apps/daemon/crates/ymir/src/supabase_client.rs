//! Supabase REST API client for device management and session secret distribution.
//!
//! This module provides a client for interacting with Supabase's REST API to:
//! - Fetch user devices with their public keys
//! - Insert and fetch encrypted session secrets

use crate::error::{AuthError, AuthResult};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

fn summarize_response_body(body: &str) -> String {
    let mut hasher = DefaultHasher::new();
    body.hash(&mut hasher);
    format!("len={},digest={:016x}", body.len(), hasher.finish())
}

/// Supabase REST API client for device and session secret operations.
#[derive(Clone)]
pub struct SupabaseClient {
    http_client: reqwest::Client,
    api_url: String,
    anon_key: String,
}

/// Device information returned from Supabase.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    /// Device UUID
    pub id: String,
    /// User ID who owns this device
    pub user_id: String,
    /// Device type (macos, ios, daemon, cli)
    pub device_type: String,
    /// Device display name
    pub name: String,
    /// Base64-encoded X25519 public key (may be None if not registered)
    pub public_key: Option<String>,
    /// Whether the device is active
    pub is_active: bool,
}

/// Encrypted session secret record for a device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodingSessionSecretRecord {
    /// Session UUID
    pub session_id: String,
    /// Device UUID this secret is encrypted for
    pub device_id: String,
    /// Base64-encoded X25519 ephemeral public key
    pub ephemeral_public_key: String,
    /// Base64-encoded encrypted secret: nonce(12) || ciphertext || tag(16)
    pub encrypted_secret: String,
}

/// Request body for inserting session secrets.
#[derive(Debug, Serialize)]
struct InsertSecretRequest {
    session_id: String,
    device_id: String,
    ephemeral_public_key: String,
    encrypted_secret: String,
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

    /// Fetch all active devices for a user (excluding a specific device).
    ///
    /// Only returns devices that have a public key set (for encryption).
    ///
    /// # Arguments
    /// * `user_id` - The user's UUID
    /// * `exclude_device_id` - Device ID to exclude (typically this device)
    /// * `access_token` - Supabase access token for authentication
    pub async fn fetch_user_devices(
        &self,
        user_id: &str,
        exclude_device_id: &str,
        access_token: &str,
    ) -> AuthResult<Vec<DeviceInfo>> {
        let url = format!(
            "{}?user_id=eq.{}&id=neq.{}&is_active=eq.true&public_key=not.is.null&select=id,user_id,device_type,name,public_key,is_active",
            self.rest_url("devices"),
            user_id,
            exclude_device_id
        );

        tracing::debug!("Fetching devices from Supabase: {}", url);

        let response = self
            .http_client
            .get(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Accept", "application/json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status, body_summary = %body_summary, "Failed to fetch devices");
            return Err(AuthError::OAuth(format!(
                "Failed to fetch devices: {} ({})",
                status, body_summary
            )));
        }

        let devices: Vec<DeviceInfo> = response.json().await?;
        tracing::debug!("Fetched {} devices with public keys", devices.len());
        Ok(devices)
    }

    /// Fetch a single active device by ID.
    ///
    /// Returns `Ok(None)` when no active device exists for that ID.
    pub async fn fetch_device_by_id(
        &self,
        device_id: &str,
        access_token: &str,
    ) -> AuthResult<Option<DeviceInfo>> {
        let url = format!(
            "{}?id=eq.{}&is_active=eq.true&select=id,user_id,device_type,name,public_key,is_active&limit=1",
            self.rest_url("devices"),
            device_id
        );

        tracing::debug!("Fetching device {} from Supabase", device_id);

        let response = self
            .http_client
            .get(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Accept", "application/json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status, body_summary = %body_summary, "Failed to fetch device by id");
            return Err(AuthError::OAuth(format!(
                "Failed to fetch device by id: {} ({})",
                status, body_summary
            )));
        }

        let devices: Vec<DeviceInfo> = response.json().await?;
        Ok(devices.into_iter().next())
    }

    /// Fetch or create this device in Supabase.
    ///
    /// If the device doesn't exist, creates it. If it exists, updates the public key.
    ///
    /// # Arguments
    /// * `device_id` - This device's UUID
    /// * `user_id` - The user's UUID
    /// * `device_type` - Device type (mac-desktop, win-desktop, linux-desktop, etc.)
    /// * `device_name` - Display name for the device
    /// * `public_key` - Base64-encoded X25519 public key
    /// * `access_token` - Supabase access token
    pub async fn upsert_device(
        &self,
        device_id: &str,
        user_id: &str,
        device_type: &str,
        device_name: &str,
        public_key: &str,
        capabilities: Option<serde_json::Value>,
        access_token: &str,
    ) -> AuthResult<()> {
        let url = self.rest_url("devices");

        // Get current timestamp in ISO8601 format
        let now = chrono::Utc::now().to_rfc3339();

        let mut body = serde_json::json!({
            "id": device_id,
            "user_id": user_id,
            "device_type": device_type,
            "name": device_name,
            "hostname": device_name,  // Use device name as hostname
            "public_key": public_key,
            "is_active": true,
            "last_seen_at": now,
            "is_trusted": false,  // New devices are not trusted by default
            "has_seen_trust_prompt": false
        });

        if let Some(capabilities) = capabilities {
            if let Some(body_obj) = body.as_object_mut() {
                body_obj.insert("capabilities".to_string(), capabilities);
            }
        }

        tracing::debug!("Upserting device {} in Supabase", device_id);

        let response = self
            .http_client
            .post(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates")
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status, body_summary = %body_summary, "Failed to upsert device");
            return Err(AuthError::OAuth(format!(
                "Failed to upsert device: {} ({})",
                status, body_summary
            )));
        }

        tracing::info!("Device {} registered/updated in Supabase", device_id);
        Ok(())
    }

    /// Update capabilities for an existing device.
    pub async fn update_device_capabilities(
        &self,
        device_id: &str,
        capabilities: serde_json::Value,
        access_token: &str,
    ) -> AuthResult<()> {
        let url = format!("{}?id=eq.{}", self.rest_url("devices"), device_id);
        let now = chrono::Utc::now().to_rfc3339();

        let body = serde_json::json!({
            "capabilities": capabilities,
            "last_seen_at": now,
        });

        tracing::debug!("Updating device {} capabilities in Supabase", device_id);

        let response = self
            .http_client
            .patch(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "return=minimal")
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(
                status = %status,
                body_summary = %body_summary,
                "Failed to update device capabilities"
            );
            return Err(AuthError::OAuth(format!(
                "Failed to update device capabilities: {} ({})",
                status, body_summary
            )));
        }

        tracing::info!("Device {} capabilities refreshed in Supabase", device_id);
        Ok(())
    }

    /// Upsert a repository to Supabase.
    ///
    /// Creates or updates the repository record.
    pub async fn upsert_repository(
        &self,
        id: &str,
        user_id: &str,
        device_id: &str,
        name: &str,
        local_path: &str,
        remote_url: Option<&str>,
        default_branch: Option<&str>,
        is_worktree: bool,
        worktree_branch: Option<&str>,
        access_token: &str,
    ) -> AuthResult<()> {
        // Use on_conflict to upsert based on the unique constraint (device_id, local_path)
        // rather than the primary key (id)
        let url = format!(
            "{}?on_conflict=device_id,local_path",
            self.rest_url("repositories")
        );

        let mut body = serde_json::json!({
            "id": id,
            "user_id": user_id,
            "device_id": device_id,
            "name": name,
            "local_path": local_path,
            "is_worktree": is_worktree,
            "status": "active"
        });

        if let Some(url) = remote_url {
            body["remote_url"] = serde_json::json!(url);
        }
        if let Some(branch) = default_branch {
            body["default_branch"] = serde_json::json!(branch);
        }
        if let Some(branch) = worktree_branch {
            body["worktree_branch"] = serde_json::json!(branch);
        }

        tracing::debug!("Upserting repository {} to Supabase", id);

        let response = self
            .http_client
            .post(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates")
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status, body_summary = %body_summary, "Failed to upsert repository");
            return Err(AuthError::OAuth(format!(
                "Failed to upsert repository: {} ({})",
                status, body_summary
            )));
        }

        tracing::debug!("Repository {} upserted to Supabase", id);
        Ok(())
    }

    /// Upsert a coding session to Supabase.
    ///
    /// Creates or updates the session record.
    pub async fn upsert_coding_session(
        &self,
        id: &str,
        user_id: &str,
        device_id: &str,
        repository_id: &str,
        status: &str,
        title: Option<&str>,
        current_branch: Option<&str>,
        working_directory: Option<&str>,
        is_worktree: bool,
        worktree_path: Option<&str>,
        access_token: &str,
    ) -> AuthResult<()> {
        let url = self.rest_url("agent_coding_sessions");

        let now = chrono::Utc::now().to_rfc3339();

        let mut body = serde_json::json!({
            "id": id,
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
        if let Some(title) = title {
            body["title"] = serde_json::json!(title);
        }
        if let Some(dir) = working_directory {
            body["working_directory"] = serde_json::json!(dir);
        }
        if let Some(path) = worktree_path {
            body["worktree_path"] = serde_json::json!(path);
        }

        tracing::debug!("Upserting coding session {} to Supabase", id);

        let response = self
            .http_client
            .post(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates")
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let status_code = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status_code, body_summary = %body_summary, "Failed to upsert coding session");
            return Err(AuthError::OAuth(format!(
                "Failed to upsert coding session: {} ({})",
                status_code, body_summary
            )));
        }

        tracing::debug!("Coding session {} upserted to Supabase", id);
        Ok(())
    }

    /// Insert encrypted session secrets for multiple devices.
    ///
    /// Uses batch insert for efficiency.
    ///
    /// # Arguments
    /// * `secrets` - List of encrypted secrets for each device
    /// * `access_token` - Supabase access token
    pub async fn insert_session_secrets(
        &self,
        secrets: Vec<CodingSessionSecretRecord>,
        access_token: &str,
    ) -> AuthResult<()> {
        if secrets.is_empty() {
            tracing::debug!("No secrets to insert");
            return Ok(());
        }

        let url = format!(
            "{}?on_conflict=session_id,device_id",
            self.rest_url("agent_coding_session_secrets")
        );

        let body: Vec<InsertSecretRequest> = secrets
            .into_iter()
            .map(|s| InsertSecretRequest {
                session_id: s.session_id,
                device_id: s.device_id,
                ephemeral_public_key: s.ephemeral_public_key,
                encrypted_secret: s.encrypted_secret,
            })
            .collect();

        tracing::debug!("Inserting {} session secrets to Supabase", body.len());

        let response = self
            .http_client
            .post(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .header("Prefer", "resolution=merge-duplicates")
            .json(&body)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body_text = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body_text);
            tracing::error!(
                status = %status,
                body_summary = %body_summary,
                "Failed to insert session secrets"
            );
            return Err(AuthError::OAuth(format!(
                "Failed to insert session secrets: {} ({})",
                status, body_summary
            )));
        }

        tracing::info!(
            "Successfully distributed session secrets to {} devices",
            body.len()
        );
        Ok(())
    }

    /// Fetch all session secrets encrypted for this device.
    ///
    /// # Arguments
    /// * `device_id` - This device's UUID
    /// * `access_token` - Supabase access token
    pub async fn fetch_session_secrets_for_device(
        &self,
        device_id: &str,
        access_token: &str,
    ) -> AuthResult<Vec<CodingSessionSecretRecord>> {
        let url = format!(
            "{}?device_id=eq.{}&select=session_id,device_id,ephemeral_public_key,encrypted_secret",
            self.rest_url("agent_coding_session_secrets"),
            device_id
        );

        tracing::debug!("Fetching session secrets for device {}", device_id);

        let response = self
            .http_client
            .get(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Accept", "application/json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status = %status, body_summary = %body_summary, "Failed to fetch session secrets");
            return Err(AuthError::OAuth(format!(
                "Failed to fetch session secrets: {} ({})",
                status, body_summary
            )));
        }

        let secrets: Vec<CodingSessionSecretRecord> = response.json().await?;
        tracing::debug!("Fetched {} session secrets for device", secrets.len());
        Ok(secrets)
    }

    /// Delete session secrets for a specific session (cleanup).
    ///
    /// # Arguments
    /// * `session_id` - The session UUID
    /// * `access_token` - Supabase access token
    pub async fn delete_session_secrets(
        &self,
        session_id: &str,
        access_token: &str,
    ) -> AuthResult<()> {
        let url = format!(
            "{}?session_id=eq.{}",
            self.rest_url("agent_coding_session_secrets"),
            session_id
        );

        tracing::debug!("Deleting session secrets for session {}", session_id);

        let response = self
            .http_client
            .delete(&url)
            .header("apikey", &self.anon_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::warn!(
                status = %status,
                body_summary = %body_summary,
                "Failed to delete session secrets"
            );
            // Don't fail on delete errors
        }

        Ok(())
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
            client.rest_url("devices"),
            "https://test.supabase.co/rest/v1/devices"
        );
    }

    #[test]
    fn test_device_info_serialization() {
        let device = DeviceInfo {
            id: "device-123".to_string(),
            user_id: "user-456".to_string(),
            device_type: "daemon".to_string(),
            name: "My MacBook".to_string(),
            public_key: Some("base64key".to_string()),
            is_active: true,
        };

        let json = serde_json::to_string(&device).unwrap();
        assert!(json.contains("device-123"));
        assert!(json.contains("daemon"));
    }

    #[test]
    fn test_session_secret_serialization() {
        let secret = CodingSessionSecretRecord {
            session_id: "session-123".to_string(),
            device_id: "device-456".to_string(),
            ephemeral_public_key: "ephemeral-key".to_string(),
            encrypted_secret: "encrypted-data".to_string(),
        };

        let json = serde_json::to_string(&secret).unwrap();
        assert!(json.contains("session-123"));
        assert!(json.contains("encrypted-data"));
    }
}
