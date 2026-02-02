//! Test harness for Falco integration tests.
//!
//! Provides:
//! - MockConsumer: A consumer that speaks the binary protocol
//! - MockRedis: A simulated Redis Streams interface
//! - TestHarness: Orchestrates Falco, MockConsumer, and MockRedis

use crate::protocol::{
    read_frame, CommandFrame, DaemonDecisionFrame, Decision, FRAME_TYPE_COMMAND,
};
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering as AtomicOrdering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tempfile::TempDir;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::time::timeout;
use uuid::Uuid;

/// A command received by the mock consumer.
#[derive(Debug, Clone)]
pub struct ReceivedCommand {
    pub command_id: Uuid,
    pub payload: Vec<u8>,
    #[allow(dead_code)]
    pub received_at: std::time::Instant,
}

/// Response to send back to Falco.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum ConsumerResponse {
    /// Send ACK_REDIS decision
    AckRedis,
    /// Send DO_NOT_ACK decision
    DoNotAck,
    /// Delay before responding
    DelayThenAck(Duration),
    /// Delay before responding with DO_NOT_ACK
    DelayThenDoNotAck(Duration),
    /// Never respond (for timeout testing)
    NeverRespond,
    /// Close connection immediately
    CloseConnection,
    /// Send response with custom result data
    AckRedisWithResult(Vec<u8>),
}

/// Mock consumer that speaks the Falco binary protocol.
pub struct MockConsumer {
    socket_path: PathBuf,
    received_commands: Arc<Mutex<Vec<ReceivedCommand>>>,
    response_queue: Arc<Mutex<VecDeque<ConsumerResponse>>>,
    default_response: Arc<Mutex<ConsumerResponse>>,
    shutdown: Arc<AtomicBool>,
    _temp_dir: TempDir,
}

impl MockConsumer {
    /// Create a new mock consumer with a temporary socket.
    pub fn new() -> Self {
        let temp_dir = TempDir::new().unwrap();
        let socket_path = temp_dir.path().join("consumer.sock");

        Self {
            socket_path,
            received_commands: Arc::new(Mutex::new(Vec::new())),
            response_queue: Arc::new(Mutex::new(VecDeque::new())),
            default_response: Arc::new(Mutex::new(ConsumerResponse::AckRedis)),
            shutdown: Arc::new(AtomicBool::new(false)),
            _temp_dir: temp_dir,
        }
    }

    /// Get the socket path.
    pub fn socket_path(&self) -> &PathBuf {
        &self.socket_path
    }

    /// Set the default response for commands.
    pub fn set_default_response(&self, response: ConsumerResponse) {
        *self.default_response.lock().unwrap() = response;
    }

    /// Queue a specific response for the next command.
    pub fn queue_response(&self, response: ConsumerResponse) {
        self.response_queue.lock().unwrap().push_back(response);
    }

    /// Get all received commands.
    pub fn received_commands(&self) -> Vec<ReceivedCommand> {
        self.received_commands.lock().unwrap().clone()
    }

    /// Get the count of received commands.
    pub fn received_count(&self) -> usize {
        self.received_commands.lock().unwrap().len()
    }

    /// Clear received commands.
    pub fn clear_received(&self) {
        self.received_commands.lock().unwrap().clear();
    }

    /// Signal shutdown.
    pub fn shutdown(&self) {
        self.shutdown.store(true, AtomicOrdering::SeqCst);
    }

    /// Start the mock consumer server.
    pub async fn start(&self) -> tokio::task::JoinHandle<()> {
        let socket_path = self.socket_path.clone();
        let received_commands = self.received_commands.clone();
        let response_queue = self.response_queue.clone();
        let default_response = self.default_response.clone();
        let shutdown = self.shutdown.clone();

        tokio::spawn(async move {
            let listener = UnixListener::bind(&socket_path).unwrap();

            loop {
                if shutdown.load(AtomicOrdering::SeqCst) {
                    break;
                }

                let accept_result = tokio::select! {
                    result = listener.accept() => result,
                    _ = tokio::time::sleep(Duration::from_millis(100)) => continue,
                };

                if let Ok((stream, _)) = accept_result {
                    let received = received_commands.clone();
                    let responses = response_queue.clone();
                    let default = default_response.clone();
                    let shutdown_flag = shutdown.clone();

                    tokio::spawn(async move {
                        Self::handle_connection(stream, received, responses, default, shutdown_flag)
                            .await;
                    });
                }
            }
        })
    }

    async fn handle_connection(
        mut stream: UnixStream,
        received_commands: Arc<Mutex<Vec<ReceivedCommand>>>,
        response_queue: Arc<Mutex<VecDeque<ConsumerResponse>>>,
        default_response: Arc<Mutex<ConsumerResponse>>,
        shutdown: Arc<AtomicBool>,
    ) {
        let mut buf = vec![0u8; 65536];
        let mut read_buf = Vec::new();

        loop {
            if shutdown.load(AtomicOrdering::SeqCst) {
                break;
            }

            // Read data with timeout
            let read_result = tokio::select! {
                result = stream.read(&mut buf) => result,
                _ = tokio::time::sleep(Duration::from_millis(100)) => continue,
            };

            match read_result {
                Ok(0) => break, // Connection closed
                Ok(n) => {
                    read_buf.extend_from_slice(&buf[..n]);
                }
                Err(_) => break,
            }

            // Try to parse frames
            while let Some((frame_data, consumed)) = read_frame(&read_buf) {
                if frame_data.is_empty() || frame_data[0] != FRAME_TYPE_COMMAND {
                    read_buf.drain(..consumed);
                    continue;
                }

                let command = match CommandFrame::decode(frame_data) {
                    Ok(cmd) => cmd,
                    Err(_) => {
                        read_buf.drain(..consumed);
                        continue;
                    }
                };

                // Record the received command
                {
                    let mut received = received_commands.lock().unwrap();
                    received.push(ReceivedCommand {
                        command_id: command.command_id,
                        payload: command.encrypted_payload.clone(),
                        received_at: std::time::Instant::now(),
                    });
                }

                // Get response
                let response = {
                    let mut queue = response_queue.lock().unwrap();
                    queue
                        .pop_front()
                        .unwrap_or_else(|| default_response.lock().unwrap().clone())
                };

                // Handle response
                match response {
                    ConsumerResponse::AckRedis => {
                        let decision = DaemonDecisionFrame::new(command.command_id, Decision::AckRedis);
                        let _ = stream.write_all(&decision.encode()).await;
                    }
                    ConsumerResponse::DoNotAck => {
                        let decision = DaemonDecisionFrame::new(command.command_id, Decision::DoNotAck);
                        let _ = stream.write_all(&decision.encode()).await;
                    }
                    ConsumerResponse::DelayThenAck(delay) => {
                        tokio::time::sleep(delay).await;
                        let decision = DaemonDecisionFrame::new(command.command_id, Decision::AckRedis);
                        let _ = stream.write_all(&decision.encode()).await;
                    }
                    ConsumerResponse::DelayThenDoNotAck(delay) => {
                        tokio::time::sleep(delay).await;
                        let decision = DaemonDecisionFrame::new(command.command_id, Decision::DoNotAck);
                        let _ = stream.write_all(&decision.encode()).await;
                    }
                    ConsumerResponse::NeverRespond => {
                        // Don't respond, just keep connection open
                        tokio::time::sleep(Duration::from_secs(3600)).await;
                    }
                    ConsumerResponse::CloseConnection => {
                        // Return to close connection (break would only exit inner loop)
                        return;
                    }
                    ConsumerResponse::AckRedisWithResult(result) => {
                        let decision = DaemonDecisionFrame::with_result(
                            command.command_id,
                            Decision::AckRedis,
                            result,
                        );
                        let _ = stream.write_all(&decision.encode()).await;
                    }
                }

                read_buf.drain(..consumed);
            }
        }
    }
}

/// A command in the mock Redis stream.
#[derive(Debug, Clone)]
pub struct MockStreamMessage {
    pub message_id: String,
    pub payload: Vec<u8>,
    #[allow(dead_code)]
    pub acked: bool,
}

/// Mock Redis Streams interface.
#[allow(dead_code)]
pub struct MockRedis {
    stream: Arc<Mutex<VecDeque<MockStreamMessage>>>,
    pending: Arc<Mutex<Vec<MockStreamMessage>>>,
    ack_log: Arc<Mutex<Vec<String>>>,
    next_id: Arc<AtomicU64>,
    consumer_group: String,
}

impl MockRedis {
    /// Create a new mock Redis.
    pub fn new(consumer_group: &str) -> Self {
        Self {
            stream: Arc::new(Mutex::new(VecDeque::new())),
            pending: Arc::new(Mutex::new(Vec::new())),
            ack_log: Arc::new(Mutex::new(Vec::new())),
            next_id: Arc::new(AtomicU64::new(1)),
            consumer_group: consumer_group.to_string(),
        }
    }

    /// Add a command to the stream (XADD).
    pub fn xadd(&self, payload: Vec<u8>) -> String {
        let id = self.next_id.fetch_add(1, AtomicOrdering::SeqCst);
        let message_id = format!("{}-0", id);

        let msg = MockStreamMessage {
            message_id: message_id.clone(),
            payload,
            acked: false,
        };

        self.stream.lock().unwrap().push_back(msg);
        message_id
    }

    /// Read next message (XREADGROUP simulation).
    /// Moves message to pending list.
    pub fn xreadgroup(&self) -> Option<MockStreamMessage> {
        let mut stream = self.stream.lock().unwrap();
        if let Some(msg) = stream.pop_front() {
            let mut pending = self.pending.lock().unwrap();
            pending.push(msg.clone());
            Some(msg)
        } else {
            None
        }
    }

    /// Acknowledge a message (XACK).
    pub fn xack(&self, message_id: &str) -> bool {
        let mut pending = self.pending.lock().unwrap();
        if let Some(pos) = pending.iter().position(|m| m.message_id == message_id) {
            pending.remove(pos);
            self.ack_log.lock().unwrap().push(message_id.to_string());
            true
        } else {
            false
        }
    }

    /// Get pending messages.
    pub fn pending(&self) -> Vec<MockStreamMessage> {
        self.pending.lock().unwrap().clone()
    }

    /// Get pending count.
    pub fn pending_count(&self) -> usize {
        self.pending.lock().unwrap().len()
    }

    /// Get ACK log (ordered list of ACKed message IDs).
    pub fn ack_log(&self) -> Vec<String> {
        self.ack_log.lock().unwrap().clone()
    }

    /// Get ACK count.
    pub fn ack_count(&self) -> usize {
        self.ack_log.lock().unwrap().len()
    }

    /// Get stream length (unread messages).
    pub fn stream_len(&self) -> usize {
        self.stream.lock().unwrap().len()
    }

    /// Check if a specific message was ACKed.
    pub fn was_acked(&self, message_id: &str) -> bool {
        self.ack_log.lock().unwrap().contains(&message_id.to_string())
    }

    /// Clear the ACK log.
    #[allow(dead_code)]
    pub fn clear_ack_log(&self) {
        self.ack_log.lock().unwrap().clear();
    }
}

/// Test harness that coordinates MockConsumer, MockRedis, and Falco.
#[allow(dead_code)]
pub struct TestHarness {
    pub consumer: MockConsumer,
    pub redis: MockRedis,
    _temp_dir: TempDir,
}

#[allow(dead_code)]
impl TestHarness {
    /// Create a new test harness.
    pub fn new() -> Self {
        let temp_dir = TempDir::new().unwrap();

        Self {
            consumer: MockConsumer::new(),
            redis: MockRedis::new("falco"),
            _temp_dir: temp_dir,
        }
    }

    /// Add a command to Redis and return the message ID.
    pub fn add_command(&self, payload: Vec<u8>) -> String {
        self.redis.xadd(payload)
    }

    /// Add multiple commands to Redis.
    pub fn add_commands(&self, payloads: Vec<Vec<u8>>) -> Vec<String> {
        payloads.into_iter().map(|p| self.redis.xadd(p)).collect()
    }

    /// Simulate Falco reading a command and forwarding it.
    /// Returns the message if available.
    pub fn read_and_forward(&self) -> Option<MockStreamMessage> {
        self.redis.xreadgroup()
    }

    /// Simulate Falco ACKing a message.
    pub fn ack_message(&self, message_id: &str) -> bool {
        self.redis.xack(message_id)
    }
}

/// Result of a simulated Falco operation.
#[derive(Debug, Clone)]
pub struct FalcoOperationResult {
    pub message_id: String,
    pub payload_forwarded: Vec<u8>,
    pub decision_received: Option<Decision>,
    pub redis_acked: bool,
    pub timed_out: bool,
}

/// Simulates the Falco courier behavior for testing.
pub struct FalcoCourierSim {
    consumer_socket: PathBuf,
    redis: Arc<MockRedis>,
    timeout_duration: Duration,
}

impl FalcoCourierSim {
    /// Create a new Falco courier simulation.
    pub fn new(consumer_socket: PathBuf, redis: Arc<MockRedis>, timeout: Duration) -> Self {
        Self {
            consumer_socket,
            redis,
            timeout_duration: timeout,
        }
    }

    /// Process one command from Redis.
    pub async fn process_one(&self) -> Option<FalcoOperationResult> {
        // Read from Redis
        let msg = self.redis.xreadgroup()?;

        let mut result = FalcoOperationResult {
            message_id: msg.message_id.clone(),
            payload_forwarded: msg.payload.clone(),
            decision_received: None,
            redis_acked: false,
            timed_out: false,
        };

        // Connect to consumer
        let mut stream = match UnixStream::connect(&self.consumer_socket).await {
            Ok(s) => s,
            Err(_) => return Some(result),
        };

        // Generate command ID and send frame
        let command_id = Uuid::new_v4();
        let frame = CommandFrame::new(command_id, msg.payload);
        if stream.write_all(&frame.encode()).await.is_err() {
            return Some(result);
        }

        // Wait for response with timeout
        let mut buf = vec![0u8; 4096];
        let read_result = timeout(self.timeout_duration, stream.read(&mut buf)).await;

        match read_result {
            Ok(Ok(n)) if n > 0 => {
                // Parse response
                if let Some((frame_data, _)) = read_frame(&buf[..n]) {
                    if let Ok(decision_frame) = DaemonDecisionFrame::decode(frame_data) {
                        result.decision_received = Some(decision_frame.decision);

                        // ACK based on decision
                        if decision_frame.decision == Decision::AckRedis {
                            result.redis_acked = self.redis.xack(&msg.message_id);
                        }
                    }
                }
            }
            Ok(Ok(_)) | Ok(Err(_)) => {
                // Connection closed or error
            }
            Err(_) => {
                // Timeout - fail-open ACK
                result.timed_out = true;
                result.redis_acked = self.redis.xack(&msg.message_id);
            }
        }

        Some(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_consumer_receives_command() {
        let consumer = MockConsumer::new();
        let handle = consumer.start().await;

        // Give server time to start
        tokio::time::sleep(Duration::from_millis(50)).await;

        // Connect and send a command
        let mut stream = UnixStream::connect(consumer.socket_path()).await.unwrap();

        let command_id = Uuid::new_v4();
        let payload = vec![1, 2, 3, 4];
        let frame = CommandFrame::new(command_id, payload.clone());
        stream.write_all(&frame.encode()).await.unwrap();

        // Read response
        let mut buf = [0u8; 4096];
        let n = stream.read(&mut buf).await.unwrap();
        assert!(n > 0);

        // Verify command was received
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(consumer.received_count(), 1);
        assert_eq!(consumer.received_commands()[0].payload, vec![1, 2, 3, 4]);

        consumer.shutdown();
        handle.abort();
    }

    #[test]
    fn test_mock_redis_basic_operations() {
        let redis = MockRedis::new("test-group");

        // Add commands
        let id1 = redis.xadd(vec![1, 2, 3]);
        let id2 = redis.xadd(vec![4, 5, 6]);

        assert_eq!(redis.stream_len(), 2);

        // Read commands
        let msg1 = redis.xreadgroup().unwrap();
        assert_eq!(msg1.message_id, id1);
        assert_eq!(msg1.payload, vec![1, 2, 3]);

        assert_eq!(redis.pending_count(), 1);
        assert_eq!(redis.stream_len(), 1);

        // ACK first message
        assert!(redis.xack(&id1));
        assert_eq!(redis.pending_count(), 0);
        assert_eq!(redis.ack_count(), 1);
        assert!(redis.was_acked(&id1));

        // Read second message
        let msg2 = redis.xreadgroup().unwrap();
        assert_eq!(msg2.message_id, id2);

        // ACK second message
        assert!(redis.xack(&id2));
        assert_eq!(redis.ack_count(), 2);

        // Verify ACK order
        let ack_log = redis.ack_log();
        assert_eq!(ack_log, vec![id1, id2]);
    }

    #[tokio::test]
    async fn test_falco_sim_basic_flow() {
        let consumer = MockConsumer::new();
        consumer.set_default_response(ConsumerResponse::AckRedis);
        let handle = consumer.start().await;

        tokio::time::sleep(Duration::from_millis(50)).await;

        let redis = Arc::new(MockRedis::new("falco"));
        let msg_id = redis.xadd(vec![10, 20, 30]);

        let sim = FalcoCourierSim::new(
            consumer.socket_path().clone(),
            redis.clone(),
            Duration::from_secs(5),
        );

        let result = sim.process_one().await.unwrap();

        assert_eq!(result.message_id, msg_id);
        assert_eq!(result.payload_forwarded, vec![10, 20, 30]);
        assert_eq!(result.decision_received, Some(Decision::AckRedis));
        assert!(result.redis_acked);
        assert!(!result.timed_out);

        consumer.shutdown();
        handle.abort();
    }
}
