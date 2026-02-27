//! OAuth callback server for browser-based authentication.

use crate::{AuthError, AuthResult};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::sync::oneshot;
use tracing::{debug, error, info};

/// Default OAuth callback port.
pub const DEFAULT_OAUTH_PORT: u16 = 9876;

/// Default OAuth timeout in seconds.
pub const DEFAULT_OAUTH_TIMEOUT_SECS: u64 = 120;

/// OAuth callback result.
#[derive(Debug, Clone)]
pub struct OAuthResult {
    /// Whether authentication succeeded.
    pub success: bool,
    /// Access token (if successful).
    pub access_token: Option<String>,
    /// Refresh token (if successful).
    pub refresh_token: Option<String>,
    /// User ID (if successful).
    pub user_id: Option<String>,
    /// User email (if successful).
    pub email: Option<String>,
    /// Expiration time in seconds (if successful).
    pub expires_in: Option<i64>,
    /// Error message (if failed).
    pub error: Option<String>,
}

impl OAuthResult {
    /// Create a successful result.
    pub fn success(
        access_token: String,
        refresh_token: String,
        user_id: String,
        email: Option<String>,
        expires_in: i64,
    ) -> Self {
        Self {
            success: true,
            access_token: Some(access_token),
            refresh_token: Some(refresh_token),
            user_id: Some(user_id),
            email,
            expires_in: Some(expires_in),
            error: None,
        }
    }

    /// Create a failed result.
    pub fn failure(error: String) -> Self {
        Self {
            success: false,
            access_token: None,
            refresh_token: None,
            user_id: None,
            email: None,
            expires_in: None,
            error: Some(error),
        }
    }
}

/// OAuth callback server that listens for the authentication redirect.
pub struct OAuthCallbackServer {
    port: u16,
    timeout_secs: u64,
}

impl OAuthCallbackServer {
    /// Create a new OAuth callback server.
    pub fn new(port: u16, timeout_secs: u64) -> Self {
        Self { port, timeout_secs }
    }

    /// Create with default settings.
    pub fn with_defaults() -> Self {
        Self::new(DEFAULT_OAUTH_PORT, DEFAULT_OAUTH_TIMEOUT_SECS)
    }

    /// Get the callback URL for this server.
    pub fn callback_url(&self) -> String {
        format!("http://localhost:{}/callback", self.port)
    }

    /// Get the full OAuth start URL.
    pub fn auth_url(&self, api_url: &str) -> String {
        let callback = self.callback_url();
        let encoded_callback = urlencoding_encode(&callback);
        format!("{}/auth/cli?callback={}", api_url, encoded_callback)
    }

    /// Start the server and wait for the OAuth callback.
    ///
    /// This method will:
    /// 1. Start a local HTTP server on the configured port
    /// 2. Wait for a callback request with auth tokens
    /// 3. Return the result and shut down the server
    ///
    /// The caller is responsible for opening the browser to the auth URL.
    pub async fn wait_for_callback(&self) -> AuthResult<OAuthResult> {
        let addr = format!("127.0.0.1:{}", self.port);
        let listener = TcpListener::bind(&addr)
            .await
            .map_err(|e| AuthError::OAuth(format!("Failed to bind to {}: {}", addr, e)))?;

        info!(port = self.port, "OAuth callback server listening");

        // Create a channel to receive the result
        let (tx, rx) = oneshot::channel::<OAuthResult>();
        let tx = Arc::new(tokio::sync::Mutex::new(Some(tx)));

        // Spawn the server task
        let server_handle = tokio::spawn({
            let tx = tx.clone();
            async move {
                loop {
                    match listener.accept().await {
                        Ok((mut socket, _)) => {
                            let tx = tx.clone();
                            tokio::spawn(async move {
                                if let Err(e) = handle_connection(&mut socket, tx).await {
                                    error!("Error handling connection: {}", e);
                                }
                            });
                        }
                        Err(e) => {
                            error!("Accept error: {}", e);
                            break;
                        }
                    }
                }
            }
        });

        // Wait for result with timeout
        let timeout = tokio::time::Duration::from_secs(self.timeout_secs);
        let result = match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => OAuthResult::failure("Internal error: channel closed".to_string()),
            Err(_) => OAuthResult::failure("OAuth timeout".to_string()),
        };

        // Abort the server
        server_handle.abort();

        Ok(result)
    }
}

/// Handle an incoming HTTP connection.
async fn handle_connection(
    socket: &mut tokio::net::TcpStream,
    tx: Arc<tokio::sync::Mutex<Option<oneshot::Sender<OAuthResult>>>>,
) -> AuthResult<()> {
    let (reader, mut writer) = socket.split();
    let mut reader = BufReader::new(reader);
    let mut request_line = String::new();
    reader.read_line(&mut request_line).await?;

    debug!(request = %request_line.trim(), "Received request");

    // Parse the request line: GET /callback?... HTTP/1.1
    if !request_line.starts_with("GET ") {
        send_response(&mut writer, 405, "Method Not Allowed", "Method Not Allowed").await?;
        return Ok(());
    }

    let path_end = request_line.find(" HTTP/").unwrap_or(request_line.len());
    let path = &request_line[4..path_end];

    if !path.starts_with("/callback") {
        send_response(&mut writer, 404, "Not Found", "Not Found").await?;
        return Ok(());
    }

    // Parse query parameters
    let query = if let Some(idx) = path.find('?') {
        &path[idx + 1..]
    } else {
        ""
    };

    let params: std::collections::HashMap<String, String> = query
        .split('&')
        .filter_map(|pair| {
            let mut parts = pair.splitn(2, '=');
            let key = parts.next()?.to_string();
            let value = parts.next().unwrap_or("").to_string();
            Some((key, urlencoding_decode(&value)))
        })
        .collect();

    // Extract parameters
    let access_token = params.get("access_token").cloned();
    let refresh_token = params.get("refresh_token").cloned();
    let user_id = params.get("user_id").cloned();
    let email = params.get("email").cloned();
    let expires_in = params.get("expires_in").and_then(|s| s.parse().ok());
    let error = params.get("error").cloned();

    // Build result
    let result = if let Some(err) = error {
        send_response(&mut writer, 200, "OK", &error_page(&err)).await?;
        OAuthResult::failure(err)
    } else if let (Some(token), Some(refresh), Some(uid)) = (access_token, refresh_token, user_id) {
        send_response(&mut writer, 200, "OK", &success_page()).await?;
        OAuthResult::success(token, refresh, uid, email, expires_in.unwrap_or(3600))
    } else {
        send_response(
            &mut writer,
            200,
            "OK",
            &error_page("Missing required parameters"),
        )
        .await?;
        OAuthResult::failure("Missing required parameters".to_string())
    };

    // Send result through channel
    if let Some(tx) = tx.lock().await.take() {
        let _ = tx.send(result);
    }

    Ok(())
}

/// Send an HTTP response.
async fn send_response(
    writer: &mut tokio::net::tcp::WriteHalf<'_>,
    status_code: u16,
    status_text: &str,
    body: &str,
) -> AuthResult<()> {
    let response = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        status_code,
        status_text,
        body.len(),
        body
    );
    writer.write_all(response.as_bytes()).await?;
    writer.flush().await?;
    Ok(())
}

/// Generate success page HTML.
fn success_page() -> String {
    r#"<!DOCTYPE html>
<html>
<head><title>Unbound - Authentication Successful</title></head>
<body style="font-family: system-ui; text-align: center; padding: 50px; background: #f5f5f5;">
<div style="max-width: 400px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
<h1 style="color: #22c55e; margin-bottom: 20px;">Authentication Successful!</h1>
<p style="color: #666;">You can close this window and return to the terminal.</p>
</div>
<script>setTimeout(() => window.close(), 2000);</script>
</body>
</html>"#.to_string()
}

/// Generate error page HTML.
fn error_page(error: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html>
<head><title>Unbound - Authentication Failed</title></head>
<body style="font-family: system-ui; text-align: center; padding: 50px; background: #f5f5f5;">
<div style="max-width: 400px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
<h1 style="color: #ef4444; margin-bottom: 20px;">Authentication Failed</h1>
<p style="color: #666;">Error: {}</p>
<p style="color: #888; font-size: 14px;">You can close this window and try again.</p>
</div>
</body>
</html>"#,
        error
    )
}

/// Simple URL encoding.
fn urlencoding_encode(s: &str) -> String {
    let mut result = String::new();
    for c in s.chars() {
        match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => result.push(c),
            _ => {
                for byte in c.to_string().as_bytes() {
                    result.push_str(&format!("%{:02X}", byte));
                }
            }
        }
    }
    result
}

/// Simple URL decoding.
fn urlencoding_decode(s: &str) -> String {
    let mut result = Vec::new();
    let mut chars = s.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '%' {
            let hex: String = chars.by_ref().take(2).collect();
            if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                result.push(byte);
            }
        } else if c == '+' {
            result.push(b' ');
        } else {
            result.push(c as u8);
        }
    }

    String::from_utf8_lossy(&result).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_callback_url() {
        let server = OAuthCallbackServer::new(9876, 120);
        assert_eq!(server.callback_url(), "http://localhost:9876/callback");
    }

    #[test]
    fn test_auth_url() {
        let server = OAuthCallbackServer::new(9876, 120);
        let auth_url = server.auth_url("https://app.unbound.computer");
        assert!(auth_url.contains("/auth/cli?callback="));
        assert!(auth_url.contains("http%3A%2F%2Flocalhost%3A9876%2Fcallback"));
    }

    #[test]
    fn test_urlencoding() {
        let encoded = urlencoding_encode("http://localhost:9876/callback");
        assert_eq!(encoded, "http%3A%2F%2Flocalhost%3A9876%2Fcallback");

        let decoded = urlencoding_decode("http%3A%2F%2Flocalhost%3A9876%2Fcallback");
        assert_eq!(decoded, "http://localhost:9876/callback");
    }

    #[test]
    fn test_oauth_result_success() {
        let result = OAuthResult::success(
            "access".to_string(),
            "refresh".to_string(),
            "user123".to_string(),
            Some("user@example.com".to_string()),
            3600,
        );
        assert!(result.success);
        assert_eq!(result.access_token, Some("access".to_string()));
        assert_eq!(result.user_id, Some("user123".to_string()));
        assert_eq!(result.email, Some("user@example.com".to_string()));
    }

    #[test]
    fn test_oauth_result_failure() {
        let result = OAuthResult::failure("test error".to_string());
        assert!(!result.success);
        assert!(result.access_token.is_none());
        assert_eq!(result.error, Some("test error".to_string()));
    }

    #[test]
    fn test_oauth_result_fields() {
        let result = OAuthResult::success(
            "my-access-token".to_string(),
            "my-refresh-token".to_string(),
            "user-id-123".to_string(),
            Some("test@example.com".to_string()),
            7200,
        );

        assert!(result.success);
        assert_eq!(result.access_token.unwrap(), "my-access-token");
        assert_eq!(result.refresh_token.unwrap(), "my-refresh-token");
        assert_eq!(result.user_id.unwrap(), "user-id-123");
        assert_eq!(result.email.unwrap(), "test@example.com");
        assert_eq!(result.expires_in.unwrap(), 7200);
        assert!(result.error.is_none());
    }

    #[test]
    fn test_oauth_result_failure_fields() {
        let result = OAuthResult::failure("access_denied".to_string());

        assert!(!result.success);
        assert!(result.access_token.is_none());
        assert!(result.refresh_token.is_none());
        assert!(result.user_id.is_none());
        assert!(result.expires_in.is_none());
        assert_eq!(result.error.unwrap(), "access_denied");
    }

    #[test]
    fn test_callback_url_with_different_ports() {
        // Default port
        let server1 = OAuthCallbackServer::new(DEFAULT_OAUTH_PORT, DEFAULT_OAUTH_TIMEOUT_SECS);
        assert_eq!(server1.callback_url(), "http://localhost:9876/callback");

        // Custom port
        let server2 = OAuthCallbackServer::new(8080, 60);
        assert_eq!(server2.callback_url(), "http://localhost:8080/callback");

        // Another custom port
        let server3 = OAuthCallbackServer::new(3000, 300);
        assert_eq!(server3.callback_url(), "http://localhost:3000/callback");
    }

    #[test]
    fn test_oauth_server_with_defaults() {
        let server = OAuthCallbackServer::with_defaults();
        assert_eq!(
            server.callback_url(),
            format!("http://localhost:{}/callback", DEFAULT_OAUTH_PORT)
        );
    }

    #[test]
    fn test_auth_url_encoding() {
        let server = OAuthCallbackServer::new(9999, 120);
        let auth_url = server.auth_url("https://example.com");

        // Should contain the base URL
        assert!(auth_url.starts_with("https://example.com/auth/cli?callback="));

        // Callback should be URL encoded
        assert!(auth_url.contains("localhost%3A9999"));
    }

    #[test]
    fn test_urlencoding_special_chars() {
        // Test various characters
        let encoded = urlencoding_encode("hello world");
        assert!(encoded.contains("%20")); // space

        let encoded = urlencoding_encode("key=value&other=test");
        assert!(encoded.contains("%3D")); // =
        assert!(encoded.contains("%26")); // &
    }

    #[test]
    fn test_urlencoding_decode_plus() {
        // Plus should decode to space
        let decoded = urlencoding_decode("hello+world");
        assert_eq!(decoded, "hello world");
    }

    #[test]
    fn test_default_constants() {
        assert_eq!(DEFAULT_OAUTH_PORT, 9876);
        assert_eq!(DEFAULT_OAUTH_TIMEOUT_SECS, 120);
    }
}
