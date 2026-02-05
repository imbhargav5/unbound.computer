//! I. Transport Setup tests for Falco.
//!
//! Rules covered:
//! - 1. Falco starts with a consumer listening on the transport socket
//! - 2. Falco connects to the consumer using the production transport
//! - 3. Falco uses the same framing and protocol as production
//! - 4. Falco does not assume anything about consumer internals

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use crate::protocol::{CommandFrame, DaemonDecisionFrame, FRAME_TYPE_COMMAND};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use uuid::Uuid;

/// Rule 1: Falco starts with a consumer listening on the transport socket
#[tokio::test]
async fn rule_01_consumer_must_be_listening() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();

    // Consumer not started yet - connection should fail
    let result = UnixStream::connect(consumer.socket_path()).await;
    assert!(result.is_err(), "Connection should fail when consumer not listening");

    // Start consumer
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    // Now connection should succeed
    let result = UnixStream::connect(consumer.socket_path()).await;
    assert!(result.is_ok(), "Connection should succeed when consumer is listening");

    consumer.shutdown();
    handle.abort();
}

/// Rule 2: Falco connects to the consumer using the production transport
#[tokio::test]
async fn rule_02_connects_using_production_transport() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    // Falco uses Unix Domain Sockets
    let stream = UnixStream::connect(consumer.socket_path()).await;
    assert!(stream.is_ok(), "Falco should connect via UDS");

    consumer.shutdown();
    handle.abort();
}

/// Rule 3: Falco uses the same framing and protocol as production
#[tokio::test]
async fn rule_03_uses_production_framing() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let mut stream = UnixStream::connect(consumer.socket_path()).await.unwrap();

    // Send a properly framed command
    let command_id = Uuid::new_v4();
    let payload = vec![0xDE, 0xAD, 0xBE, 0xEF];
    let frame = CommandFrame::new(command_id, payload.clone());
    let encoded = frame.encode();

    // Verify frame structure (length-prefixed)
    let len = u32::from_le_bytes(encoded[0..4].try_into().unwrap()) as usize;
    assert_eq!(len + 4, encoded.len(), "Frame should be length-prefixed");
    assert_eq!(encoded[4], FRAME_TYPE_COMMAND, "Frame type should be COMMAND");

    stream.write_all(&encoded).await.unwrap();

    // Read response
    let mut buf = [0u8; 4096];
    let n = stream.read(&mut buf).await.unwrap();
    assert!(n > 0, "Should receive response");

    // Parse response
    let resp_len = u32::from_le_bytes(buf[0..4].try_into().unwrap()) as usize;
    assert_eq!(resp_len + 4, n, "Response should be length-prefixed");

    let decision = DaemonDecisionFrame::decode(&buf[4..n]).unwrap();
    assert_eq!(decision.command_id, command_id, "Command ID should match");

    consumer.shutdown();
    handle.abort();
}

/// Rule 4: Falco does not assume anything about consumer internals
#[tokio::test]
async fn rule_04_consumer_agnostic() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    // Test with ACK response
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();
    assert!(result.redis_acked, "Should ACK when consumer says ACK");

    // Test with DO_NOT_ACK response
    redis.xadd(vec![4, 5, 6]);
    consumer.queue_response(ConsumerResponse::DoNotAck);

    let result = sim.process_one().await.unwrap();
    assert!(!result.redis_acked, "Should not ACK when consumer says DO_NOT_ACK");

    // Falco behavior depends only on protocol responses, not consumer identity
    assert_eq!(consumer.received_count(), 2);

    consumer.shutdown();
    handle.abort();
}

/// Transport: Binary frame integrity preserved
#[tokio::test]
async fn transport_binary_frame_integrity() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let mut stream = UnixStream::connect(consumer.socket_path()).await.unwrap();

    // Send binary payload with all byte values
    let payload: Vec<u8> = (0..=255).collect();
    let command_id = Uuid::new_v4();
    let frame = CommandFrame::new(command_id, payload.clone());

    stream.write_all(&frame.encode()).await.unwrap();

    // Read response
    let mut buf = [0u8; 4096];
    let _ = stream.read(&mut buf).await.unwrap();

    // Verify payload was received intact
    tokio::time::sleep(Duration::from_millis(50)).await;
    let received = consumer.received_commands();
    assert_eq!(received.len(), 1);
    assert_eq!(received[0].payload, payload, "Binary payload should be preserved");

    consumer.shutdown();
    handle.abort();
}

/// Transport: Multiple sequential connections work
#[tokio::test]
async fn transport_multiple_connections() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    for i in 0..5 {
        let mut stream = UnixStream::connect(consumer.socket_path()).await.unwrap();

        let command_id = Uuid::new_v4();
        let payload = vec![i as u8];
        let frame = CommandFrame::new(command_id, payload);

        stream.write_all(&frame.encode()).await.unwrap();

        let mut buf = [0u8; 4096];
        let n = stream.read(&mut buf).await.unwrap();
        assert!(n > 0, "Connection {} should receive response", i);
    }

    assert_eq!(consumer.received_count(), 5, "All connections should work");

    consumer.shutdown();
    handle.abort();
}
