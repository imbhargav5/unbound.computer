//! XI. Content Agnosticism tests for Falco.
//!
//! Rules covered:
//! - 41. Payload contains random bytes
//! - 42. Falco forwards payload unchanged
//! - 43. Falco does not parse or inspect payload
//! - 44. Falco does not crash on malformed payload

use super::harness::{ConsumerResponse, FalcoCourierSim, MockConsumer, MockRedis};
use std::sync::Arc;
use std::time::Duration;

/// Rule 41: Payload contains random bytes
#[tokio::test]
async fn rule_41_random_bytes_payload() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Generate random-like bytes (all possible byte values)
    let random_payload: Vec<u8> = (0..1024).map(|i| ((i * 17 + 31) % 256) as u8).collect();
    redis.xadd(random_payload.clone());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    assert_eq!(result.payload_forwarded, random_payload);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Rule 42: Falco forwards payload unchanged
#[tokio::test]
async fn rule_42_payload_unchanged() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    let test_payloads: Vec<Vec<u8>> = vec![
        vec![],                                    // Empty
        vec![0x00],                                // Null byte
        vec![0xFF],                                // Max byte
        vec![0x00, 0xFF, 0x00, 0xFF],             // Alternating
        (0..=255).collect(),                       // All byte values
        vec![0x00; 1000],                          // Many nulls
        vec![0xFF; 1000],                          // Many max bytes
        b"Hello, World!".to_vec(),                 // ASCII
        "こんにちは".as_bytes().to_vec(),            // UTF-8 Japanese
        vec![0x89, 0x50, 0x4E, 0x47],             // PNG magic
        vec![0x7F, 0x45, 0x4C, 0x46],             // ELF magic
    ];

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for (i, expected) in test_payloads.into_iter().enumerate() {
        consumer.clear_received();
        redis.xadd(expected.clone());

        let result = sim.process_one().await.unwrap();

        assert_eq!(
            result.payload_forwarded, expected,
            "Payload {} should be unchanged",
            i
        );

        let received = consumer.received_commands();
        assert_eq!(
            received.last().unwrap().payload, expected,
            "Consumer should receive unchanged payload {}", i
        );
    }

    consumer.shutdown();
    handle.abort();
}

/// Rule 43: Falco does not parse or inspect payload
/// (Demonstrated by forwarding structurally invalid content)
#[tokio::test]
async fn rule_43_no_payload_inspection() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Invalid JSON
    redis.xadd(b"{invalid json".to_vec());

    // Invalid UTF-8
    redis.xadd(vec![0xFF, 0xFE, 0x00, 0x01]);

    // Random binary garbage
    redis.xadd(vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]);

    // Truncated message-looking data
    redis.xadd(b"message_type:".to_vec());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    // All should be forwarded successfully (no parsing errors)
    for _ in 0..4 {
        let result = sim.process_one().await.unwrap();
        assert!(result.redis_acked, "Should forward without parsing");
    }

    assert_eq!(consumer.received_count(), 4);

    consumer.shutdown();
    handle.abort();
}

/// Rule 44: Falco does not crash on malformed payload
#[tokio::test]
async fn rule_44_no_crash_on_malformed() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Payloads that might crash a naive parser
    let malformed_payloads: Vec<Vec<u8>> = vec![
        vec![],                                          // Empty
        vec![0x00],                                      // Single null
        vec![0x00; 10000],                               // Many nulls
        vec![0xFF; 10000],                               // Many 0xFF
        (0..10000).map(|i| (i % 256) as u8).collect(),  // Large sequential
        vec![0x00, 0x00, 0x00, 0x00],                   // Looks like length=0
        vec![0xFF, 0xFF, 0xFF, 0xFF],                   // Looks like huge length
        // Invalid UTF-8 sequences
        vec![0x80],
        vec![0xC0, 0xAF],
        vec![0xE0, 0x80, 0xAF],
        vec![0xF0, 0x80, 0x80, 0xAF],
        // Byte sequences that might confuse protocol parsers
        vec![0x01, 0x00, 0x00, 0x00],                   // Looks like frame type
        vec![0x02, 0x01, 0x00, 0x00],                   // Looks like decision
    ];

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for (i, payload) in malformed_payloads.into_iter().enumerate() {
        redis.xadd(payload.clone());

        // Should not panic
        let result = sim.process_one().await;
        assert!(result.is_some(), "Should not crash on payload {}", i);
        assert!(result.unwrap().redis_acked, "Should ACK malformed payload {}", i);
    }

    consumer.shutdown();
    handle.abort();
}

// =============================================================================
// Additional content agnosticism tests
// =============================================================================

/// Content: Binary payloads with embedded protocol bytes
#[tokio::test]
async fn content_embedded_protocol_bytes() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Payload that looks like a Falco frame inside
    let mut fake_frame = vec![
        0x10, 0x00, 0x00, 0x00, // fake length
        0x01,                   // fake FRAME_TYPE_COMMAND
        0x00, 0x00, 0x00,       // fake flags/reserved
    ];
    fake_frame.extend_from_slice(&[0; 16]); // fake UUID
    fake_frame.extend_from_slice(&[0x04, 0x00, 0x00, 0x00]); // fake payload len
    fake_frame.extend_from_slice(b"fake");

    redis.xadd(fake_frame.clone());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // Should forward the "fake frame" as payload, not interpret it
    assert_eq!(result.payload_forwarded, fake_frame);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Content: Maximum payload size
#[tokio::test]
async fn content_max_payload_size() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // 1MB payload
    let large_payload: Vec<u8> = (0..1_000_000).map(|i| (i % 256) as u8).collect();
    redis.xadd(large_payload.clone());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(30), // Longer timeout for large payload
    );

    let result = sim.process_one().await.unwrap();

    assert_eq!(result.payload_forwarded.len(), 1_000_000);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}

/// Content: Zero-length payloads are valid
#[tokio::test]
async fn content_zero_length_valid() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // Multiple empty payloads
    for _ in 0..5 {
        redis.xadd(vec![]);
    }

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    for _ in 0..5 {
        let result = sim.process_one().await.unwrap();
        assert!(result.payload_forwarded.is_empty());
        assert!(result.redis_acked);
    }

    assert_eq!(consumer.received_count(), 5);
    for cmd in consumer.received_commands() {
        assert!(cmd.payload.is_empty());
    }

    consumer.shutdown();
    handle.abort();
}

/// Content: Encrypted-looking payloads
#[tokio::test]
async fn content_encrypted_payloads() {
    if !super::harness::ensure_uds() { return; }
    let consumer = MockConsumer::new();
    consumer.set_default_response(ConsumerResponse::AckRedis);
    let handle = consumer.start().await;
    tokio::time::sleep(Duration::from_millis(50)).await;

    let redis = Arc::new(MockRedis::new("falco"));

    // High-entropy "encrypted" data
    let encrypted_payload: Vec<u8> = (0..256)
        .map(|i| ((i * 31 + 17) ^ (i * 7)) as u8)
        .collect();

    redis.xadd(encrypted_payload.clone());

    let sim = FalcoCourierSim::new(
        consumer.socket_path().clone(),
        redis.clone(),
        Duration::from_secs(5),
    );

    let result = sim.process_one().await.unwrap();

    // Encrypted data passed through unchanged
    assert_eq!(result.payload_forwarded, encrypted_payload);
    assert!(result.redis_acked);

    consumer.shutdown();
    handle.abort();
}
