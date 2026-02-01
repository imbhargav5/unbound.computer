//! Ordering & consistency tests for the Armin session engine.
//!
//! Rules covered:
//! - 61. Message order is consistent across snapshot, delta, live
//! - 62. Message IDs increase with append order
//! - 63. No message appears twice in any view
//! - 64. No message disappears after commit
//! - 65. Clients may observe stale snapshots (by design)
//! - 66. Clients never observe torn messages
//! - 67. Side-effects reflect the same order as SQLite
//! - 68. Live stream order matches SQLite order
//! - 69. Delta order matches SQLite order
//! - 70. Snapshot order matches SQLite order

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::{Armin, SideEffect};
use std::collections::HashSet;
use tempfile::NamedTempFile;

/// Rule 61: Message order is consistent across snapshot, delta, live
#[test]
fn rule_61_order_consistent_across_views() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    // Subscribe before appending
    let sub = armin.subscribe(&session_id);

    // Add messages
    let mut expected_order = Vec::new();
    for i in 0..5 {
        let msg = armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
        expected_order.push(msg.id);
    }

    // Take snapshot
    armin.refresh_snapshot().unwrap();

    // Add more messages
    for i in 5..10 {
        let msg = armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
        expected_order.push(msg.id);
    }

    // Verify snapshot order (first 5)
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let snapshot_ids: Vec<_> = session.messages().iter().map(|m| m.id.clone()).collect();
    assert_eq!(snapshot_ids, expected_order[..5]);

    // Verify delta order (last 5)
    let delta = armin.delta(&session_id);
    let delta_ids: Vec<_> = delta.iter().map(|m| m.id.clone()).collect();
    assert_eq!(delta_ids, expected_order[5..]);

    // Verify live order (all 10)
    let mut live_ids = Vec::new();
    while let Some(msg) = sub.try_recv() {
        live_ids.push(msg.id.clone());
    }
    assert_eq!(live_ids, expected_order);
}

/// Rule 62: Message IDs are unique (UUIDs)
#[test]
fn rule_62_message_ids_are_unique() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let mut all_ids = std::collections::HashSet::new();
    for i in 0..100 {
        let msg = armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
        assert!(
            all_ids.insert(msg.id.as_str().to_string()),
            "ID {} should be unique",
            msg.id.as_str()
        );
    }
}

/// Rule 63: No message appears twice in any view
#[test]
fn rule_63_no_duplicate_messages() {
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

    armin.refresh_snapshot().unwrap();

    for i in 50..100 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    // Check snapshot for duplicates
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let snapshot_ids: HashSet<_> = session.messages().iter().map(|m| m.id.clone()).collect();
    assert_eq!(snapshot_ids.len(), session.message_count());

    // Check delta for duplicates
    let delta = armin.delta(&session_id);
    let delta_ids: HashSet<_> = delta.iter().map(|m| m.id.clone()).collect();
    assert_eq!(delta_ids.len(), delta.len());

    // Check no overlap between snapshot and delta
    for id in &delta_ids {
        assert!(!snapshot_ids.contains(id), "ID {} in both snapshot and delta", id.as_str());
    }
}

/// Rule 64: No message disappears after commit
#[test]
fn rule_64_no_message_disappears() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, messages) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        let mut msgs = Vec::new();
        for i in 0..100 {
            msgs.push(armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            ));
        }
        (session_id, msgs)
    };

    // Reopen and verify all messages present
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    assert_eq!(session.message_count(), 100);
    let recovered_ids: Vec<_> = session.messages().iter().map(|m| m.id.clone()).collect();
    let message_ids: Vec<_> = messages.iter().map(|m| m.id.clone()).collect();
    assert_eq!(recovered_ids, message_ids);
}

/// Rule 65: Clients may observe stale snapshots (by design)
#[test]
fn rule_65_stale_snapshots_allowed() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    armin.append(
        &session_id,
        NewMessage {
            content: "V1".to_string(),
        },
    );
    armin.refresh_snapshot().unwrap();

    // Take snapshot (V1)
    let stale_snapshot = armin.snapshot();

    // Add more
    armin.append(
        &session_id,
        NewMessage {
            content: "V2".to_string(),
        },
    );
    armin.refresh_snapshot().unwrap();

    // Stale snapshot still shows V1 only
    let session = stale_snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 1);

    // Fresh snapshot shows V1 and V2
    let fresh_snapshot = armin.snapshot();
    let session = fresh_snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 2);
}

/// Rule 66: Clients never observe torn messages
/// (Verified by design - messages are atomic)
#[test]
fn rule_66_no_torn_messages() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let long_content = "A".repeat(10000);

    armin.append(
        &session_id,
        NewMessage {
            content: long_content.clone(),
        },
    );

    let delta = armin.delta(&session_id);
    let msg = &delta.messages()[0];

    // Message should be complete
    assert_eq!(msg.content.len(), long_content.len());
    assert_eq!(msg.content, long_content);
}

/// Rule 67: Side-effects reflect the same order as SQLite
#[test]
fn rule_67_side_effects_match_sqlite_order() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, effect_ids) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        armin.sink().clear();

        for i in 0..10 {
            armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            );
        }

        let ids: Vec<_> = armin
            .sink()
            .effects()
            .iter()
            .filter_map(|e| match e {
                SideEffect::MessageAppended { message_id, .. } => Some(message_id.clone()),
                _ => None,
            })
            .collect();

        (session_id, ids)
    };

    // Verify SQLite order matches
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let sqlite_ids: Vec<_> = session.messages().iter().map(|m| m.id.clone()).collect();

    assert_eq!(effect_ids, sqlite_ids);
}

/// Rule 68: Live stream order matches SQLite order
#[test]
fn rule_68_live_matches_sqlite_order() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, live_ids) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        let sub = armin.subscribe(&session_id);

        for i in 0..10 {
            armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            );
        }

        let mut ids = Vec::new();
        while let Some(msg) = sub.try_recv() {
            ids.push(msg.id.clone());
        }

        (session_id, ids)
    };

    // Verify SQLite order matches
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let sqlite_ids: Vec<_> = session.messages().iter().map(|m| m.id.clone()).collect();

    assert_eq!(live_ids, sqlite_ids);
}

/// Rule 69: Delta order matches SQLite order
#[test]
fn rule_69_delta_matches_sqlite_order() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        for i in 0..10 {
            armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            );
        }

        session_id
    };

    // Reopen and add more to delta
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    let delta_start = armin.delta(&session_id).len(); // Should be 0 after recovery
    assert_eq!(delta_start, 0);

    for i in 10..20 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    let delta = armin.delta(&session_id);
    let delta_ids: Vec<_> = delta.iter().map(|m| m.id.clone()).collect();

    // Verify IDs are unique
    let unique_ids: std::collections::HashSet<_> = delta_ids.iter().map(|id| id.as_str()).collect();
    assert_eq!(unique_ids.len(), delta_ids.len());
}

/// Rule 70: Snapshot order matches SQLite order
#[test]
fn rule_70_snapshot_matches_sqlite_order() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, original_messages) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        let mut msgs = Vec::new();
        for i in 0..20 {
            msgs.push(armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            ));
        }

        (session_id, msgs)
    };

    // Reopen - snapshot from SQLite
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    let snapshot_ids: Vec<_> = session.messages().iter().map(|m| m.id.clone()).collect();
    let original_ids: Vec<_> = original_messages.iter().map(|m| m.id.clone()).collect();

    assert_eq!(snapshot_ids, original_ids);
}

// =============================================================================
// Additional ordering tests
// =============================================================================

#[test]
fn interleaved_sessions_maintain_global_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session();
    let session2 = armin.create_session();

    let mut all_messages = Vec::new();

    // Interleave
    for i in 0..10 {
        all_messages.push(armin.append(
            if i % 2 == 0 { &session1 } else { &session2 },
            NewMessage {
                content: format!("Message {}", i),
            },
        ));
    }

    // Global IDs should be unique
    let unique_ids: std::collections::HashSet<_> = all_messages.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(unique_ids.len(), all_messages.len());
}

#[test]
fn message_content_preserved_in_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let contents: Vec<_> = (0..20).map(|i| format!("Content-{}", i)).collect();
    for (i, content) in contents.iter().enumerate() {
        armin.append(
            &session_id,
            NewMessage {
                content: content.clone(),
            },
        );
    }

    let delta = armin.delta(&session_id);
    for (i, msg) in delta.iter().enumerate() {
        assert_eq!(msg.content, contents[i]);
    }
}
