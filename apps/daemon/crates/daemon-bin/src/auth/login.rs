//! Authentication login handler.

use crate::app::DaemonState;
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::{info, warn};

/// Register the auth login handler.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::AuthLogin, move |req| {
            let secrets = state.secrets.clone();
            let config = state.config.clone();
            let supabase_client = state.supabase_client.clone();
            let cached_db_key = state.db_encryption_key.clone();
            let cached_device_id = state.device_id.clone();
            let cached_device_private_key = state.device_private_key.clone();
            async move {
                let email = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("email"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let password = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("password"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let (Some(email), Some(password)) = (email, password) else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "email and password are required",
                    );
                };

                // Call Supabase Auth API directly
                let login_url =
                    format!("{}/auth/v1/token?grant_type=password", config.supabase_url);

                let client = reqwest::Client::new();
                let response = match client
                    .post(&login_url)
                    .header("apikey", &config.supabase_publishable_key)
                    .header("Content-Type", "application/json")
                    .json(&serde_json::json!({
                        "email": email,
                        "password": password,
                    }))
                    .send()
                    .await
                {
                    Ok(resp) => resp,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Request failed: {}", e),
                        );
                    }
                };

                if !response.status().is_success() {
                    let status = response.status();
                    let body = response.text().await.unwrap_or_default();
                    return Response::error(
                        &req.id,
                        error_codes::NOT_AUTHENTICATED,
                        &format!("Login failed ({}): {}", status, body),
                    );
                }

                #[derive(serde::Deserialize)]
                struct LoginResponse {
                    access_token: String,
                    refresh_token: String,
                    expires_in: i64,
                    user: LoginUser,
                }

                #[derive(serde::Deserialize)]
                struct LoginUser {
                    id: String,
                    #[serde(default)]
                    email: Option<String>,
                }

                let data: LoginResponse = match response.json().await {
                    Ok(d) => d,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Invalid response: {}", e),
                        );
                    }
                };

                info!(
                    user_id = %data.user.id,
                    email = ?data.user.email,
                    expires_in = data.expires_in,
                    "Supabase login successful"
                );

                // Calculate expiration time
                let expires_at =
                    chrono::Utc::now() + chrono::Duration::seconds(data.expires_in);
                let expires_at_str = expires_at.to_rfc3339();

                // Clone values for response before moving into spawn_blocking
                let user_id = data.user.id.clone();
                let user_email = data.user.email.clone();
                let expires_at_response = expires_at_str.clone();

                // Store tokens and set up device identity
                let access_token_for_supabase = data.access_token.clone();
                let user_id_for_device = data.user.id.clone();

                let device_setup = tokio::task::spawn_blocking(move || {
                    let secrets = secrets.lock().unwrap();

                    // Store session tokens
                    secrets.set_supabase_session(
                        &data.access_token,
                        &data.refresh_token,
                        &data.user.id,
                        data.user.email.as_deref(),
                        &expires_at_str,
                    )?;

                    // Get or generate device ID
                    let device_id = match secrets.get_device_id()? {
                        Some(id) => id,
                        None => {
                            let id = uuid::Uuid::new_v4().to_string();
                            secrets.set_device_id(&id)?;
                            info!("Generated new device ID: {}", id);
                            id
                        }
                    };

                    // Get or generate device private key
                    let private_key = secrets.ensure_device_private_key()?;

                    // Derive public key from private key
                    let private_key_arr: [u8; 32] = private_key.clone().try_into().map_err(
                        |_| {
                            daemon_storage::StorageError::Encoding(
                                "Invalid private key length".to_string(),
                            )
                        },
                    )?;
                    let public_key =
                        daemon_core::hybrid_crypto::public_key_from_private(&private_key_arr);
                    let public_key_b64 = base64::Engine::encode(
                        &base64::engine::general_purpose::STANDARD,
                        &public_key,
                    );

                    // Get the database encryption key (derived from device private key)
                    let db_encryption_key = secrets.get_database_encryption_key()?;

                    Ok::<(String, String, [u8; 32], Option<[u8; 32]>), daemon_storage::StorageError>(
                        (device_id, public_key_b64, private_key_arr, db_encryption_key),
                    )
                })
                .await
                .unwrap();

                let (device_id, public_key_b64, private_key_arr, db_encryption_key) =
                    match device_setup {
                        Ok(result) => result,
                        Err(e) => {
                            return Response::error(
                                &req.id,
                                error_codes::INTERNAL_ERROR,
                                &format!("Device setup failed: {}", e),
                            );
                        }
                    };

                // Update cached values in state
                *cached_device_id.lock().unwrap() = Some(device_id.clone());
                *cached_device_private_key.lock().unwrap() = Some(private_key_arr);
                *cached_db_key.lock().unwrap() = db_encryption_key;
                info!("Updated cached device identity and encryption keys after login");

                // Detect platform for device_type
                let device_type = if cfg!(target_os = "macos") {
                    "mac-desktop"
                } else if cfg!(target_os = "windows") {
                    "win-desktop"
                } else {
                    "linux-desktop"
                };

                let device_name = hostname::get()
                    .map(|h| h.to_string_lossy().to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());

                // Register device with Supabase (with the user's access token for auth)
                if let Err(e) = supabase_client
                    .upsert_device(
                        &device_id,
                        &user_id_for_device,
                        device_type,
                        &device_name,
                        &public_key_b64,
                        &access_token_for_supabase,
                    )
                    .await
                {
                    warn!("Failed to register device with Supabase: {}", e);
                    // Don't fail login - device can be registered later
                } else {
                    info!("Device registered with Supabase: {}", device_id);
                }

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "status": "logged_in",
                        "user_id": user_id,
                        "email": user_email,
                        "expires_at": expires_at_response,
                        "device_id": device_id,
                    }),
                )
            }
        })
        .await;
}
