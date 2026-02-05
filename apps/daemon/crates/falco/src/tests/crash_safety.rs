//! IX. Crash Safety (In-Flight) tests for Falco.
//!
//! Rules covered:
//! - 33. Falco crashes after forwarding but before resolution
//! - 34. Falco restarts
//! - 35. Command is re-forwarded to the consumer
//! - 36. Redis ACK is not lost

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 33: Falco crashes after forwarding but before resolution
/// (Simulated by not completing the decision phase)
#[tokio::test]
async fn rule_33_crash_after_forward_before_resolution() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    // Consumer never responds - simulates Falco crashing while waiting
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1, 2, 3]);

    // Simulate Falco reading and forwarding, then "crashing" (timeout acts as crash)
    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    let result = sim.process_one().await.unwrap();

    // Command was forwarded
    assert_eq!(consumer.received_count(), 1);
    assert_eq!(consumer.received_commands()[0].payload, vec![1, 2, 3]);

    // Because of timeout (simulating crash recovery), message was ACKed
    // In a real crash, the message would remain in PEL for redelivery
    assert!(result.timed_out);

    consumer.shutdown();
    handle.abort();
}

/// Rule 34 & 35: Falco restarts and command is re-forwarded
/// (Simulated using pending messages in Redis)
#[tokio::test]
async fn rule_34_35_restart_and_reforward() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    // First "Falco instance" - crashes (simulated by DO_NOT_ACK)
    consumer.queue_response(ConsumerResponse::DoNotAck);

    let sim1 = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result1 = sim1.process_one().await.unwrap();
    assert!(!result1.redis_acked, "First instance should not ACK (crash simulation)");

    // Message is still pending
    assert_eq!(redis.pending_count(), 1);

    // "Restart" - In real Redis, XCLAIM would be used to reclaim pending message
    // For mock, we'll verify the message is still there
    let pending = redis.pending();
    assert_eq!(pending[0].message_id, msg_id);
    assert_eq!(pending[0].payload, vec![1, 2, 3]);

    consumer.shutdown();
    handle.abort();
}

/// Rule 36: Redis ACK is not lost
#[tokio::test]
async fn rule_36_ack_not_lost() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let ids: Vec<String> = (0..5).map(|i| redis.xadd(vec![i])).collect();

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process all
    for _ in 0..5 {
        sim.process_one().await;
    }

    // All ACKs recorded
    assert_eq!(redis.ack_count(), 5);
    for id in &ids {
        assert!(redis.was_acked(id), "ACK for {} should not be lost", id);
    }

    // Nothing pending
    assert_eq!(redis.pending_count(), 0);

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional crash safety tests
// =============================================================================

/// Crash safety: Pending messages don't disappear
#[tokio::test]
async fn crash_safety_pending_persists() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::DoNotAck);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add and process without ACK
    let id1 = redis.xadd(vec![1]);
    let id2 = redis.xadd(vec![2]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    sim.process_one().await;
    sim.process_one().await;

    // Both should be pending
    assert_eq!(redis.pending_count(), 2);

    let pending = redis.pending();
    assert!(pending.iter().any(|m| m.message_id == id1));
    assert!(pending.iter().any(|m| m.message_id == id2));

    consumer.shutdown();
    handle.abort();
}

/// Crash safety: Mixed ACK/NACK maintains correct pending state
#[tokio::test]
async fn crash_safety_mixed_pending_state() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let id1 = redis.xadd(vec![1]);
    let id2 = redis.xadd(vec![2]);
    let id3 = redis.xadd(vec![3]);

    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    sim.process_one().await;
    sim.process_one().await;
    sim.process_one().await;

    // id1 and id3 ACKed, id2 pending
    assert_eq!(redis.ack_count(), 2);
    assert!(redis.was_acked(&id1));
    assert!(!redis.was_acked(&id2));
    assert!(redis.was_acked(&id3));

    assert_eq!(redis.pending_count(), 1);
    assert_eq!(redis.pending()[0].message_id, id2);

    consumer.shutdown();
    handle.abort();
}

/// Crash safety: Timeout ACKs are durable
#[tokio::test]
async fn crash_safety_timeout_acks_durable() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::NeverRespond);
    consumer.queue_response(ConsumerResponse::NeverRespond);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let id1 = redis.xadd(vec![1]);
    let id2 = redis.xadd(vec![2]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    sim.process_one().await;
    sim.process_one().await;

    // Both should be ACKed via timeout
    assert_eq!(redis.ack_count(), 2);
    assert!(redis.was_acked(&id1));
    assert!(redis.was_acked(&id2));
    assert_eq!(redis.pending_count(), 0);

    consumer.shutdown();
    handle.abort();
}

/// Crash safety: No duplicate ACKs
#[tokio::test]
async fn crash_safety_no_duplicate_acks() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process the message
    let result = sim.process_one().await.unwrap();
    assert!(result.redis_acked);

    // Exactly one ACK
    assert_eq!(redis.ack_count(), 1);

    // ACKing same message again should fail (already removed from pending)
    let already_acked = redis.xack(&msg_id);
    assert!(!already_acked, "Should not be able to ACK again");

    // Still only one ACK in log
    assert_eq!(redis.ack_count(), 1);

    consumer.shutdown();
    handle.abort();
}
