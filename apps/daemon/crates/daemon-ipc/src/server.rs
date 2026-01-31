//! IPC server implementation.

use crate::{error_codes, Event, EventType, IpcError, IpcResult, Method, Request, Response};
use std::collections::HashMap;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{broadcast, mpsc, RwLock};
use tracing::{debug, error, info, warn};

/// Handler function type for IPC methods.
pub type HandlerFn = Box<
    dyn Fn(Request) -> Pin<Box<dyn Future<Output = Response> + Send>> + Send + Sync,
>;

/// Callback type for getting initial subscription state.
pub type InitialStateFn = Box<
    dyn Fn(String) -> Pin<Box<dyn Future<Output = Option<(Vec<Event>, i64)>> + Send>> + Send + Sync,
>;

/// Manages active subscriptions for streaming events.
#[derive(Clone)]
pub struct SubscriptionManager {
    /// Broadcast sender for each session - sends events to all subscribers.
    senders: Arc<RwLock<HashMap<String, broadcast::Sender<Event>>>>,
    /// Global broadcast channel for non-session events (SessionCreated, SessionDeleted, etc.).
    global_sender: broadcast::Sender<Event>,
}

impl SubscriptionManager {
    /// Create a new subscription manager.
    pub fn new() -> Self {
        let (global_sender, _) = broadcast::channel(100);
        Self {
            senders: Arc::new(RwLock::new(HashMap::new())),
            global_sender,
        }
    }

    /// Subscribe to a session's events. Returns a receiver for events.
    pub async fn subscribe(&self, session_id: &str) -> broadcast::Receiver<Event> {
        let mut senders = self.senders.write().await;
        let sender = senders
            .entry(session_id.to_string())
            .or_insert_with(|| {
                let (tx, _) = broadcast::channel(100);
                tx
            });
        sender.subscribe()
    }

    /// Broadcast an event to all subscribers of a session.
    pub async fn broadcast(&self, session_id: &str, event: Event) {
        let senders = self.senders.read().await;
        if let Some(sender) = senders.get(session_id) {
            // Ignore send errors (no subscribers)
            let _ = sender.send(event);
        }
    }

    /// Broadcast an event, creating the channel if it doesn't exist.
    pub async fn broadcast_or_create(&self, session_id: &str, event: Event) {
        let mut senders = self.senders.write().await;
        let sender = senders
            .entry(session_id.to_string())
            .or_insert_with(|| {
                let (tx, _) = broadcast::channel(100);
                tx
            });
        let _ = sender.send(event);
    }

    /// Remove a session's broadcast channel (when no more subscribers).
    pub async fn cleanup(&self, session_id: &str) {
        let mut senders = self.senders.write().await;
        if let Some(sender) = senders.get(session_id) {
            if sender.receiver_count() == 0 {
                senders.remove(session_id);
            }
        }
    }

    /// Subscribe to global events (SessionCreated, SessionDeleted, etc.).
    pub fn subscribe_global(&self) -> broadcast::Receiver<Event> {
        self.global_sender.subscribe()
    }

    /// Broadcast a global event to all global subscribers.
    pub fn broadcast_global(&self, event: Event) {
        let _ = self.global_sender.send(event);
    }
}

impl Default for SubscriptionManager {
    fn default() -> Self {
        Self::new()
    }
}

/// IPC server that listens on a Unix domain socket.
pub struct IpcServer {
    socket_path: String,
    handlers: Arc<RwLock<HashMap<Method, HandlerFn>>>,
    shutdown_tx: broadcast::Sender<()>,
    subscriptions: SubscriptionManager,
    initial_state_fn: Arc<RwLock<Option<InitialStateFn>>>,
}

impl IpcServer {
    /// Create a new IPC server.
    pub fn new(socket_path: &str) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);

        Self {
            socket_path: socket_path.to_string(),
            handlers: Arc::new(RwLock::new(HashMap::new())),
            shutdown_tx,
            subscriptions: SubscriptionManager::new(),
            initial_state_fn: Arc::new(RwLock::new(None)),
        }
    }

    /// Register a handler for a method.
    pub async fn register_handler<F, Fut>(&self, method: Method, handler: F)
    where
        F: Fn(Request) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Response> + Send + 'static,
    {
        let boxed_handler: HandlerFn = Box::new(move |req| Box::pin(handler(req)));
        self.handlers.write().await.insert(method, boxed_handler);
    }

    /// Register the callback for getting initial subscription state.
    pub async fn register_initial_state_handler<F, Fut>(&self, handler: F)
    where
        F: Fn(String) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Option<(Vec<Event>, i64)>> + Send + 'static,
    {
        let boxed: InitialStateFn = Box::new(move |session_id| Box::pin(handler(session_id)));
        *self.initial_state_fn.write().await = Some(boxed);
    }

    /// Get the subscription manager for broadcasting events.
    pub fn subscriptions(&self) -> &SubscriptionManager {
        &self.subscriptions
    }

    /// Get a shutdown receiver.
    pub fn shutdown_receiver(&self) -> broadcast::Receiver<()> {
        self.shutdown_tx.subscribe()
    }

    /// Get a shutdown sender (for handlers that need to trigger shutdown).
    pub fn shutdown_sender(&self) -> broadcast::Sender<()> {
        self.shutdown_tx.clone()
    }

    /// Trigger shutdown.
    pub fn shutdown(&self) {
        let _ = self.shutdown_tx.send(());
    }

    /// Start the server and listen for connections.
    pub async fn run(&self) -> IpcResult<()> {
        // Remove existing socket file
        let socket_path = Path::new(&self.socket_path);
        if socket_path.exists() {
            std::fs::remove_file(socket_path)?;
        }

        // Ensure parent directory exists
        if let Some(parent) = socket_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let listener = UnixListener::bind(&self.socket_path)?;
        info!(path = %self.socket_path, "IPC server listening");

        let mut shutdown_rx = self.shutdown_tx.subscribe();
        let handlers = self.handlers.clone();
        let subscriptions = self.subscriptions.clone();
        let initial_state_fn = self.initial_state_fn.clone();

        loop {
            tokio::select! {
                accept_result = listener.accept() => {
                    match accept_result {
                        Ok((stream, _)) => {
                            let handlers = handlers.clone();
                            let subscriptions = subscriptions.clone();
                            let initial_state_fn = initial_state_fn.clone();
                            tokio::spawn(async move {
                                if let Err(e) = handle_connection(stream, handlers, subscriptions, initial_state_fn).await {
                                    error!(error = %e, "Connection error");
                                }
                            });
                        }
                        Err(e) => {
                            error!(error = %e, "Accept error");
                        }
                    }
                }
                _ = shutdown_rx.recv() => {
                    info!("IPC server shutting down");
                    break;
                }
            }
        }

        // Cleanup socket file
        let _ = std::fs::remove_file(&self.socket_path);

        Ok(())
    }
}

/// Handle a single client connection.
async fn handle_connection(
    stream: UnixStream,
    handlers: Arc<RwLock<HashMap<Method, HandlerFn>>>,
    _subscriptions: SubscriptionManager,
    _initial_state_fn: Arc<RwLock<Option<InitialStateFn>>>,
) -> IpcResult<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    debug!("Client connected");

    loop {
        line.clear();
        let bytes_read = reader.read_line(&mut line).await?;

        if bytes_read == 0 {
            debug!("Client disconnected");
            break;
        }

        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        debug!(request = %trimmed, "Received request");

        let request = match Request::from_json(trimmed) {
            Ok(req) => req,
            Err(e) => {
                warn!(error = %e, "Failed to parse request");
                let response = Response::error("", error_codes::PARSE_ERROR, &format!("Parse error: {}", e));
                let response_json = response.to_json()?;
                writer.write_all(response_json.as_bytes()).await?;
                writer.write_all(b"\n").await?;
                writer.flush().await?;
                continue;
            }
        };

        let request_id = request.id.clone();
        let method = request.method.clone();

        // Legacy socket subscription - deprecated in favor of shared memory.
        // Clients should use IpcClient::subscribe() which opens shared memory directly.
        if method == Method::SessionSubscribe || method == Method::SessionUnsubscribe {
            let response = Response::error(
                &request_id,
                error_codes::METHOD_NOT_FOUND,
                "Socket-based subscriptions are deprecated. Use shared memory via IpcClient::subscribe() instead.",
            );
            let response_json = response.to_json()?;
            writer.write_all(response_json.as_bytes()).await?;
            writer.write_all(b"\n").await?;
            writer.flush().await?;
            continue;
        }

        // Normal request/response handling
        let response = {
            let handlers = handlers.read().await;
            if let Some(handler) = handlers.get(&method) {
                handler(request).await
            } else {
                Response::error(
                    &request_id,
                    error_codes::METHOD_NOT_FOUND,
                    &format!("Method not found: {:?}", method),
                )
            }
        };

        let response_json = response.to_json()?;
        debug!(response = %response_json, "Sending response");

        writer.write_all(response_json.as_bytes()).await?;
        writer.write_all(b"\n").await?;
        writer.flush().await?;
    }

    Ok(())
}

/// IPC client for connecting to the daemon.
pub struct IpcClient {
    socket_path: String,
}

impl IpcClient {
    /// Create a new IPC client.
    pub fn new(socket_path: &str) -> Self {
        Self {
            socket_path: socket_path.to_string(),
        }
    }

    /// Send a request and wait for response.
    pub async fn call(&self, request: Request) -> IpcResult<Response> {
        let stream = UnixStream::connect(&self.socket_path).await
            .map_err(|e| IpcError::Socket(format!("Failed to connect: {}", e)))?;

        let (reader, mut writer) = stream.into_split();
        let mut reader = BufReader::new(reader);

        // Send request
        let request_json = request.to_json()?;
        writer.write_all(request_json.as_bytes()).await?;
        writer.write_all(b"\n").await?;
        writer.flush().await?;

        // Read response
        let mut line = String::new();
        reader.read_line(&mut line).await?;

        if line.is_empty() {
            return Err(IpcError::ConnectionClosed);
        }

        let response = Response::from_json(line.trim())?;
        Ok(response)
    }

    /// Send a method call with no parameters.
    pub async fn call_method(&self, method: Method) -> IpcResult<Response> {
        self.call(Request::new(method)).await
    }

    /// Send a method call with parameters.
    pub async fn call_method_with_params(
        &self,
        method: Method,
        params: serde_json::Value,
    ) -> IpcResult<Response> {
        self.call(Request::with_params(method, params)).await
    }

    /// Check if the daemon is running.
    pub async fn is_daemon_running(&self) -> bool {
        self.call_method(Method::Health).await.is_ok()
    }

    /// Subscribe to a session's events using shared memory.
    /// This is the preferred method for low-latency streaming (~1-5μs vs ~35-130μs for sockets).
    pub async fn subscribe(&self, session_id: &str) -> IpcResult<SharedMemorySubscription> {
        // Open shared memory consumer
        let mut consumer = daemon_stream::StreamConsumer::open(session_id)
            .map_err(|e| IpcError::Socket(format!(
                "Shared memory stream not available for session {}: {}",
                session_id, e
            )))?;

        // Create channel for events
        let (event_tx, event_rx) = mpsc::channel(100);

        // Spawn task to poll shared memory and forward events
        let session_id_clone = session_id.to_string();
        tokio::spawn(async move {
            loop {
                // Non-blocking read
                match consumer.try_read() {
                    Some(shm_event) => {
                        // Convert shared memory event to IPC event
                        if let Some(event) = convert_shm_event(&session_id_clone, shm_event) {
                            if event_tx.send(event).await.is_err() {
                                break;
                            }
                        }
                    }
                    None => {
                        // Check for shutdown
                        if consumer.is_shutdown() {
                            debug!("Shared memory stream shutdown for session {}", session_id_clone);
                            break;
                        }
                        // No events available, sleep briefly
                        tokio::time::sleep(std::time::Duration::from_millis(1)).await;
                    }
                }
            }
        });

        Ok(SharedMemorySubscription {
            session_id: session_id.to_string(),
            event_rx,
        })
    }
}

/// Convert a shared memory event to an IPC event.
fn convert_shm_event(session_id: &str, shm_event: daemon_stream::StreamEvent) -> Option<Event> {
    let event_type = match shm_event.event_type {
        daemon_stream::EventType::ClaudeEvent => EventType::ClaudeEvent,
        daemon_stream::EventType::TerminalOutput => EventType::TerminalOutput,
        daemon_stream::EventType::TerminalFinished => EventType::TerminalFinished,
        daemon_stream::EventType::StreamingChunk => EventType::StreamingChunk,
        daemon_stream::EventType::Ping => return None, // Internal, don't forward
    };

    // Parse payload as JSON if possible, otherwise wrap as raw string
    let data = match String::from_utf8(shm_event.payload.clone()) {
        Ok(s) => {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&s) {
                json
            } else {
                serde_json::json!({ "raw": s })
            }
        }
        Err(_) => {
            // Binary data - for terminal finished, this is the exit code
            if shm_event.event_type == daemon_stream::EventType::TerminalFinished && shm_event.payload.len() >= 4 {
                let exit_code = i32::from_le_bytes([
                    shm_event.payload[0],
                    shm_event.payload[1],
                    shm_event.payload[2],
                    shm_event.payload[3],
                ]);
                serde_json::json!({ "exit_code": exit_code })
            } else {
                serde_json::json!({ "raw_bytes": shm_event.payload.len() })
            }
        }
    };

    Some(Event::new(event_type, session_id, data, shm_event.sequence))
}

/// A subscription to a session's events via shared memory.
/// Provides low-latency access to streaming events (~1-5μs per event).
pub struct SharedMemorySubscription {
    session_id: String,
    event_rx: mpsc::Receiver<Event>,
}

impl SharedMemorySubscription {
    /// Get the session ID this subscription is for.
    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    /// Receive the next event. Returns None if the subscription is closed.
    pub async fn recv(&mut self) -> Option<Event> {
        self.event_rx.recv().await
    }

    /// Try to receive an event without blocking. Returns None if no event available or closed.
    pub fn try_recv(&mut self) -> Option<Event> {
        self.event_rx.try_recv().ok()
    }
}

// Keep the old Subscription type as an alias for backward compatibility
pub type Subscription = SharedMemorySubscription;

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_ipc_client_not_running() {
        let client = IpcClient::new("/tmp/nonexistent.sock");
        assert!(!client.is_daemon_running().await);
    }

    #[tokio::test]
    async fn test_ipc_client_connect_failure() {
        let client = IpcClient::new("/tmp/definitely-does-not-exist-12345.sock");
        let result = client.call_method(Method::Health).await;
        assert!(result.is_err());
    }

    #[test]
    fn test_ipc_server_creation() {
        let server = IpcServer::new("/tmp/test-server.sock");
        // Server should be created successfully
        assert!(true);
    }

    #[tokio::test]
    async fn test_ipc_server_shutdown_receiver() {
        let server = IpcServer::new("/tmp/test-server2.sock");
        let _receiver = server.shutdown_receiver();
        // Should be able to get a receiver without error
        assert!(true);
    }

    #[tokio::test]
    async fn test_ipc_server_register_handler() {
        let server = IpcServer::new("/tmp/test-server3.sock");

        server.register_handler(Method::Health, |req| async move {
            Response::success(&req.id, serde_json::json!({"status": "ok"}))
        }).await;

        // Handler should be registered (we can't verify directly but no panic)
        assert!(true);
    }

    #[test]
    fn test_ipc_client_creation() {
        let client = IpcClient::new("/path/to/socket.sock");
        // Client should be created successfully
        assert!(true);
    }

    #[tokio::test]
    async fn test_ipc_server_shutdown() {
        let server = IpcServer::new("/tmp/test-server4.sock");
        let mut receiver = server.shutdown_receiver();

        // Trigger shutdown
        server.shutdown();

        // Receiver should get notification
        let result = tokio::time::timeout(
            std::time::Duration::from_millis(100),
            receiver.recv()
        ).await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_ipc_server_multiple_handlers() {
        let server = IpcServer::new("/tmp/test-server5.sock");

        server.register_handler(Method::Health, |req| async move {
            Response::success(&req.id, serde_json::json!({"healthy": true}))
        }).await;

        server.register_handler(Method::AuthStatus, |req| async move {
            Response::success(&req.id, serde_json::json!({"logged_in": false}))
        }).await;

        server.register_handler(Method::SessionList, |req| async move {
            Response::success(&req.id, serde_json::json!({"sessions": []}))
        }).await;

        // All handlers registered without error
        assert!(true);
    }
}
