//! X. Transport Failure Handling tests for Falco.
//!
//! Rules covered:
//! - 37. Consumer closes connection mid-command
//! - 38. Falco reconnects
//! - 39. Falco does not emit Redis ACK
//! - 40. Command remains pending

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 37: Consumer closes connection mid-command
#[tokio::test]
async fn rule_37_consumer_closes_connection() {
    let consumer = MockConsumer::new();
    // Consumer will close connection without responding
    consumer.queue_response(ConsumerResponse::CloseConnection);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // Consumer received the command
    assert_eq!(consumer.received_count(), 1);

    // No decision received (connection closed)
    assert!(result.decision_received.is_none());

    consumer.shutdown();
    handle.abort();
}

/// Rule 38: Falco reconnects (tested by successful subsequent connection)
#[tokio::test]
async fn rule_38_falco_reconnects() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // First command: connection closed
    redis.xadd(vec![1]);
    consumer.queue_response(ConsumerResponse::CloseConnection);

    // Second command: normal ACK
    redis.xadd(vec![2]);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // First attempt - connection closes
    let result1 = sim.process_one().await.unwrap();
    assert!(result1.decision_received.is_none());

    // Second attempt - should reconnect and succeed
    let result2 = sim.process_one().await.unwrap();
    assert!(result2.redis_acked);
    assert_eq!(result2.decision_received, Some(crate::protocol::Decision::AckRedis));

    consumer.shutdown();
    handle.abort();
}

/// Rule 39: Falco does not emit Redis ACK on connection failure
#[tokio::test]
async fn rule_39_no_ack_on_connection_failure() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::CloseConnection);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // No ACK when connection fails
    assert!(!result.redis_acked, "Should not ACK on connection failure");
    assert_eq!(redis.ack_count(), 0);

    consumer.shutdown();
    handle.abort();
}

/// Rule 40: Command remains pending after connection failure
#[tokio::test]
async fn rule_40_command_remains_pending() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::CloseConnection);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let _result = sim.process_one().await.unwrap();

    // Command should remain in pending list
    assert_eq!(redis.pending_count(), 1);
    assert_eq!(redis.pending()[0].message_id, msg_id);
    assert!(!redis.was_acked(&msg_id));

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional transport failure tests
// =============================================================================

/// Transport failure: Consumer not listening at start
#[tokio::test]
async fn transport_failure_consumer_not_listening() {
    let consumer = MockConsumer::new();
    // Don't start the consumer

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(1),
    );

    let result = sim.process_one().await.unwrap();

    // Connection failed
    assert!(!result.redis_acked);
    assert!(result.decision_received.is_none());

    // Command still pending
    assert_eq!(redis.pending_count(), 1);
}

/// Transport failure: Multiple connection failures then success
#[tokio::test]
async fn transport_failure_retry_success() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // First two close, third succeeds
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);
    redis.xadd(vec![3]);

    consumer.queue_response(ConsumerResponse::CloseConnection);
    consumer.queue_response(ConsumerResponse::CloseConnection);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let r1 = sim.process_one().await.unwrap();
    let r2 = sim.process_one().await.unwrap();
    let r3 = sim.process_one().await.unwrap();

    assert!(!r1.redis_acked, "First should fail");
    assert!(!r2.redis_acked, "Second should fail");
    assert!(r3.redis_acked, "Third should succeed");

    // Two pending, one ACKed
    assert_eq!(redis.pending_count(), 2);
    assert_eq!(redis.ack_count(), 1);

    consumer.shutdown();
    handle.abort();
}

/// Transport failure: Partial write before close
#[tokio::test]
async fn transport_failure_partial_write() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::CloseConnection);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    // Large payload that might have partial write issues
    let redis = Arc::new(MockRedis::new("falco"));
    let large_payload: Vec<u8> = (0..10000).map(|i| (i % 256) as u8).collect();
    redis.xadd(large_payload);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // Should not ACK regardless of write state
    assert!(!result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Transport failure: Socket path doesn't exist
#[tokio::test]
async fn transport_failure_socket_not_exists() {
    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        "/nonexistent/path/to/socket.sock".into(),
        redis.clone(),
        Duration::from_secs(1),
    );

    let result = sim.process_one().await.unwrap();

    // Connection failed
    assert!(!result.redis_acked);
    assert_eq!(redis.pending_count(), 1);
}

/// Transport failure: Recovery after consumer restart
#[tokio::test]
async fn transport_failure_consumer_restart() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);

    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // First command succeeds
    let r1 = sim.process_one().await.unwrap();
    assert!(r1.redis_acked);

    // Stop consumer
    consumer.shutdown();
    handle.abort();

    // Add another command
    redis.xadd(vec![2]);

    // Try to process while consumer is down
    let sim2 = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(1),
    );

    let r2 = sim2.process_one().await.unwrap();
    assert!(!r2.redis_acked, "Should fail while consumer is down");

    // One pending (the failed one)
    assert_eq!(redis.pending_count(), 1);
    assert_eq!(redis.ack_count(), 1);
}
