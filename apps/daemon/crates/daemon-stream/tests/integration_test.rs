//! Integration tests for daemon-stream.
//!
//! These tests verify the end-to-end behavior of the shared memory streaming
//! implementation across producer and consumer.

#![cfg(unix)] // Only run on Unix platforms

use std::thread;
use std::time::Duration;

use daemon_stream::{EventType, StreamConsumer, StreamProducer, StreamResult};

fn unique_session_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

#[test]
fn test_basic_producer_consumer() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write and read a single event
    producer.write_event(EventType::ClaudeEvent, 1, b"hello")?;

    let event = consumer.try_read().expect("should have event");
    assert_eq!(event.event_type, EventType::ClaudeEvent);
    assert_eq!(event.sequence, 1);
    assert_eq!(event.payload, b"hello");

    Ok(())
}

#[test]
fn test_high_throughput() -> StreamResult<()> {
    let session_id = unique_session_id();
    let event_count = 200; // Keep within default buffer size (256 slots)

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write events (staying within buffer size)
    for i in 0..event_count {
        producer.write_event(EventType::ClaudeEvent, i, &i.to_le_bytes())?;
    }

    // Read all events
    let mut read_count = 0;
    while let Some(event) = consumer.try_read() {
        assert_eq!(event.sequence, read_count);
        read_count += 1;
    }

    assert_eq!(read_count, event_count);
    Ok(())
}

#[test]
fn test_concurrent_producer_consumer() -> StreamResult<()> {
    let session_id = unique_session_id();
    let event_count = 200; // Keep within buffer size

    let producer = StreamProducer::new(&session_id)?;

    // Spawn consumer in another thread
    let session_id_clone = session_id.clone();
    let consumer_handle = thread::spawn(move || {
        let mut consumer = StreamConsumer::open(&session_id_clone).unwrap();
        let mut received = 0;

        // Read with timeout to handle timing
        loop {
            if let Some(_event) = consumer.try_read() {
                received += 1;
                if received >= event_count {
                    break;
                }
            } else if consumer.is_shutdown() {
                break;
            } else {
                thread::sleep(Duration::from_micros(100));
            }
        }

        received
    });

    // Give consumer time to start
    thread::sleep(Duration::from_millis(10));

    // Produce events
    for i in 0..event_count {
        producer.write_event(EventType::ClaudeEvent, i as i64, b"data")?;
    }

    // Wait for consumer
    let received = consumer_handle.join().expect("consumer thread panicked");
    assert_eq!(received, event_count);

    Ok(())
}

#[test]
fn test_large_payloads() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Create a large payload (close to slot size limit)
    let large_payload = vec![b'x'; 3000]; // Under 4040 byte limit

    producer.write_event(EventType::ClaudeEvent, 1, &large_payload)?;

    let event = consumer.try_read().expect("should have event");
    assert_eq!(event.payload.len(), large_payload.len());
    assert_eq!(event.payload, large_payload);
    assert!(!event.truncated);

    Ok(())
}

#[test]
fn test_payload_truncation() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Create a payload larger than slot size
    let huge_payload = vec![b'x'; 5000]; // Over 4040 byte limit

    producer.write_event(EventType::ClaudeEvent, 1, &huge_payload)?;

    let event = consumer.try_read().expect("should have event");
    assert!(event.truncated);
    assert!(event.payload.len() < huge_payload.len());

    Ok(())
}

#[test]
fn test_multiple_event_types() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write different event types
    producer.write_event(EventType::ClaudeEvent, 1, b"claude")?;
    producer.write_event(EventType::TerminalOutput, 2, b"terminal")?;
    producer.write_event(EventType::StreamingChunk, 3, b"chunk")?;
    producer.write_event(EventType::Ping, 4, b"")?;

    // Read and verify
    let e1 = consumer.try_read().unwrap();
    assert_eq!(e1.event_type, EventType::ClaudeEvent);

    let e2 = consumer.try_read().unwrap();
    assert_eq!(e2.event_type, EventType::TerminalOutput);

    let e3 = consumer.try_read().unwrap();
    assert_eq!(e3.event_type, EventType::StreamingChunk);

    let e4 = consumer.try_read().unwrap();
    assert_eq!(e4.event_type, EventType::Ping);

    Ok(())
}

#[test]
fn test_shutdown_propagation() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let consumer = StreamConsumer::open(&session_id)?;

    assert!(!consumer.is_shutdown());

    producer.shutdown();

    assert!(consumer.is_shutdown());

    Ok(())
}

#[test]
fn test_consumer_skip_to_latest() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write some events
    for i in 0..100 {
        producer.write_event(EventType::ClaudeEvent, i, b"old")?;
    }

    // Skip to latest
    let skipped = consumer.skip_to_latest();
    assert_eq!(skipped, 100);

    // Write new event
    producer.write_event(EventType::ClaudeEvent, 999, b"new")?;

    // Should only get the new one
    let event = consumer.try_read().unwrap();
    assert_eq!(event.sequence, 999);

    Ok(())
}

#[test]
fn test_batch_reading() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write events
    for i in 0..100 {
        producer.write_event(EventType::ClaudeEvent, i, b"data")?;
    }

    // Read in batches
    let batch1 = consumer.read_batch(30);
    assert_eq!(batch1.len(), 30);

    let batch2 = consumer.read_batch(30);
    assert_eq!(batch2.len(), 30);

    // Read remaining
    let remaining = consumer.read_all();
    assert_eq!(remaining.len(), 40);

    Ok(())
}

#[test]
fn test_json_payload() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    let json = r#"{"type":"assistant","message":{"content":"Hello!"}}"#;
    producer.write_json_event(1, json)?;

    let event = consumer.try_read().unwrap();
    assert_eq!(event.event_type, EventType::ClaudeEvent);
    assert_eq!(event.payload_str().unwrap(), json);

    Ok(())
}

#[test]
fn test_terminal_events() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write terminal output
    producer.write_terminal_output(1, "$ ls\n")?;
    producer.write_terminal_output(2, "file1.txt\nfile2.txt\n")?;
    producer.write_terminal_finished(3, 0)?;

    // Read events
    let e1 = consumer.try_read().unwrap();
    assert_eq!(e1.event_type, EventType::TerminalOutput);
    assert_eq!(e1.payload_str().unwrap(), "$ ls\n");

    let e2 = consumer.try_read().unwrap();
    assert_eq!(e2.event_type, EventType::TerminalOutput);

    let e3 = consumer.try_read().unwrap();
    assert_eq!(e3.event_type, EventType::TerminalFinished);
    // Exit code is stored as i32 little-endian
    let exit_code = i32::from_le_bytes(e3.payload[..4].try_into().unwrap());
    assert_eq!(exit_code, 0);

    Ok(())
}

#[test]
fn test_producer_dropped_before_consumer() -> StreamResult<()> {
    let session_id = unique_session_id();

    let producer = StreamProducer::new(&session_id)?;
    let consumer = StreamConsumer::open(&session_id)?;

    // Drop producer
    drop(producer);

    // Consumer should see shutdown
    assert!(consumer.is_shutdown());

    Ok(())
}

#[test]
fn test_wrap_around() -> StreamResult<()> {
    // Use small buffer to test wrap-around
    let session_id = unique_session_id();

    // Create producer with small slot count (16 slots)
    let producer = StreamProducer::with_config(&session_id, 4096, 16)?;
    let mut consumer = StreamConsumer::open(&session_id)?;

    // Write and read interleaved to test wrap-around without buffer full
    let mut written = 0i64;
    let mut read_count = 0i64;

    for _ in 0..100 {
        // Write up to 8 events
        for _ in 0..8 {
            if producer.pending_events() < 15 {
                producer.write_event(EventType::ClaudeEvent, written, b"wrap")?;
                written += 1;
            }
        }

        // Read available events
        while let Some(event) = consumer.try_read() {
            assert_eq!(event.sequence, read_count);
            read_count += 1;
        }
    }

    // Drain remaining
    while let Some(event) = consumer.try_read() {
        assert_eq!(event.sequence, read_count);
        read_count += 1;
    }

    assert_eq!(read_count, written);

    Ok(())
}

/// Benchmark-style test to measure throughput
#[test]
#[ignore] // Run with --ignored for benchmarks
fn bench_throughput() -> StreamResult<()> {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

    let session_id = unique_session_id();
    let event_count: i64 = 100_000;

    let producer = Arc::new(StreamProducer::new(&session_id)?);
    let done = Arc::new(AtomicBool::new(false));
    let written = Arc::new(AtomicU64::new(0));
    let read_count = Arc::new(AtomicU64::new(0));

    let payload = vec![b'x'; 1000]; // 1KB payload

    // Spawn consumer thread
    let session_clone = session_id.clone();
    let done_clone = done.clone();
    let read_count_clone = read_count.clone();
    let consumer_handle = thread::spawn(move || {
        let mut consumer = StreamConsumer::open(&session_clone).unwrap();
        let mut count = 0u64;

        while !done_clone.load(Ordering::Relaxed) || consumer.has_events() {
            while let Some(_) = consumer.try_read() {
                count += 1;
            }
            if !done_clone.load(Ordering::Relaxed) {
                thread::sleep(Duration::from_micros(10));
            }
        }

        read_count_clone.store(count, Ordering::Release);
    });

    // Give consumer time to start
    thread::sleep(Duration::from_millis(5));

    let start = std::time::Instant::now();

    // Write events, waiting if buffer full
    let mut i = 0i64;
    while i < event_count {
        match producer.write_event(EventType::ClaudeEvent, i, &payload) {
            Ok(_) => {
                i += 1;
                written.fetch_add(1, Ordering::Relaxed);
            }
            Err(daemon_stream::StreamError::BufferFull) => {
                // Brief pause to let consumer catch up
                thread::sleep(Duration::from_micros(1));
            }
            Err(e) => return Err(e),
        }
    }

    let write_time = start.elapsed();

    // Signal done and wait for consumer
    done.store(true, Ordering::Release);
    consumer_handle.join().expect("consumer thread panicked");

    let total_time = start.elapsed();
    let final_read_count = read_count.load(Ordering::Acquire);

    assert_eq!(final_read_count, event_count as u64);

    let total_bytes = event_count as u64 * payload.len() as u64;
    let throughput = total_bytes as f64 / total_time.as_secs_f64() / 1_000_000.0;

    println!("Events: {}", event_count);
    println!("Payload size: {} bytes", payload.len());
    println!("Total data: {} MB", total_bytes / 1_000_000);
    println!("Write time: {:?}", write_time);
    println!("Total time (write + read): {:?}", total_time);
    println!("Throughput: {:.2} MB/s", throughput);
    println!(
        "Latency per event: {:.2}µs",
        total_time.as_nanos() as f64 / event_count as f64 / 1000.0
    );

    Ok(())
}
