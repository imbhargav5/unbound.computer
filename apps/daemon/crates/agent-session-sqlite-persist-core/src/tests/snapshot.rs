//! Snapshot tests for the Armin session engine.
//!
//! Rules covered:
//! - 41. Snapshots contain only committed messages
//! - 42. Snapshots never include in-flight messages (N/A - sync API)
//! - 43. Snapshots are immutable once built
//! - 44. Snapshots do not change without rebuild
//! - 45. Snapshot rebuild emits no side-effects
//! - 46. Snapshot rebuild preserves message order
//! - 47. Snapshot rebuild includes all historical messages
//! - 48. Snapshots exclude delta messages (before refresh)
//! - 49. Snapshot + delta equals full session
//! - 50. Snapshot reads require no SQLite access (by design)

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::Armin;
use tempfile::NamedTempFile;

/// Rule 41: Snapshots contain only committed messages
#[test]
fn rule_41_snapshots_contain_committed_messages() {
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
                    content: "Committed message".to_string(),
                },
            )
            .unwrap();

        session_id
    };

    // Reopen - snapshot rebuilt from SQLite (committed messages only)
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "Committed message");
}

/// Rule 43: Snapshots are immutable once built
#[test]
fn rule_43_snapshots_immutable() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Message 1".to_string(),
            },
        )
        .unwrap();

    armin.refresh_snapshot().unwrap();

    // Take snapshot
    let snapshot1 = armin.snapshot();

    // Add more messages
    armin
        .append(
            &session_id,
            NewMessage {
                content: "Message 2".to_string(),
            },
        )
        .unwrap();

    // Original snapshot should still have only 1 message
    let session = snapshot1.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "Message 1");
}

/// Rule 44: Snapshots do not change without rebuild
#[test]
fn rule_44_snapshots_unchanged_without_rebuild() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Before".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    let snapshot_before = armin.snapshot();

    // Add more messages
    for i in 0..10 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("After {}", i),
                },
            )
            .unwrap();
    }

    // Snapshot should be unchanged
    let snapshot_after = armin.snapshot();
    let session_before = snapshot_before.session(&session_id).unwrap();
    let session_after = snapshot_after.session(&session_id).unwrap();

    assert_eq!(
        session_before.message_count(),
        session_after.message_count()
    );
    assert_eq!(session_before.message_count(), 1);
}

/// Rule 45: Snapshot rebuild emits no side-effects
#[test]
fn rule_45_snapshot_rebuild_no_side_effects() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    for i in 0..20 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    armin.sink().clear();

    // Rebuild snapshot
    armin.refresh_snapshot().unwrap();

    assert!(
        armin.sink().is_empty(),
        "Snapshot rebuild should not emit side-effects"
    );
}

/// Rule 46: Snapshot rebuild preserves message order
#[test]
fn rule_46_snapshot_rebuild_preserves_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let contents: Vec<_> = (0..20).map(|i| format!("Message {}", i)).collect();
    for (i, content) in contents.iter().enumerate() {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: content.clone(),
                },
            )
            .unwrap();
    }

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    for (i, msg) in session.messages().iter().enumerate() {
        assert_eq!(msg.content, contents[i], "Message {} out of order", i);
    }
}

/// Rule 47: Snapshot rebuild includes all historical messages
#[test]
fn rule_47_snapshot_includes_all_history() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add in batches with refreshes
    for batch in 0..5 {
        for i in 0..10 {
            armin
                .append(
                    &session_id,
                    NewMessage {
                        content: format!("Batch {} Message {}", batch, i),
                    },
                )
                .unwrap();
        }
        armin.refresh_snapshot().unwrap();
    }

    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    // Should have all 50 messages
    assert_eq!(session.message_count(), 50);
}

/// Rule 48: Snapshots exclude delta messages (before refresh)
#[test]
fn rule_48_snapshots_exclude_delta_before_refresh() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "In snapshot".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "In delta".to_string(),
            },
        )
        .unwrap();

    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    // Snapshot should only have "In snapshot"
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "In snapshot");

    // Delta should have "In delta"
    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].content, "In delta");
}

/// Rule 49: Snapshot + delta equals full session
#[test]
fn rule_49_snapshot_plus_delta_equals_full() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add messages to snapshot
    for i in 0..5 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Snapshot {}", i),
                },
            )
            .unwrap();
    }
    armin.refresh_snapshot().unwrap();

    // Add messages to delta
    for i in 0..5 {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Delta {}", i),
                },
            )
            .unwrap();
    }

    // Combine snapshot and delta
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let delta = armin.delta(&session_id);

    let mut all_messages: Vec<_> = session.messages().iter().map(|m| &m.content).collect();
    all_messages.extend(delta.iter().map(|m| &m.content));

    // Should have all 10 messages
    assert_eq!(all_messages.len(), 10);

    // Check order
    for i in 0..5 {
        assert_eq!(*all_messages[i], format!("Snapshot {}", i));
        assert_eq!(*all_messages[i + 5], format!("Delta {}", i));
    }
}

/// Rule 50: Snapshot reads require no SQLite access (by design)
/// (This is architectural - we verify snapshot works in-memory)
#[test]
fn rule_50_snapshot_reads_in_memory() {
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

    // Multiple snapshot reads should work without issues
    for _ in 0..100 {
        let snapshot = armin.snapshot();
        let session = snapshot.session(&session_id).unwrap();
        assert_eq!(session.message_count(), 1);
        let _ = session.messages();
        let _ = session.is_closed();
    }
}

// =============================================================================
// Additional snapshot tests
// =============================================================================

#[test]
fn empty_snapshot() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let snapshot = armin.snapshot();
    assert!(snapshot.is_empty());
    assert_eq!(snapshot.len(), 0);
}

#[test]
fn snapshot_with_multiple_sessions() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session().unwrap();
    let session2 = armin.create_session().unwrap();

    armin
        .append(
            &session1,
            NewMessage {
                content: "S1".to_string(),
            },
        )
        .unwrap();
    armin
        .append(
            &session2,
            NewMessage {
                content: "S2".to_string(),
            },
        )
        .unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    assert_eq!(snapshot.len(), 2);

    let s1 = snapshot.session(&session1).unwrap();
    assert_eq!(s1.messages()[0].content, "S1");

    let s2 = snapshot.session(&session2).unwrap();
    assert_eq!(s2.messages()[0].content, "S2");
}

#[test]
fn snapshot_preserves_closed_status() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let open_session = armin.create_session().unwrap();
    let closed_session = armin.create_session().unwrap();
    armin.close(&closed_session).unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    assert!(!snapshot.session(&open_session).unwrap().is_closed());
    assert!(snapshot.session(&closed_session).unwrap().is_closed());
}

#[test]
fn snapshot_session_ids_iterator() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let s1 = armin.create_session().unwrap();
    let s2 = armin.create_session().unwrap();
    let s3 = armin.create_session().unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    let ids: std::collections::HashSet<_> = snapshot.session_ids().collect();

    assert!(ids.contains(&s1));
    assert!(ids.contains(&s2));
    assert!(ids.contains(&s3));
}

#[test]
fn snapshot_nonexistent_session_returns_none() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    armin.refresh_snapshot().unwrap();

    let snapshot = armin.snapshot();
    assert!(snapshot
        .session(&crate::types::SessionId::from_string(
            "nonexistent-session-9999"
        ))
        .is_none());
}

#[test]
fn snapshot_clone_is_independent() {
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

    let snapshot1 = armin.snapshot();
    let snapshot2 = snapshot1.clone();

    // Add more and refresh
    armin
        .append(
            &session_id,
            NewMessage {
                content: "New".to_string(),
            },
        )
        .unwrap();
    armin.refresh_snapshot().unwrap();

    // Cloned snapshots should be unchanged
    assert_eq!(snapshot1.session(&session_id).unwrap().message_count(), 1);
    assert_eq!(snapshot2.session(&session_id).unwrap().message_count(), 1);

    // Fresh snapshot should have both
    let snapshot3 = armin.snapshot();
    assert_eq!(snapshot3.session(&session_id).unwrap().message_count(), 2);
}
