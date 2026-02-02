//! III. ACK on Consumer Approval & IV. No ACK on Consumer Rejection tests for Falco.
//!
//! Rules covered:
//! - 9. Consumer responds with ACK_REDIS
//! - 10. Falco emits exactly one Redis ACK
//! - 11. Redis ACK occurs after consumer response
//! - 12. Falco proceeds to the next command
//! - 13. Consumer responds with DO_NOT_ACK
//! - 14. Falco emits no Redis ACK
//! - 15. Command remains pending in Redis
//! - 16. Falco does not proceed to the next command (leaves it pending)

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use crate::protocol::Decision;
use std::sync::Arc;
use std::time::Duration;

// =============================================================================
// III. ACK on Consumer Approval
// =============================================================================

/// Rule 9: Consumer responds with ACK_REDIS
#[tokio::test]
async fn rule_09_consumer_responds_ack_redis() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
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

    assert_eq!(
        result.decision_received,
        Some(Decision::AckRedis),
        "Consumer should respond with ACK_REDIS"
    );

    consumer.shutdown();
    handle.abort();
}

/// Rule 10: Falco emits exactly one Redis ACK
#[tokio::test]
async fn rule_10_emits_exactly_one_ack() {
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

    let _result = sim.process_one().await.unwrap();

    // Exactly one ACK
    assert_eq!(redis.ack_count(), 1, "Should emit exactly one ACK");
    assert!(redis.was_acked(&msg_id), "Should ACK the correct message");

    consumer.shutdown();
    handle.abort();
}

/// Rule 11: Redis ACK occurs after consumer response
#[tokio::test]
async fn rule_11_ack_after_consumer_response() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    // Delay consumer response
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(100)));

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let start = std::time::Instant::now();
    let result = sim.process_one().await.unwrap();
    let elapsed = start.elapsed();

    // ACK should happen after response delay
    assert!(elapsed >= Duration::from_millis(100), "ACK should wait for consumer response");
    assert!(result.redis_acked, "Should ACK after response");
    assert!(redis.was_acked(&msg_id));

    consumer.shutdown();
    handle.abort();
}

/// Rule 12: Falco proceeds to the next command
#[tokio::test]
async fn rule_12_proceeds_to_next_command() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let id1 = redis.xadd(vec![1]);
    let id2 = redis.xadd(vec![2]);
    let id3 = redis.xadd(vec![3]);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process all three
    let result1 = sim.process_one().await.unwrap();
    let result2 = sim.process_one().await.unwrap();
    let result3 = sim.process_one().await.unwrap();

    assert_eq!(result1.message_id, id1);
    assert_eq!(result2.message_id, id2);
    assert_eq!(result3.message_id, id3);

    assert_eq!(redis.ack_count(), 3, "All three should be ACKed");
    assert_eq!(redis.pending_count(), 0, "No pending messages");

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// IV. No ACK on Consumer Rejection
// =============================================================================

/// Rule 13: Consumer responds with DO_NOT_ACK
#[tokio::test]
async fn rule_13_consumer_responds_do_not_ack() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::DoNotAck);
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

    assert_eq!(
        result.decision_received,
        Some(Decision::DoNotAck),
        "Consumer should respond with DO_NOT_ACK"
    );

    consumer.shutdown();
    handle.abort();
}

/// Rule 14: Falco emits no Redis ACK
#[tokio::test]
async fn rule_14_no_ack_emitted() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::DoNotAck);
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

    assert!(!result.redis_acked, "Should not ACK");
    assert_eq!(redis.ack_count(), 0, "No ACK should be emitted");

    consumer.shutdown();
    handle.abort();
}

/// Rule 15: Command remains pending in Redis
#[tokio::test]
async fn rule_15_command_remains_pending() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::DoNotAck);
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

    // Command should be in pending list
    assert_eq!(redis.pending_count(), 1, "Command should remain pending");
    let pending = redis.pending();
    assert_eq!(pending[0].message_id, msg_id);

    consumer.shutdown();
    handle.abort();
}

/// Rule 16: With DO_NOT_ACK, the command stays in PEL for redelivery
#[tokio::test]
async fn rule_16_command_available_for_redelivery() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    let msg_id = redis.xadd(vec![1, 2, 3]);

    // First attempt: DO_NOT_ACK
    consumer.queue_response(ConsumerResponse::DoNotAck);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result1 = sim.process_one().await.unwrap();
    assert!(!result1.redis_acked);
    assert_eq!(redis.pending_count(), 1);

    // Message is still in pending, available for redelivery
    // (In real Redis, XPENDING + XCLAIM would be used)
    let pending = redis.pending();
    assert_eq!(pending[0].message_id, msg_id);

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional ACK tests
// =============================================================================

/// ACK: Multiple commands, alternating ACK and DO_NOT_ACK
#[tokio::test]
async fn ack_alternating_decisions() {
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

    let r1 = sim.process_one().await.unwrap();
    let r2 = sim.process_one().await.unwrap();
    let r3 = sim.process_one().await.unwrap();

    assert!(r1.redis_acked);
    assert!(!r2.redis_acked);
    assert!(r3.redis_acked);

    assert_eq!(redis.ack_count(), 2);
    assert!(redis.was_acked(&id1));
    assert!(!redis.was_acked(&id2));
    assert!(redis.was_acked(&id3));

    consumer.shutdown();
    handle.abort();
}

/// ACK: Response with result data
#[tokio::test]
async fn ack_with_result_data() {
    let consumer = MockConsumer::new();
    consumer.queue_response(ConsumerResponse::AckRedisWithResult(vec![0xCA, 0xFE]));
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

    // Result data doesn't change ACK behavior
    assert!(result.redis_acked);
    assert_eq!(redis.ack_count(), 1);

    consumer.shutdown();
    handle.abort();
}

/// ACK: ACK order matches processing order
#[tokio::test]
async fn ack_order_matches_processing_order() {
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

    for _ in 0..5 {
        sim.process_one().await;
    }

    let ack_log = redis.ack_log();
    assert_eq!(ack_log, ids, "ACK order should match add order");

    consumer.shutdown();
    handle.abort();
}
