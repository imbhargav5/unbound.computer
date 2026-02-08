//! Secret management utilities.

use crate::app::DaemonState;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use daemon_storage::SecretsManager;
use tracing::{debug, info, warn};

/// Load session secrets from Supabase into the memory cache.
///
/// This fetches all session secrets encrypted for this device from Supabase,
/// decrypts them using hybrid encryption, and caches them in memory.
pub async fn load_session_secrets_from_supabase(state: &DaemonState) -> Result<usize, String> {
    let device_id = match state.device_id.lock().unwrap().clone() {
        Some(id) => id,
        None => {
            debug!("No device ID - skipping Supabase session secret loading");
            return Ok(0);
        }
    };

    let device_private_key = match *state.device_private_key.lock().unwrap() {
        Some(key) => key,
        None => {
            debug!("No device private key - skipping Supabase session secret loading");
            return Ok(0);
        }
    };

    // Get access token
    let access_token = {
        let secrets = state.secrets.lock().unwrap();
        match secrets.get_supabase_access_token() {
            Ok(Some(token)) => token,
            Ok(None) => {
                debug!("No Supabase session - skipping session secret loading");
                return Ok(0);
            }
            Err(e) => return Err(format!("Failed to get access token: {}", e)),
        }
    };

    // Fetch all secrets for this device
    let records = state
        .supabase_client
        .fetch_session_secrets_for_device(&device_id, &access_token)
        .await
        .map_err(|e| format!("Failed to fetch session secrets: {}", e))?;

    if records.is_empty() {
        debug!("No session secrets found in Supabase for this device");
        return Ok(0);
    }

    // Decrypt each secret and cache in memory
    let mut loaded = 0;

    for record in records {
        // Decode base64 fields
        let ephemeral_key: [u8; 32] = match BASE64.decode(&record.ephemeral_public_key) {
            Ok(bytes) if bytes.len() == 32 => bytes.try_into().unwrap(),
            Ok(_) => {
                warn!(session_id = %record.session_id, "Invalid ephemeral key length");
                continue;
            }
            Err(e) => {
                warn!(session_id = %record.session_id, "Failed to decode ephemeral key: {}", e);
                continue;
            }
        };

        let encrypted_data = match BASE64.decode(&record.encrypted_secret) {
            Ok(bytes) => bytes,
            Err(e) => {
                warn!(session_id = %record.session_id, "Failed to decode encrypted secret: {}", e);
                continue;
            }
        };

        // Decrypt using hybrid crypto
        let plaintext = match daemon_config_and_utils::decrypt_for_device(
            &ephemeral_key,
            &encrypted_data,
            &device_private_key,
            &record.session_id,
        ) {
            Ok(bytes) => bytes,
            Err(e) => {
                warn!(session_id = %record.session_id, "Failed to decrypt session secret: {}", e);
                continue;
            }
        };

        // Parse the session secret string to get key bytes
        let secret_str = match String::from_utf8(plaintext) {
            Ok(s) => s,
            Err(e) => {
                warn!(session_id = %record.session_id, "Invalid session secret encoding: {}", e);
                continue;
            }
        };

        let key = match SecretsManager::parse_session_secret(&secret_str) {
            Ok(k) => k,
            Err(e) => {
                warn!(session_id = %record.session_id, "Failed to parse session secret: {}", e);
                continue;
            }
        };

        state.session_secret_cache.insert(&record.session_id, key);
        loaded += 1;
    }

    info!(
        "Loaded {} session secrets from Supabase into memory cache",
        loaded
    );
    Ok(loaded)
}
