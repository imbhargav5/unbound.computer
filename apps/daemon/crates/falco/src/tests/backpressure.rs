//! V. Blocking & Backpressure tests for Falco.
//!
//! Rules covered:
//! - 17. Consumer delays response
//! - 18. Falco blocks waiting for resolution
//! - 19. Additional commands appended to Redis remain unread
//! - 20. Falco does not buffer commands locally

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 17: Consumer delays response
#[tokio::test]
async fn rule_17_consumer_delays_response() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(300)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let start = std::time::Instant::now();
    let result = sim.process_one().await.unwrap();
    let elapsed = start.elapsed();

    // Response was delayed
    assert!(
        elapsed >= Duration::from_millis(300),
        "Should wait for delayed response (took {:?})",
        elapsed
    );
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Rule 18: Falco blocks waiting for resolution
#[tokio::test]
async fn rule_18_blocks_waiting_for_resolution() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(500)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Start processing (will block)
    let start = std::time::Instant::now();
    let result = sim.process_one().await.unwrap();
    let elapsed = start.elapsed();

    // Falco blocked for the full delay
    assert!(elapsed >= Duration::from_millis(500));
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Rule 19: Additional commands appended to Redis remain unread
#[tokio::test]
async fn rule_19_additional_commands_unread() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(200)));
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]); // First command

    // Start processing first command
    let process_handle = {
        let sim = FalcoCourierSim::new(
            consumer.socket_path().clone(),
            redis.clone(),
            Duration::from_secs(5),
        );
        tokio::spawn(async move { sim.process_one().await })
    };

    // While first is in flight, add more commands
    tokio::time::sleep(Duration::from_millis(50)).await;
    redis.xadd(vec![2]);
    redis.xadd(vec![3]);

    // These additional commands should still be in the stream
    assert_eq!(redis.stream_len(), 2, "New commands should be unread in stream");

    // Wait for first to complete
    let _ = process_handle.await;

    // Now we can read the additional commands
    assert_eq!(redis.stream_len(), 2, "Commands still in stream after first completes");

    consumer.shutdown();
    handle.abort();
}

/// Rule 20: Falco does not buffer commands locally
#[tokio::test]
async fn rule_20_no_local_buffering() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add commands
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process one - should only read one from Redis
    let result = sim.process_one().await.unwrap();
    assert_eq!(result.payload_forwarded, vec![1]);

    // Only one command was read (no local buffer)
    assert_eq!(redis.stream_len(), 1, "Only one read from Redis, one remains");
    assert_eq!(redis.pending_count(), 0, "First was ACKed");

    // Process second
    let result = sim.process_one().await.unwrap();
    assert_eq!(result.payload_forwarded, vec![2]);

    consumer.shutdown();
    handle.abort();
}

/// Backpressure: Slow consumer doesn't cause command loss
#[tokio::test]
async fn backpressure_slow_consumer_no_loss() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add multiple commands
    let ids: Vec<String> = (0..5).map(|i| redis.xadd(vec![i])).collect();

    // Each command takes time
    for _ in 0..5 {
        consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process all
    for _ in 0..5 {
        let _ = sim.process_one().await;
    }

    // All should be ACKed despite slow processing
    assert_eq!(redis.ack_count(), 5);
    for id in &ids {
        assert!(redis.was_acked(id), "Message {} should be ACKed", id);
    }

    consumer.shutdown();
    handle.abort();
}

/// Backpressure: XREADGROUP blocks until data available
#[tokio::test]
async fn backpressure_read_blocks_until_data() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Empty stream - no commands yet
    assert_eq!(redis.stream_len(), 0);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Try to read from empty stream - returns None immediately in mock
    let result = sim.process_one().await;
    assert!(result.is_none(), "Should return None when stream empty");

    // Add a command
    redis.xadd(vec![1, 2, 3]);

    // Now read should work
    let result = sim.process_one().await;
    assert!(result.is_some());
    assert_eq!(result.unwrap().payload_forwarded, vec![1, 2, 3]);

    consumer.shutdown();
    handle.abort();
}

/// Backpressure: Sequential processing with varying delays
#[tokio::test]
async fn backpressure_varying_delays() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add commands with different response times
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);
    redis.xadd(vec![3]);

    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(50)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(200)));
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(10)));

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let start = std::time::Instant::now();

    // Process all
    sim.process_one().await;
    let after_first = start.elapsed();

    sim.process_one().await;
    let after_second = start.elapsed();

    sim.process_one().await;
    let after_third = start.elapsed();

    // Timing should reflect each command's delay
    assert!(after_first >= Duration::from_millis(50));
    assert!(after_second >= Duration::from_millis(250)); // 50 + 200
    assert!(after_third >= Duration::from_millis(260)); // 50 + 200 + 10

    consumer.shutdown();
    handle.abort();
}
