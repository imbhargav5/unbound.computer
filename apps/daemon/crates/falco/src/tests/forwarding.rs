//! II. Forwarding Behavior tests for Falco.
//!
//! Rules covered:
//! - 5. When a command exists in Redis, Falco forwards exactly one command frame to the consumer
//! - 6. Forwarded payload bytes match Redis payload bytes exactly
//! - 7. Falco forwards at most one command at a time
//! - 8. Falco does not forward the next command before the current one resolves

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 5: When a command exists in Redis, Falco forwards exactly one command frame to the consumer
#[tokio::test]
async fn rule_05_forwards_exactly_one_frame() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let _msg_id = redis.xadd(vec![1, 2, 3, 4]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // Exactly one command was forwarded
    assert_eq!(consumer.received_count(), 1, "Should forward exactly one command");
    assert_eq!(result.payload_forwarded, vec![1, 2, 3, 4]);

    consumer.shutdown();
    handle.abort();
}

/// Rule 6: Forwarded payload bytes match Redis payload bytes exactly
#[tokio::test]
async fn rule_06_payload_bytes_match_exactly() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Test with various payloads
    let test_payloads: Vec<Vec<u8>> = vec![
        vec![],                           // Empty
        vec![0],                          // Single byte
        vec![0xFF],                       // Max byte
        (0..=255).collect(),              // All byte values
        vec![0; 10000],                   // Large payload
        vec![0xDE, 0xAD, 0xBE, 0xEF],    // Binary magic
    ];

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for (i, expected_payload) in test_payloads.into_iter().enumerate() {
        consumer.clear_received();
        redis.xadd(expected_payload.clone());

        let result = sim.process_one().await.unwrap();

        assert_eq!(
            result.payload_forwarded, expected_payload,
            "Payload {} should match exactly",
            i
        );

        let received = consumer.received_commands();
        assert_eq!(
            received.last().unwrap().payload, expected_payload,
            "Consumer received payload {} should match",
            i
        );
    }

    consumer.shutdown();
    handle.abort();
}

/// Rule 7: Falco forwards at most one command at a time
#[tokio::test]
async fn rule_07_at_most_one_command_at_a_time() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add multiple commands
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);
    redis.xadd(vec![3]);

    // Delay consumer response to ensure we can observe in-flight state
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process first command
    let result1 = sim.process_one().await.unwrap();
    assert_eq!(result1.payload_forwarded, vec![1]);

    // Only one should be received so far
    assert_eq!(consumer.received_count(), 1, "Only one command should be in-flight");

    // Process second
    let result2 = sim.process_one().await.unwrap();
    assert_eq!(result2.payload_forwarded, vec![2]);
    assert_eq!(consumer.received_count(), 2);

    // Process third
    let result3 = sim.process_one().await.unwrap();
    assert_eq!(result3.payload_forwarded, vec![3]);
    assert_eq!(consumer.received_count(), 3);

    consumer.shutdown();
    handle.abort();
}

/// Rule 8: Falco does not forward the next command before the current one resolves
#[tokio::test]
async fn rule_08_no_forward_before_resolution() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);

    // First command: delay before response
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(200)));
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Start processing first command
    let start = std::time::Instant::now();
    let result1 = sim.process_one().await.unwrap();
    let elapsed1 = start.elapsed();

    // First command should have waited for response
    assert!(elapsed1 >= Duration::from_millis(200), "Should wait for first command resolution");
    assert_eq!(result1.payload_forwarded, vec![1]);
    assert!(result1.redis_acked);

    // Second command can now proceed
    let start = std::time::Instant::now();
    let result2 = sim.process_one().await.unwrap();
    let elapsed2 = start.elapsed();

    // Second command should be fast (no delay)
    assert!(elapsed2 < Duration::from_millis(100), "Second command should be quick");
    assert_eq!(result2.payload_forwarded, vec![2]);
    assert!(result2.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Forwarding: Empty payload is forwarded correctly
#[tokio::test]
async fn forwarding_empty_payload() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();
    assert!(result.payload_forwarded.is_empty());
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Forwarding: Large payload is forwarded correctly
#[tokio::test]
async fn forwarding_large_payload() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // 64KB payload
    let large_payload: Vec<u8> = (0..65536).map(|i| (i % 256) as u8).collect();
    redis.xadd(large_payload.clone());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();
    assert_eq!(result.payload_forwarded.len(), 65536);
    assert_eq!(result.payload_forwarded, large_payload);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Forwarding: Command ID is unique per forward
#[tokio::test]
async fn forwarding_unique_command_ids() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    for i in 0..10 {
        redis.xadd(vec![i]);
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..10 {
        sim.process_one().await;
    }

    let received = consumer.received_commands();
    let command_ids: std::collections::HashSet<_> =
        received.iter().map(|r| r.command_id).collect();

    assert_eq!(command_ids.len(), 10, "All command IDs should be unique");

    consumer.shutdown();
    handle.abort();
}
