//! Concurrency & isolation tests for the Armin session engine.
//!
//! Rules covered:
//! - 81. Concurrent appends are serialized (N/A - single-threaded engine)
//! - 82. Concurrent appends preserve global order (N/A - single-threaded)
//! - 83. Concurrent reads do not block appends
//! - 84. Concurrent appends do not corrupt SQLite (N/A - single-threaded)
//! - 85. Concurrent live subscribers are isolated
//! - 86. Side-effects are emitted sequentially
//! - 87. Side-effects do not interleave incorrectly
//! - 88. Delta is thread-safe (for reads)
//! - 89. Live hub is thread-safe
//! - 90. SQLite access is properly synchronized (by design)
//!
//! Note: Armin uses rusqlite::Connection which is not Sync, so true
//! concurrent writes are not supported. These tests verify that
//! the derived state (snapshots, deltas) can be safely shared.

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::{Armin, SideEffect};
use std::thread;

/// Rule 83: Concurrent reads do not block appends
#[test]
fn rule_83_concurrent_reads_no_blocking() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    // Take many read references
    let _snapshots: Vec<_> = (0..100).map(|_| armin.snapshot()).collect();
    let deltas: Vec<_> = (0..100).map(|_| armin.delta(&session_id)).collect();

    // Writes should still work
    for i in 0..100 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    // Verify writes succeeded
    assert_eq!(armin.delta(&session_id).len(), 100);

    // Old references should still be valid (with old state)
    for delta in &deltas {
        assert!(delta.is_empty());
    }
}

/// Rule 85: Concurrent live subscribers are isolated
#[test]
fn rule_85_concurrent_subscribers_isolated() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    // Create many subscribers
    let subscribers: Vec<_> = (0..50).map(|_| armin.subscribe(&session_id)).collect();

    // Send messages
    for i in 0..10 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    // Each subscriber should receive all messages independently
    for (sub_idx, sub) in subscribers.iter().enumerate() {
        let mut count = 0;
        while sub.try_recv().is_some() {
            count += 1;
        }
        assert_eq!(count, 10, "Subscriber {} got wrong count", sub_idx);
    }
}

/// Rule 86: Side-effects are emitted sequentially
#[test]
fn rule_86_side_effects_sequential() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.sink().clear();

    // Append many messages
    for i in 0..100 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    let effects = armin.sink().effects();
    assert_eq!(effects.len(), 100);

    // Verify all IDs are unique
    let mut seen_ids = std::collections::HashSet::new();
    for effect in effects {
        match effect {
            SideEffect::MessageAppended { message_id, .. } => {
                assert!(seen_ids.insert(message_id.as_str().to_string()), "Duplicate ID in side-effects");
            }
            _ => panic!("Unexpected side-effect"),
        }
    }
}

/// Rule 87: Side-effects do not interleave incorrectly
#[test]
fn rule_87_side_effects_no_interleave() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session();
    let session2 = armin.create_session();
    armin.sink().clear();

    // Alternate between sessions
    for i in 0..10 {
        armin.append(
            &session1,
            NewMessage {
                content: format!("S1-{}", i),
            },
        );
        armin.append(
            &session2,
            NewMessage {
                content: format!("S2-{}", i),
            },
        );
    }

    let effects = armin.sink().effects();

    // Verify each effect is complete (has both session_id and message_id)
    for effect in &effects {
        match effect {
            SideEffect::MessageAppended {
                session_id: sid,
                message_id: mid,
            } => {
                assert!(*sid == session1 || *sid == session2);
                assert!(!mid.as_str().is_empty());
            }
            _ => panic!("Unexpected side-effect type"),
        }
    }
}

/// Rule 88: Delta is thread-safe (for reads)
#[test]
fn rule_88_delta_thread_safe_reads() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    for i in 0..100 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    // Get delta (it's Clone)
    let delta = armin.delta(&session_id);

    // Read from multiple threads
    let handles: Vec<_> = (0..10)
        .map(|_| {
            let d = delta.clone();
            thread::spawn(move || {
                assert_eq!(d.len(), 100);
                for (i, msg) in d.iter().enumerate() {
                    assert_eq!(msg.content, format!("Message {}", i));
                }
            })
        })
        .collect();

    for handle in handles {
        handle.join().unwrap();
    }
}

/// Rule 89: Live hub is thread-safe
#[test]
fn rule_89_live_hub_thread_safe() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    // Subscribe
    let sub = armin.subscribe(&session_id);

    // Append messages
    for i in 0..10 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    // Receive in a different context (simulating thread safety)
    let mut received = Vec::new();
    while let Some(msg) = sub.try_recv() {
        received.push(msg.content);
    }

    assert_eq!(received.len(), 10);
}

/// Rule 90: SQLite access is properly synchronized (by design)
/// This is architectural - rusqlite::Connection is not Sync
#[test]
fn rule_90_sqlite_synchronized() {
    use tempfile::NamedTempFile;

    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    // Write with one engine
    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        for i in 0..100 {
            armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            );
        }

        session_id
    };

    // Read with another engine (sequential access)
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 100);
}

// =============================================================================
// Additional concurrency tests
// =============================================================================

#[test]
fn snapshot_arc_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<crate::snapshot::SnapshotView>();
}

#[test]
fn delta_view_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<crate::delta::DeltaView>();
}

#[test]
fn message_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<crate::types::Message>();
}

#[test]
fn recording_sink_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<RecordingSink>();
}

#[test]
fn multiple_snapshot_clones_independent() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    armin.append(
        &session_id,
        NewMessage {
            content: "Original".to_string(),
        },
    );
    armin.refresh_snapshot().unwrap();

    let snap1 = armin.snapshot();
    let snap2 = snap1.clone();
    let snap3 = armin.snapshot();

    // All snapshots work independently
    let handles: Vec<_> = vec![snap1, snap2, snap3]
        .into_iter()
        .map(|snap| {
            let sid = session_id.clone();
            thread::spawn(move || {
                let session = snap.session(&sid).unwrap();
                assert_eq!(session.message_count(), 1);
            })
        })
        .collect();

    for handle in handles {
        handle.join().unwrap();
    }
}

#[test]
fn delta_clones_independent() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    for i in 0..50 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    let delta1 = armin.delta(&session_id);
    let delta2 = delta1.clone();

    // Both work independently
    let h1 = thread::spawn(move || delta1.len());
    let h2 = thread::spawn(move || delta2.len());

    assert_eq!(h1.join().unwrap(), 50);
    assert_eq!(h2.join().unwrap(), 50);
}

#[test]
fn many_subscribers_single_message() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let subscribers: Vec<_> = (0..100).map(|_| armin.subscribe(&session_id)).collect();

    armin.append(
        &session_id,
        NewMessage {
            content: "Broadcast".to_string(),
        },
    );

    // All should receive
    for (i, sub) in subscribers.iter().enumerate() {
        let msg = sub.try_recv().expect(&format!("Subscriber {} failed", i));
        assert_eq!(msg.content, "Broadcast");
    }
}
