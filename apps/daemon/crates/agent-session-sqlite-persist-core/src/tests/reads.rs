//! Read path purity tests for the Armin session engine.
//!
//! Rules covered:
//! - 51. Read operations never emit side-effects
//! - 52. Read operations never write to SQLite
//! - 53. Read operations never modify delta
//! - 54. Read operations never notify live subscribers
//! - 55. Read operations are deterministic
//! - 56. Read operations are repeatable
//! - 57. Concurrent reads are safe
//! - 58. Reads tolerate snapshot replacement
//! - 59. Reads tolerate delta growth
//! - 60. Reads do not block writes

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::Armin;
use std::thread;

/// Rule 51: Read operations never emit side-effects
#[test]
fn rule_51_reads_never_emit_side_effects() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Test".to_string(),
            },
        )
        .unwrap();

    armin.sink().clear();

    // All read operations
    let _ = armin.snapshot();
    let _ = armin.delta(&session_id);
    let _ = armin.subscribe(&session_id);

    let snapshot = armin.snapshot();
    if let Some(session) = snapshot.session(&session_id) {
        let _ = session.id();
        let _ = session.messages();
        let _ = session.message_count();
        let _ = session.is_closed();
    }

    let delta = armin.delta(&session_id);
    let _ = delta.len();
    let _ = delta.is_empty();
    let _ = delta.messages();
    for _ in delta.iter() {}

    assert!(
        armin.sink().is_empty(),
        "Reads should never emit side-effects"
    );
}

/// Rule 52: Read operations never write to SQLite
/// (Verified by design - reads don't have mutable access)
#[test]
fn rule_52_reads_never_write_sqlite() {
    use tempfile::NamedTempFile;

    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session().unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "Original".to_string(),
                },
            )
            .unwrap();
        session_id
    };

    // Perform reads
    {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();

        // Many read operations
        for _ in 0..100 {
            let _ = armin.snapshot();
            let _ = armin.delta(&session_id);
        }
    }

    // Verify SQLite unchanged
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "Original");
}

/// Rule 53: Read operations never modify delta
#[test]
fn rule_53_reads_never_modify_delta() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Test".to_string(),
            },
        )
        .unwrap();

    // Many reads
    for _ in 0..100 {
        let delta = armin.delta(&session_id);
        let _ = delta.len();
        for _ in delta.iter() {}
    }

    // Delta should still have 1 message
    assert_eq!(armin.delta(&session_id).len(), 1);
}

/// Rule 54: Read operations never notify live subscribers
#[test]
fn rule_54_reads_never_notify_subscribers() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    // Perform reads
    for _ in 0..100 {
        let _ = armin.snapshot();
        let _ = armin.delta(&session_id);
    }

    // Subscriber should not have received anything
    assert!(
        sub.try_recv().is_none(),
        "Reads should not notify subscribers"
    );
}

/// Rule 55: Read operations are deterministic
#[test]
fn rule_55_reads_are_deterministic() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    for i in 0..10 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    // Multiple reads should return identical results
    let deltas: Vec<_> = (0..10).map(|_| armin.delta(&session_id)).collect();

    let first_ids: Vec<_> = deltas[0].iter().map(|m| m.id.clone()).collect();
    for (i, delta) in deltas.iter().enumerate() {
        let ids: Vec<_> = delta.iter().map(|m| m.id.clone()).collect();
        assert_eq!(ids, first_ids, "Read {} differs from first", i);
    }
}

/// Rule 56: Read operations are repeatable
#[test]
fn rule_56_reads_are_repeatable() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Test".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    // Repeat same read many times
    for _ in 0..1000 {
        let snapshot = armin.snapshot();
        let session = snapshot.session(&session_id).unwrap();
        assert_eq!(session.message_count(), 1);
        assert_eq!(session.messages()[0].content, "Test");
    }
}

/// Rule 57: Concurrent reads are safe
#[test]
fn rule_57_concurrent_reads_safe() {
    use std::sync::Arc;

    let sink = RecordingSink::new();
    let armin = Arc::new(Armin::in_memory(sink).unwrap());
    let session_id = armin.create_session().unwrap();

    for i in 0..10 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    // Note: Armin is not Sync due to rusqlite::Connection
    // This test verifies that SnapshotView (which uses Arc) is thread-safe

    armin.refresh_snapshot().unwrap();
    let snapshot = armin.snapshot();

    let handles: Vec<_> = (0..10)
        .map(|_| {
            let snap = snapshot.clone();
            let sid = session_id.clone();
            thread::spawn(move || {
                for _ in 0..100 {
                    let session = snap.session(&sid).unwrap();
                    assert_eq!(session.message_count(), 10);
                }
            })
        })
        .collect();

    for handle in handles {
        handle.join().unwrap();
    }
}

/// Rule 58: Reads tolerate snapshot replacement
#[test]
fn rule_58_reads_tolerate_snapshot_replacement() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "V1".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    // Take snapshot
    let old_snapshot = armin.snapshot();

    // Modify and refresh
    armin
        .append(
            &session_id,
            NewMessage {
                content: "V2".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    // Old snapshot still works
    let session = old_snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "V1");

    // New snapshot has both
    let new_snapshot = armin.snapshot();
    let session = new_snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 2);
}

/// Rule 59: Reads tolerate delta growth
#[test]
fn rule_59_reads_tolerate_delta_growth() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Take initial delta
    let delta_before = armin.delta(&session_id);
    assert!(delta_before.is_empty());

    // Grow delta
    for i in 0..100 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    // Old delta reference is still valid (it's a clone)
    assert!(delta_before.is_empty());

    // New delta has all messages
    let delta_after = armin.delta(&session_id);
    assert_eq!(delta_after.len(), 100);
}

/// Rule 60: Reads do not block writes
#[test]
fn rule_60_reads_do_not_block_writes() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Hold onto read references
    let _snapshot = armin.snapshot();
    let _delta = armin.delta(&session_id);
    let _sub = armin.subscribe(&session_id);

    // Writes should still work
    for i in 0..100 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    // Verify writes succeeded
    assert_eq!(armin.delta(&session_id).len(), 100);
}

// =============================================================================
// Additional read tests
// =============================================================================

#[test]
fn reading_empty_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 0);
    assert!(session.messages().is_empty());
}

#[test]
fn reading_nonexistent_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    assert!(snapshot
        .session(&crate::types::SessionId::from_string(
            "nonexistent-session-9999"
        ))
        .is_none());

    let delta = armin.delta(&crate::types::SessionId::from_string(
        "nonexistent-session-9999",
    ));
    assert!(delta.is_empty());
}

#[test]
fn reading_closed_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Before close".to_string(),
            },
        )
        .unwrap();
    armin.close(&session_id).unwrap();
    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert!(session.is_closed());
    assert_eq!(session.message_count(), 1);
}

#[test]
fn reading_message_ids() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let msg1 = armin
        .append(
            &session_id,
            NewMessage {
                content: "One".to_string(),
            },
        )
        .unwrap();
    let msg2 = armin
        .append(
            &session_id,
            NewMessage {
                content: "Two".to_string(),
            },
        )
        .unwrap();

    let delta = armin.delta(&session_id);
    assert_eq!(delta.messages()[0].id, msg1.id);
    assert_eq!(delta.messages()[1].id, msg2.id);
}
