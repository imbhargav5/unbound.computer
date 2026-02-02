//! VI. Timeout (Escape Hatch) & VII. Late Consumer Response tests for Falco.
//!
//! Rules covered:
//! - 21. Consumer does not respond
//! - 22. Decision timeout expires
//! - 23. Falco emits exactly one Redis ACK
//! - 24. ACK is marked as timeout-derived
//! - 25. Consumer responds after timeout
//! - 26. Falco ignores late response
//! - 27. No additional Redis ACK is emitted
//! - 28. Falco state remains consistent

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use crate::protocol::Decision;
use std::sync::Arc;
use std::time::Duration;

// =============================================================================
// VI. Timeout (Escape Hatch)
// =============================================================================

/// Rule 21: Consumer does not respond
#[tokio::test]
async fn rule_21_consumer_no_response() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    // Use a short timeout for testing
    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200), // Short timeout
    );

    let result = sim.process_one().await.unwrap();

    // No decision received from consumer
    assert!(
        result.decision_received.is_none(),
        "Should not receive decision when consumer doesn't respond"
    );

    consumer.shutdown();
    handle.abort();
}

/// Rule 22: Decision timeout expires
#[tokio::test]
async fn rule_22_timeout_expires() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let timeout_duration = Duration::from_millis(200);
    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        timeout_duration,
    );

    let start = std::time::Instant::now();
    let result = sim.process_one().await.unwrap();
    let elapsed = start.elapsed();

    // Timeout should have occurred
    assert!(
        elapsed >= timeout_duration,
        "Should wait at least the timeout duration"
    );
    assert!(result.timed_out, "Should be marked as timed out");

    consumer.shutdown();
    handle.abort();
}

/// Rule 23: Falco emits exactly one Redis ACK (on timeout)
#[tokio::test]
async fn rule_23_emits_exactly_one_ack_on_timeout() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200),
    );

    let result = sim.process_one().await.unwrap();

    // Exactly one ACK even on timeout (fail-open)
    assert!(result.timed_out);
    assert!(result.redis_acked, "Should ACK on timeout (fail-open)");
    assert_eq!(redis.ack_count(), 1, "Should emit exactly one ACK");
    assert!(redis.was_acked(&msg_id));

    consumer.shutdown();
    handle.abort();
}

/// Rule 24: ACK is timeout-derived (timed_out flag)
#[tokio::test]
async fn rule_24_ack_marked_timeout_derived() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200),
    );

    let result = sim.process_one().await.unwrap();

    // The result indicates this was a timeout ACK
    assert!(result.timed_out, "Should be marked as timeout-derived");
    assert!(result.redis_acked);
    assert!(
        result.decision_received.is_none(),
        "No decision should be recorded"
    );

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// VII. Late Consumer Response
// =============================================================================

/// Rule 25: Consumer responds after timeout
#[tokio::test]
async fn rule_25_consumer_responds_after_timeout() {
    let consumer = MockConsumer::new();
    // Consumer will respond after 500ms, but timeout is 200ms
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(500)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200), // Timeout before consumer responds
    );

    let result = sim.process_one().await.unwrap();

    // Timeout occurred before consumer response
    assert!(result.timed_out);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Rule 26: Falco ignores late response
#[tokio::test]
async fn rule_26_ignores_late_response() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(500)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200),
    );

    let result = sim.process_one().await.unwrap();

    // Timed out, but ACKed anyway
    assert!(result.timed_out);
    assert!(result.decision_received.is_none(), "Late response should be ignored");

    consumer.shutdown();
    handle.abort();
}

/// Rule 27: No additional Redis ACK is emitted
#[tokio::test]
async fn rule_27_no_additional_ack() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(500)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200),
    );

    let _result = sim.process_one().await.unwrap();

    // Exactly one ACK from timeout
    assert_eq!(redis.ack_count(), 1);

    // Wait for late response
    tokio::time::sleep(Duration::from_millis(400)).await;

    // Still only one ACK (late response ignored)
    assert_eq!(redis.ack_count(), 1, "No additional ACK from late response");
    assert!(redis.was_acked(&msg_id));

    consumer.shutdown();
    handle.abort();
}

/// Rule 28: Falco state remains consistent
#[tokio::test]
async fn rule_28_state_remains_consistent() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // First command: timeout
    redis.xadd(vec![1]);
    consumer.queue_response(ConsumerResponse::NeverRespond);

    // Second command: normal ACK
    redis.xadd(vec![2]);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200),
    );

    // Process first (will timeout)
    let result1 = sim.process_one().await.unwrap();
    assert!(result1.timed_out);
    assert!(result1.redis_acked);

    // Process second (should work normally)
    let result2 = sim.process_one().await.unwrap();
    assert!(!result2.timed_out);
    assert!(result2.redis_acked);
    assert_eq!(result2.decision_received, Some(Decision::AckRedis));

    // State is consistent
    assert_eq!(redis.ack_count(), 2);
    assert_eq!(redis.pending_count(), 0);

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional timeout tests
// =============================================================================

/// Timeout: Configurable timeout duration
#[tokio::test]
async fn timeout_configurable_duration() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);

    // Short timeout
    let sim_short = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    let start = std::time::Instant::now();
    sim_short.process_one().await;
    let short_elapsed = start.elapsed();

    assert!(short_elapsed < Duration::from_millis(200));

    // Reset
    consumer.clear_received();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    redis.xadd(vec![2]);

    // Longer timeout
    let sim_long = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(300),
    );

    let start = std::time::Instant::now();
    sim_long.process_one().await;
    let long_elapsed = start.elapsed();

    assert!(long_elapsed >= Duration::from_millis(300));

    consumer.shutdown();
    handle.abort();
}

/// Timeout: Just-in-time response (no timeout)
#[tokio::test]
async fn timeout_just_in_time_response() {
    let consumer = MockConsumer::new();
    // Respond just before timeout
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(150)));
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(200), // Timeout at 200ms, response at 150ms
    );

    let result = sim.process_one().await.unwrap();

    // Response received before timeout
    assert!(!result.timed_out, "Should not timeout");
    assert_eq!(result.decision_received, Some(Decision::AckRedis));
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Timeout: Multiple consecutive timeouts
#[tokio::test]
async fn timeout_multiple_consecutive() {
    let consumer = MockConsumer::new();
    for _ in 0..3 {
        consumer.queue_response(ConsumerResponse::NeverRespond);
    }
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);
    redis.xadd(vec![3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    // All three should timeout
    for i in 0..3 {
        let result = sim.process_one().await.unwrap();
        assert!(result.timed_out, "Command {} should timeout", i);
        assert!(result.redis_acked);
    }

    // All were ACKed via timeout
    assert_eq!(redis.ack_count(), 3);

    consumer.shutdown();
    handle.abort();
}
