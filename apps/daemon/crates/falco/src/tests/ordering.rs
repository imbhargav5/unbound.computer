//! VIII. Ordering Guarantees tests for Falco.
//!
//! Rules covered:
//! - 29. Multiple commands appended to Redis
//! - 30. Consumer resolves commands sequentially
//! - 31. Falco forwards commands strictly in append order
//! - 32. Redis ACK order matches append order

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 29: Multiple commands appended to Redis
#[tokio::test]
async fn rule_29_multiple_commands_appended() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Append multiple commands
    let ids: Vec<String> = (0..10).map(|i| redis.xadd(vec![i])).collect();

    assert_eq!(redis.stream_len(), 10);

    // IDs should be monotonically increasing
    for i in 1..ids.len() {
        let prev: u64 = ids[i - 1].split('-').next().unwrap().parse().unwrap();
        let curr: u64 = ids[i].split('-').next().unwrap().parse().unwrap();
        assert!(curr > prev, "IDs should be monotonically increasing");
    }

    consumer.shutdown();
    handle.abort();
}

/// Rule 30: Consumer resolves commands sequentially
#[tokio::test]
async fn rule_30_sequential_resolution() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    for i in 0..5 {
        redis.xadd(vec![i]);
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process all commands
    for _ in 0..5 {
        sim.process_one().await;
    }

    // Consumer received them in order
    let received = consumer.received_commands();
    assert_eq!(received.len(), 5);

    for (i, cmd) in received.iter().enumerate() {
        assert_eq!(cmd.payload, vec![i as u8], "Command {} should have payload {}", i, i);
    }

    consumer.shutdown();
    handle.abort();
}

/// Rule 31: Falco forwards commands strictly in append order
#[tokio::test]
async fn rule_31_forwards_in_append_order() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add commands with distinct payloads
    let payloads: Vec<Vec<u8>> = vec![
        vec![0xAA],
        vec![0xBB],
        vec![0xCC],
        vec![0xDD],
        vec![0xEE],
    ];

    for payload in &payloads {
        redis.xadd(payload.clone());
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let mut forwarded: Vec<Vec<u8>> = Vec::new();
    for _ in 0..5 {
        let result = sim.process_one().await.unwrap();
        forwarded.push(result.payload_forwarded);
    }

    // Order should match append order
    assert_eq!(forwarded, payloads);

    consumer.shutdown();
    handle.abort();
}

/// Rule 32: Redis ACK order matches append order
#[tokio::test]
async fn rule_32_ack_order_matches_append_order() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let ids: Vec<String> = (0..10).map(|i| redis.xadd(vec![i])).collect();

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..10 {
        sim.process_one().await;
    }

    // ACK order should match append order
    let ack_log = redis.ack_log();
    assert_eq!(ack_log, ids, "ACK order should match append order");

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional ordering tests
// =============================================================================

/// Ordering: FIFO guarantee even with varying response times
#[tokio::test]
async fn ordering_fifo_with_varying_delays() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add commands
    let ids: Vec<String> = (0..5).map(|i| redis.xadd(vec![i])).collect();

    // Varying response times
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(10)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(50)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(5)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(200)));

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..5 {
        sim.process_one().await;
    }

    // Despite varying delays, order is preserved
    let ack_log = redis.ack_log();
    assert_eq!(ack_log, ids, "FIFO order preserved despite varying delays");

    consumer.shutdown();
    handle.abort();
}

/// Ordering: Interleaved ACK/NACK preserves order for ACKed messages
#[tokio::test]
async fn ordering_interleaved_ack_nack() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let id0 = redis.xadd(vec![0]);
    let _id1 = redis.xadd(vec![1]); // Will be NAKed
    let id2 = redis.xadd(vec![2]);
    let _id3 = redis.xadd(vec![3]); // Will be NAKed
    let id4 = redis.xadd(vec![4]);

    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..5 {
        sim.process_one().await;
    }

    // Only ACKed messages in ACK log, in order
    let ack_log = redis.ack_log();
    assert_eq!(ack_log, vec![id0, id2, id4]);

    consumer.shutdown();
    handle.abort();
}

/// Ordering: Timeout doesn't break order
#[tokio::test]
async fn ordering_timeout_preserves_order() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let id0 = redis.xadd(vec![0]);
    let id1 = redis.xadd(vec![1]); // Will timeout
    let id2 = redis.xadd(vec![2]);

    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::NeverRespond); // Timeout
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    for _ in 0..3 {
        sim.process_one().await;
    }

    // All ACKed (including timeout), in order
    let ack_log = redis.ack_log();
    assert_eq!(ack_log, vec![id0, id1, id2]);

    consumer.shutdown();
    handle.abort();
}

/// Ordering: Large number of commands maintains order
#[tokio::test]
async fn ordering_large_command_count() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let count = 100;
    let ids: Vec<String> = (0..count).map(|i| redis.xadd(vec![(i % 256) as u8])).collect();

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..count {
        sim.process_one().await;
    }

    let ack_log = redis.ack_log();
    assert_eq!(ack_log.len(), count);
    assert_eq!(ack_log, ids);

    consumer.shutdown();
    handle.abort();
}

/// Ordering: Consumer receives in same order as Redis
#[tokio::test]
async fn ordering_consumer_receives_in_order() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let expected_payloads: Vec<Vec<u8>> = (0..20).map(|i| vec![i]).collect();
    for payload in &expected_payloads {
        redis.xadd(payload.clone());
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..20 {
        sim.process_one().await;
    }

    let received = consumer.received_commands();
    let received_payloads: Vec<Vec<u8>> = received.iter().map(|r| r.payload.clone()).collect();

    assert_eq!(received_payloads, expected_payloads);

    consumer.shutdown();
    handle.abort();
}
