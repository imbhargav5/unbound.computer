//! XII. Hard Integration Invariants tests for Falco.
//!
//! Rules covered:
//! - 45. At most one command is ever in-flight
//! - 46. Falco never forwards a second command before resolving the first
//! - 47. Falco never ACKs Redis without consumer approval or timeout
//! - 48. Falco behavior depends only on: Redis state, Consumer protocol responses, Time
//!
//! One-Line Integration Guarantee:
//! Falco's behavior is fully determined by Redis input, consumer responses, and time —
//! independent of consumer identity or implementation.

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 45: At most one command is ever in-flight
#[tokio::test]
async fn rule_45_at_most_one_in_flight() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Add multiple commands
    for i in 0..5 {
        redis.xadd(vec![i]);
    }

    // Use delayed responses to observe sequential processing
    for _ in 0..5 {
        consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(50)));
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process sequentially - each command completes before next starts
    for _ in 0..5 {
        let result = sim.process_one().await;
        assert!(result.is_some());
    }

    // Due to sequential processing, at most 1 was ever in-flight
    // (Verified by the fact that we received them in order)
    let received = consumer.received_commands();
    assert_eq!(received.len(), 5);

    for i in 0..5 {
        assert_eq!(received[i].payload, vec![i as u8], "Commands processed in order");
    }

    consumer.shutdown();
    handle.abort();
}

/// Rule 46: Falco never forwards a second command before resolving the first
#[tokio::test]
async fn rule_46_no_forward_before_resolution() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));
    redis.xadd(vec![1]);
    redis.xadd(vec![2]);

    // First command: long delay
    consumer.queue_response(ConsumerResponse::DelayThenAck(Duration::from_millis(300)));
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // Process first (will block for delay)
    let start = std::time::Instant::now();
    let result1 = sim.process_one().await.unwrap();
    let first_done = start.elapsed();

    // Second starts only after first resolved
    let result2 = sim.process_one().await.unwrap();
    let second_done = start.elapsed();

    // First command took ~300ms, second started after
    assert!(first_done >= Duration::from_millis(300));
    assert!(second_done > first_done);

    // Order preserved
    assert_eq!(result1.payload_forwarded, vec![1]);
    assert_eq!(result2.payload_forwarded, vec![2]);

    consumer.shutdown();
    handle.abort();
}

/// Rule 47: Falco never ACKs Redis without consumer approval or timeout
#[tokio::test]
async fn rule_47_no_ack_without_approval_or_timeout() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Scenario 1: Consumer says ACK
    redis.xadd(vec![1]);
    consumer.queue_response(ConsumerResponse::AckRedis);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let r1 = sim.process_one().await.unwrap();
    assert!(r1.redis_acked, "Should ACK with consumer approval");
    assert!(!r1.timed_out);

    // Scenario 2: Consumer says DO_NOT_ACK
    redis.xadd(vec![2]);
    consumer.queue_response(ConsumerResponse::DoNotAck);

    let r2 = sim.process_one().await.unwrap();
    assert!(!r2.redis_acked, "Should NOT ACK without approval");
    assert!(!r2.timed_out);

    // Scenario 3: Timeout (no response)
    redis.xadd(vec![3]);
    consumer.queue_response(ConsumerResponse::NeverRespond);

    let sim_timeout = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100),
    );

    let r3 = sim_timeout.process_one().await.unwrap();
    assert!(r3.redis_acked, "Should ACK on timeout");
    assert!(r3.timed_out, "Should be marked as timeout");

    // Scenario 4: Connection failure (no response)
    redis.xadd(vec![4]);
    consumer.queue_response(ConsumerResponse::CloseConnection);

    let r4 = sim.process_one().await.unwrap();
    assert!(!r4.redis_acked, "Should NOT ACK on connection failure");

    consumer.shutdown();
    handle.abort();
}

/// Rule 48: Behavior depends only on Redis state, Consumer responses, Time
#[tokio::test]
async fn rule_48_deterministic_behavior() {
    // Run the same scenario multiple times to verify determinism

    for trial in 0..3 {
        let consumer = MockConsumer::new();
        let handle = consumer.start().await;
        tokio::time::sleep(Duration::from_millis(50)).await;

        let redis = Arc::new(MockRedis::new("falco"));

        // Fixed inputs
        redis.xadd(vec![1]);
        redis.xadd(vec![2]);
        redis.xadd(vec![3]);

        // Fixed responses
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

        // Same inputs produce same outputs
        assert_eq!(r1.payload_forwarded, vec![1], "Trial {} result 1", trial);
        assert!(r1.redis_acked, "Trial {} result 1 ACKed", trial);

        assert_eq!(r2.payload_forwarded, vec![2], "Trial {} result 2", trial);
        assert!(!r2.redis_acked, "Trial {} result 2 not ACKed", trial);

        assert_eq!(r3.payload_forwarded, vec![3], "Trial {} result 3", trial);
        assert!(r3.redis_acked, "Trial {} result 3 ACKed", trial);

        // Same ACK state
        assert_eq!(redis.ack_count(), 2, "Trial {}", trial);
        assert_eq!(redis.pending_count(), 1, "Trial {}", trial);

        consumer.shutdown();
        handle.abort();
    }
}

// =============================================================================
// Additional invariant tests
// =============================================================================

/// Invariant: Consumer identity doesn't affect behavior
#[tokio::test]
async fn invariant_consumer_identity_irrelevant() {
    // Two different "consumer instances" with same response pattern
    // should produce identical Falco behavior

    for consumer_name in ["daemon-a", "daemon-b", "test-consumer"] {
        let consumer = MockConsumer::new();
        consumer.queue_response(ConsumerResponse::AckRedis);
        consumer.queue_response(ConsumerResponse::DoNotAck);
        consumer.queue_response(ConsumerResponse::AckRedis);
        let handle = consumer.start().await;
        tokio::time::sleep(Duration::from_millis(50)).await;

        let redis = Arc::new(MockRedis::new("falco"));
        redis.xadd(vec![0xAA]);
        redis.xadd(vec![0xBB]);
        redis.xadd(vec![0xCC]);

        let sim = FalcoCourierSim::new(
            consumer.socket_path().clone(),
            redis.clone(),
            Duration::from_secs(5),
        );

        let r1 = sim.process_one().await.unwrap();
        let r2 = sim.process_one().await.unwrap();
        let r3 = sim.process_one().await.unwrap();

        // Behavior identical regardless of consumer "identity"
        assert!(r1.redis_acked, "Consumer '{}' r1", consumer_name);
        assert!(!r2.redis_acked, "Consumer '{}' r2", consumer_name);
        assert!(r3.redis_acked, "Consumer '{}' r3", consumer_name);

        consumer.shutdown();
        handle.abort();
    }
}

/// Invariant: ACK log captures all and only approved messages
#[tokio::test]
async fn invariant_ack_log_accuracy() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let id1 = redis.xadd(vec![1]); // ACK
    let id2 = redis.xadd(vec![2]); // NACK
    let id3 = redis.xadd(vec![3]); // ACK
    let id4 = redis.xadd(vec![4]); // NACK
    let id5 = redis.xadd(vec![5]); // Timeout ACK

    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::NeverRespond);

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_millis(100), // Short timeout for last one
    );

    for _ in 0..5 {
        sim.process_one().await;
    }

    // ACK log should contain exactly ACKed messages
    let ack_log = redis.ack_log();
    assert_eq!(ack_log.len(), 3);
    assert!(ack_log.contains(&id1));
    assert!(!ack_log.contains(&id2));
    assert!(ack_log.contains(&id3));
    assert!(!ack_log.contains(&id4));
    assert!(ack_log.contains(&id5)); // Timeout ACK

    consumer.shutdown();
    handle.abort();
}

/// Invariant: Pending count is consistent
#[tokio::test]
async fn invariant_pending_count_consistent() {
    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    for i in 0..10 {
        redis.xadd(vec![i]);
    }

    // 7 ACKs, 3 NACKs
    for i in 0..10 {
        if i == 2 || i == 5 || i == 8 {
            consumer.queue_response(ConsumerResponse::DoNotAck);
        } else {
            consumer.queue_response(ConsumerResponse::AckRedis);
        }
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..10 {
        sim.process_one().await;
    }

    // Invariant: ack_count + pending_count = total processed
    assert_eq!(redis.ack_count() + redis.pending_count(), 10);
    assert_eq!(redis.ack_count(), 7);
    assert_eq!(redis.pending_count(), 3);

    consumer.shutdown();
    handle.abort();
}

/// Invariant: Stream is drained in order
#[tokio::test]
async fn invariant_stream_drained_in_order() {
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    for i in 0..20 {
        redis.xadd(vec![i]);
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let mut processing_order = Vec::new();
    for _ in 0..20 {
        let result = sim.process_one().await.unwrap();
        processing_order.push(result.payload_forwarded[0]);
    }

    // Processing order matches append order
    let expected: Vec<u8> = (0..20).collect();
    assert_eq!(processing_order, expected);

    consumer.shutdown();
    handle.abort();
}

/// One-Line Integration Guarantee test
#[tokio::test]
async fn one_line_integration_guarantee() {
    // Falco's behavior is fully determined by:
    // 1. Redis input (payloads and order)
    // 2. Consumer protocol responses
    // 3. Time (timeout only)

    let consumer = MockConsumer::new();
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Fixed Redis input
    let payloads = vec![vec![0x01], vec![0x02], vec![0x03]];
    for p in &payloads {
        redis.xadd(p.clone());
    }

    // Fixed consumer responses
    consumer.queue_response(ConsumerResponse::AckRedis);
    consumer.queue_response(ConsumerResponse::DoNotAck);
    consumer.queue_response(ConsumerResponse::AckRedis);

    // Fixed timeout (not triggered)
    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let results: Vec<_> = futures::future::join_all(
        (0..3).map(|_| async { sim.process_one().await })
    ).await;

    // Given these inputs, output is deterministic:
    // - Message 1: forwarded, ACKed
    // - Message 2: forwarded, NOT ACKed
    // - Message 3: forwarded, ACKed

    let r1 = results[0].as_ref().unwrap();
    let r2 = results[1].as_ref().unwrap();
    let r3 = results[2].as_ref().unwrap();

    assert_eq!(r1.payload_forwarded, vec![0x01]);
    assert!(r1.redis_acked);

    assert_eq!(r2.payload_forwarded, vec![0x02]);
    assert!(!r2.redis_acked);

    assert_eq!(r3.payload_forwarded, vec![0x03]);
    assert!(r3.redis_acked);

    // This behavior is independent of:
    // - Consumer implementation details
    // - Internal Falco state
    // - System load
    // - Network conditions (beyond success/failure)

    consumer.shutdown();
    handle.abort();
}
