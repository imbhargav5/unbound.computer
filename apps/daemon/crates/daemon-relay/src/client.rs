//! WebSocket relay client.

use crate::{RelayError, RelayMessage, RelayMessageType, RelayResult};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, Mutex, RwLock};
use tokio::time::{interval, Duration};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

/// Relay client configuration.
#[derive(Debug, Clone)]
pub struct RelayConfig {
    /// Relay server URL (e.g., wss://relay.unbound.computer).
    pub url: String,
    /// Heartbeat interval in seconds.
    pub heartbeat_interval_secs: u64,
    /// Base reconnect delay in seconds.
    pub reconnect_base_delay_secs: u64,
    /// Maximum reconnect delay in seconds.
    pub reconnect_max_delay_secs: u64,
    /// Maximum reconnect attempts.
    pub max_reconnect_attempts: u32,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            url: "wss://relay.unbound.computer".to_string(),
            heartbeat_interval_secs: 30,
            reconnect_base_delay_secs: 2,
            reconnect_max_delay_secs: 30,
            max_reconnect_attempts: 10,
        }
    }
}

/// Connection state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Authenticating,
    Connected,
}

/// Events emitted by the relay client.
#[derive(Debug, Clone)]
pub enum RelayEvent {
    /// Connected to relay.
    Connected,
    /// Disconnected from relay.
    Disconnected(Option<String>),
    /// Authentication succeeded.
    Authenticated,
    /// Authentication failed.
    AuthenticationFailed(String),
    /// Joined a session.
    SessionJoined(String),
    /// Left a session.
    SessionLeft(String),
    /// Received a message.
    Message(RelayMessage),
    /// Error occurred.
    Error(String),
}

/// WebSocket relay client with automatic reconnection.
pub struct RelayClient {
    config: RelayConfig,
    state: Arc<RwLock<ConnectionState>>,
    current_session: Arc<RwLock<Option<String>>>,
    sender: Arc<Mutex<Option<mpsc::Sender<Message>>>>,
    event_tx: broadcast::Sender<RelayEvent>,
    auth_token: Arc<RwLock<Option<String>>>,
    device_id: Arc<RwLock<Option<String>>>,
    reconnect_attempts: Arc<RwLock<u32>>,
}

impl RelayClient {
    /// Create a new relay client with the given configuration.
    pub fn new(config: RelayConfig) -> Self {
        let (event_tx, _) = broadcast::channel(100);

        Self {
            config,
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            current_session: Arc::new(RwLock::new(None)),
            sender: Arc::new(Mutex::new(None)),
            event_tx,
            auth_token: Arc::new(RwLock::new(None)),
            device_id: Arc::new(RwLock::new(None)),
            reconnect_attempts: Arc::new(RwLock::new(0)),
        }
    }

    /// Create with default configuration.
    pub fn with_defaults() -> Self {
        Self::new(RelayConfig::default())
    }

    /// Subscribe to relay events.
    pub fn subscribe(&self) -> broadcast::Receiver<RelayEvent> {
        self.event_tx.subscribe()
    }

    /// Get the current connection state.
    pub async fn state(&self) -> ConnectionState {
        *self.state.read().await
    }

    /// Check if connected.
    pub async fn is_connected(&self) -> bool {
        *self.state.read().await == ConnectionState::Connected
    }

    /// Get the current session ID.
    pub async fn current_session(&self) -> Option<String> {
        self.current_session.read().await.clone()
    }

    /// Connect to the relay server.
    pub async fn connect(&self, auth_token: &str, device_id: &str) -> RelayResult<()> {
        let current_state = *self.state.read().await;
        if current_state != ConnectionState::Disconnected {
            debug!("Already connecting or connected");
            return Ok(());
        }

        // Store credentials for reconnection
        *self.auth_token.write().await = Some(auth_token.to_string());
        *self.device_id.write().await = Some(device_id.to_string());

        self.do_connect().await
    }

    /// Internal connect implementation.
    async fn do_connect(&self) -> RelayResult<()> {
        *self.state.write().await = ConnectionState::Connecting;
        info!(url = %self.config.url, "Connecting to relay");

        // Connect to WebSocket
        let (ws_stream, _) = connect_async(&self.config.url).await?;
        let (mut write, mut read) = ws_stream.split();

        // Create message channel
        let (msg_tx, mut msg_rx) = mpsc::channel::<Message>(100);
        *self.sender.lock().await = Some(msg_tx.clone());

        *self.state.write().await = ConnectionState::Authenticating;

        // Send authentication
        let auth_token = self.auth_token.read().await.clone()
            .ok_or_else(|| RelayError::Authentication("No auth token".to_string()))?;
        let device_id = self.device_id.read().await.clone()
            .ok_or_else(|| RelayError::Authentication("No device ID".to_string()))?;

        let auth_msg = RelayMessage::auth(&auth_token, &device_id);
        let auth_json = auth_msg.to_json()?;
        write.send(Message::Text(auth_json.into())).await?;
        debug!("Sent AUTH message");

        // Spawn message sender task
        let sender_handle = tokio::spawn(async move {
            while let Some(msg) = msg_rx.recv().await {
                if write.send(msg).await.is_err() {
                    break;
                }
            }
        });

        // Spawn heartbeat task
        let heartbeat_sender = msg_tx.clone();
        let heartbeat_interval = self.config.heartbeat_interval_secs;
        let heartbeat_handle = tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(heartbeat_interval));
            loop {
                interval.tick().await;
                let heartbeat = RelayMessage::heartbeat();
                if let Ok(json) = heartbeat.to_json() {
                    if heartbeat_sender.send(Message::Text(json.into())).await.is_err() {
                        break;
                    }
                }
            }
        });

        // Process incoming messages
        let state = self.state.clone();
        let event_tx = self.event_tx.clone();
        let current_session = self.current_session.clone();
        let reconnect_attempts = self.reconnect_attempts.clone();

        while let Some(msg_result) = read.next().await {
            match msg_result {
                Ok(Message::Text(text)) => {
                    match RelayMessage::from_json(&text) {
                        Ok(relay_msg) => {
                            self.handle_message(&relay_msg, &state, &event_tx, &current_session, &reconnect_attempts).await;
                        }
                        Err(e) => {
                            warn!(error = %e, "Failed to parse relay message");
                        }
                    }
                }
                Ok(Message::Close(_)) => {
                    info!("Relay connection closed");
                    break;
                }
                Ok(Message::Ping(data)) => {
                    if let Some(sender) = self.sender.lock().await.as_ref() {
                        let _ = sender.send(Message::Pong(data)).await;
                    }
                }
                Ok(_) => {}
                Err(e) => {
                    error!(error = %e, "WebSocket error");
                    break;
                }
            }
        }

        // Cleanup
        heartbeat_handle.abort();
        sender_handle.abort();
        *self.sender.lock().await = None;
        *self.state.write().await = ConnectionState::Disconnected;
        *self.current_session.write().await = None;

        let _ = self.event_tx.send(RelayEvent::Disconnected(None));

        // Attempt reconnection
        self.schedule_reconnect().await;

        Ok(())
    }

    /// Handle incoming relay message.
    async fn handle_message(
        &self,
        msg: &RelayMessage,
        state: &Arc<RwLock<ConnectionState>>,
        event_tx: &broadcast::Sender<RelayEvent>,
        current_session: &Arc<RwLock<Option<String>>>,
        reconnect_attempts: &Arc<RwLock<u32>>,
    ) {
        match msg.msg_type {
            RelayMessageType::AuthResult => {
                if msg.success == Some(true) {
                    *state.write().await = ConnectionState::Connected;
                    *reconnect_attempts.write().await = 0;
                    info!("Authenticated with relay");
                    let _ = event_tx.send(RelayEvent::Authenticated);
                    let _ = event_tx.send(RelayEvent::Connected);
                } else {
                    let error = msg.error.clone().unwrap_or_else(|| "Unknown error".to_string());
                    *state.write().await = ConnectionState::Disconnected;
                    error!(error = %error, "Authentication failed");
                    let _ = event_tx.send(RelayEvent::AuthenticationFailed(error));
                }
            }
            RelayMessageType::Subscribed => {
                if let Some(session_id) = &msg.session_id {
                    *current_session.write().await = Some(session_id.clone());
                    info!(session_id = %session_id, "Joined session");
                    let _ = event_tx.send(RelayEvent::SessionJoined(session_id.clone()));
                }
            }
            RelayMessageType::Unsubscribed => {
                if let Some(session_id) = &msg.session_id {
                    if current_session.read().await.as_deref() == Some(session_id) {
                        *current_session.write().await = None;
                    }
                    info!(session_id = %session_id, "Left session");
                    let _ = event_tx.send(RelayEvent::SessionLeft(session_id.clone()));
                }
            }
            RelayMessageType::Error => {
                let error = msg.error.clone().unwrap_or_else(|| "Unknown error".to_string());
                warn!(error = %error, "Relay error");
                let _ = event_tx.send(RelayEvent::Error(error));
            }
            _ => {
                debug!(msg_type = ?msg.msg_type, "Received message");
                let _ = event_tx.send(RelayEvent::Message(msg.clone()));
            }
        }
    }

    /// Schedule automatic reconnection.
    async fn schedule_reconnect(&self) {
        let mut attempts = self.reconnect_attempts.write().await;
        *attempts += 1;

        if *attempts > self.config.max_reconnect_attempts {
            warn!("Max reconnect attempts reached");
            return;
        }

        // Calculate delay with exponential backoff
        let delay = std::cmp::min(
            self.config.reconnect_base_delay_secs * 2u64.pow(*attempts - 1),
            self.config.reconnect_max_delay_secs,
        );

        info!(attempt = *attempts, delay_secs = delay, "Scheduling reconnect");

        drop(attempts);

        tokio::time::sleep(Duration::from_secs(delay)).await;

        if self.auth_token.read().await.is_some() {
            if let Err(e) = Box::pin(self.do_connect()).await {
                error!(error = %e, "Reconnect failed");
            }
        }
    }

    /// Disconnect from the relay.
    pub async fn disconnect(&self) {
        *self.reconnect_attempts.write().await = self.config.max_reconnect_attempts + 1;

        if let Some(sender) = self.sender.lock().await.take() {
            drop(sender);
        }

        *self.state.write().await = ConnectionState::Disconnected;
        *self.current_session.write().await = None;
        *self.auth_token.write().await = None;
        *self.device_id.write().await = None;

        info!("Disconnected from relay");
        let _ = self.event_tx.send(RelayEvent::Disconnected(Some("User disconnected".to_string())));
    }

    /// Join a session.
    pub async fn join_session(&self, session_id: &str) -> RelayResult<()> {
        if !self.is_connected().await {
            return Err(RelayError::NotConnected);
        }

        let msg = RelayMessage::join_session(session_id);
        self.send_message(msg).await
    }

    /// Leave the current session.
    pub async fn leave_session(&self) -> RelayResult<()> {
        if !self.is_connected().await {
            return Err(RelayError::NotConnected);
        }

        let session_id = self.current_session.read().await.clone()
            .ok_or_else(|| RelayError::Session("Not in a session".to_string()))?;

        let msg = RelayMessage::leave_session(&session_id);
        self.send_message(msg).await
    }

    /// Send a message to the relay.
    pub async fn send_message(&self, msg: RelayMessage) -> RelayResult<()> {
        let sender = self.sender.lock().await;
        let sender = sender.as_ref().ok_or(RelayError::NotConnected)?;

        let json = msg.to_json()?;
        sender.send(Message::Text(json.into())).await
            .map_err(|e| RelayError::Send(e.to_string()))
    }

    /// Send raw JSON to the relay.
    pub async fn send_raw(&self, json: &str) -> RelayResult<()> {
        let sender = self.sender.lock().await;
        let sender = sender.as_ref().ok_or(RelayError::NotConnected)?;

        sender.send(Message::Text(json.to_string().into())).await
            .map_err(|e| RelayError::Send(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_relay_config_default() {
        let config = RelayConfig::default();
        assert_eq!(config.heartbeat_interval_secs, 30);
        assert_eq!(config.reconnect_base_delay_secs, 2);
        assert_eq!(config.reconnect_max_delay_secs, 30);
        assert_eq!(config.max_reconnect_attempts, 10);
        assert_eq!(config.url, "wss://relay.unbound.computer");
    }

    #[tokio::test]
    async fn test_relay_client_initial_state() {
        let client = RelayClient::with_defaults();
        assert_eq!(client.state().await, ConnectionState::Disconnected);
        assert!(!client.is_connected().await);
        assert!(client.current_session().await.is_none());
    }

    #[test]
    fn test_relay_client_state_transitions() {
        // Verify all state enum values exist and are distinct
        let states = vec![
            ConnectionState::Disconnected,
            ConnectionState::Connecting,
            ConnectionState::Authenticating,
            ConnectionState::Connected,
        ];

        // All states should be different
        assert_ne!(states[0], states[1]);
        assert_ne!(states[1], states[2]);
        assert_ne!(states[2], states[3]);
        assert_ne!(states[0], states[3]);
    }

    #[test]
    fn test_relay_reconnect_config() {
        let config = RelayConfig {
            url: "wss://custom.relay.com".to_string(),
            heartbeat_interval_secs: 60,
            reconnect_base_delay_secs: 5,
            reconnect_max_delay_secs: 120,
            max_reconnect_attempts: 20,
        };

        assert_eq!(config.url, "wss://custom.relay.com");
        assert_eq!(config.heartbeat_interval_secs, 60);
        assert_eq!(config.reconnect_base_delay_secs, 5);
        assert_eq!(config.reconnect_max_delay_secs, 120);
        assert_eq!(config.max_reconnect_attempts, 20);
    }

    #[test]
    fn test_relay_client_with_custom_config() {
        let config = RelayConfig {
            url: "wss://custom.example.com".to_string(),
            ..Default::default()
        };

        assert_eq!(config.url, "wss://custom.example.com");
        // Other fields should have defaults
        assert_eq!(config.heartbeat_interval_secs, 30);

        let client = RelayClient::new(config);
        // Client should be created with custom config
        assert!(true);
    }

    #[tokio::test]
    async fn test_relay_client_subscribe() {
        let client = RelayClient::with_defaults();
        let _receiver = client.subscribe();
        // Should be able to subscribe without error
        assert!(true);
    }

    #[tokio::test]
    async fn test_relay_client_not_connected_error() {
        let client = RelayClient::with_defaults();

        // Join session should fail when not connected
        let result = client.join_session("session-123").await;
        assert!(result.is_err());

        // Leave session should fail when not connected
        let result = client.leave_session().await;
        assert!(result.is_err());
    }

    #[test]
    fn test_relay_event_variants() {
        // Test creating different event types
        let connected = RelayEvent::Connected;
        let disconnected = RelayEvent::Disconnected(Some("reason".to_string()));
        let authenticated = RelayEvent::Authenticated;
        let auth_failed = RelayEvent::AuthenticationFailed("bad token".to_string());
        let session_joined = RelayEvent::SessionJoined("session-1".to_string());
        let session_left = RelayEvent::SessionLeft("session-1".to_string());
        let error = RelayEvent::Error("something went wrong".to_string());

        // Verify they can be created (compile-time check)
        match connected {
            RelayEvent::Connected => assert!(true),
            _ => panic!("Wrong variant"),
        }
        match disconnected {
            RelayEvent::Disconnected(Some(reason)) => assert_eq!(reason, "reason"),
            _ => panic!("Wrong variant"),
        }
        match authenticated {
            RelayEvent::Authenticated => assert!(true),
            _ => panic!("Wrong variant"),
        }
        match auth_failed {
            RelayEvent::AuthenticationFailed(msg) => assert_eq!(msg, "bad token"),
            _ => panic!("Wrong variant"),
        }
        match session_joined {
            RelayEvent::SessionJoined(id) => assert_eq!(id, "session-1"),
            _ => panic!("Wrong variant"),
        }
        match session_left {
            RelayEvent::SessionLeft(id) => assert_eq!(id, "session-1"),
            _ => panic!("Wrong variant"),
        }
        match error {
            RelayEvent::Error(msg) => assert_eq!(msg, "something went wrong"),
            _ => panic!("Wrong variant"),
        }
    }

    #[tokio::test]
    async fn test_relay_client_disconnect_when_not_connected() {
        let client = RelayClient::with_defaults();

        // Disconnect when already disconnected should not panic
        client.disconnect().await;
        assert_eq!(client.state().await, ConnectionState::Disconnected);
    }

    #[test]
    fn test_relay_config_clone() {
        let config = RelayConfig::default();
        let cloned = config.clone();

        assert_eq!(config.url, cloned.url);
        assert_eq!(config.heartbeat_interval_secs, cloned.heartbeat_interval_secs);
    }
}
