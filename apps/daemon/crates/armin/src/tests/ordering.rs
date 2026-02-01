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
use crate::types::{MessageId, NewMessage, Role};
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
    let sub = armin.subscribe(session_id);

    // Add messages
    let mut expected_order = Vec::new();
    for i in 0..5 {
        let id = armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
        expected_order.push(id);
    }

    // Take snapshot
    armin.refresh_snapshot().unwrap();

    // Add more messages
    for i in 5..10 {
        let id = armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
        expected_order.push(id);
    }

    // Verify snapshot order (first 5)
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    let snapshot_ids: Vec<_> = session.messages().iter().map(|m| m.id).collect();
    assert_eq!(snapshot_ids, expected_order[..5]);

    // Verify delta order (last 5)
    let delta = armin.delta(session_id);
    let delta_ids: Vec<_> = delta.iter().map(|m| m.id).collect();
    assert_eq!(delta_ids, expected_order[5..]);

    // Verify live order (all 10)
    let mut live_ids = Vec::new();
    while let Some(msg) = sub.try_recv() {
        live_ids.push(msg.id);
    }
    assert_eq!(live_ids, expected_order);
}

/// Rule 62: Message IDs increase with append order
#[test]
fn rule_62_message_ids_increase_with_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let mut prev_id = MessageId(0);
    for i in 0..100 {
        let id = armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
        assert!(
            id.0 > prev_id.0,
            "ID {} should be greater than previous {}",
            id.0,
            prev_id.0
        );
        prev_id = id;
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
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
    }

    armin.refresh_snapshot().unwrap();

    for i in 50..100 {
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
    }

    // Check snapshot for duplicates
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    let snapshot_ids: HashSet<_> = session.messages().iter().map(|m| m.id).collect();
    assert_eq!(snapshot_ids.len(), session.message_count());

    // Check delta for duplicates
    let delta = armin.delta(session_id);
    let delta_ids: HashSet<_> = delta.iter().map(|m| m.id).collect();
    assert_eq!(delta_ids.len(), delta.len());

    // Check no overlap between snapshot and delta
    for id in &delta_ids {
        assert!(!snapshot_ids.contains(id), "ID {} in both snapshot and delta", id.0);
    }
}

/// Rule 64: No message disappears after commit
#[test]
fn rule_64_no_message_disappears() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, message_ids) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        let mut ids = Vec::new();
        for i in 0..100 {
            ids.push(armin.append(
                session_id,
                NewMessage {
                    role: Role::User,
                    content: format!("Message {}", i),
                },
            ));
        }
        (session_id, ids)
    };

    // Reopen and verify all messages present
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();

    assert_eq!(session.message_count(), 100);
    let recovered_ids: Vec<_> = session.messages().iter().map(|m| m.id).collect();
    assert_eq!(recovered_ids, message_ids);
}

/// Rule 65: Clients may observe stale snapshots (by design)
#[test]
fn rule_65_stale_snapshots_allowed() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "V1".to_string(),
        },
    );
    armin.refresh_snapshot().unwrap();

    // Take snapshot (V1)
    let stale_snapshot = armin.snapshot();

    // Add more
    armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "V2".to_string(),
        },
    );
    armin.refresh_snapshot().unwrap();

    // Stale snapshot still shows V1 only
    let session = stale_snapshot.session(session_id).unwrap();
    assert_eq!(session.message_count(), 1);

    // Fresh snapshot shows V1 and V2
    let fresh_snapshot = armin.snapshot();
    let session = fresh_snapshot.session(session_id).unwrap();
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
        session_id,
        NewMessage {
            role: Role::User,
            content: long_content.clone(),
        },
    );

    let delta = armin.delta(session_id);
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
                session_id,
                NewMessage {
                    role: Role::User,
                    content: format!("Message {}", i),
                },
            );
        }

        let ids: Vec<_> = armin
            .sink()
            .effects()
            .iter()
            .filter_map(|e| match e {
                SideEffect::MessageAppended { message_id, .. } => Some(*message_id),
                _ => None,
            })
            .collect();

        (session_id, ids)
    };

    // Verify SQLite order matches
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    let sqlite_ids: Vec<_> = session.messages().iter().map(|m| m.id).collect();

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

        let sub = armin.subscribe(session_id);

        for i in 0..10 {
            armin.append(
                session_id,
                NewMessage {
                    role: Role::User,
                    content: format!("Message {}", i),
                },
            );
        }

        let mut ids = Vec::new();
        while let Some(msg) = sub.try_recv() {
            ids.push(msg.id);
        }

        (session_id, ids)
    };

    // Verify SQLite order matches
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    let sqlite_ids: Vec<_> = session.messages().iter().map(|m| m.id).collect();

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
                session_id,
                NewMessage {
                    role: Role::User,
                    content: format!("Message {}", i),
                },
            );
        }

        session_id
    };

    // Reopen and add more to delta
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    let delta_start = armin.delta(session_id).len(); // Should be 0 after recovery
    assert_eq!(delta_start, 0);

    for i in 10..20 {
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        );
    }

    let delta = armin.delta(session_id);
    let delta_ids: Vec<_> = delta.iter().map(|m| m.id).collect();

    // Verify order is monotonic
    for i in 1..delta_ids.len() {
        assert!(delta_ids[i].0 > delta_ids[i - 1].0);
    }
}

/// Rule 70: Snapshot order matches SQLite order
#[test]
fn rule_70_snapshot_matches_sqlite_order() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, original_ids) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        let mut ids = Vec::new();
        for i in 0..20 {
            ids.push(armin.append(
                session_id,
                NewMessage {
                    role: Role::User,
                    content: format!("Message {}", i),
                },
            ));
        }

        (session_id, ids)
    };

    // Reopen - snapshot from SQLite
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    let snapshot_ids: Vec<_> = session.messages().iter().map(|m| m.id).collect();

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

    let mut all_ids = Vec::new();

    // Interleave
    for i in 0..10 {
        all_ids.push(armin.append(
            if i % 2 == 0 { session1 } else { session2 },
            NewMessage {
                role: Role::User,
                content: format!("Message {}", i),
            },
        ));
    }

    // Global IDs should be monotonic
    for i in 1..all_ids.len() {
        assert!(all_ids[i].0 > all_ids[i - 1].0);
    }
}

#[test]
fn message_content_preserved_in_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let contents: Vec<_> = (0..20).map(|i| format!("Content-{}", i)).collect();
    for content in &contents {
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: content.clone(),
            },
        );
    }

    let delta = armin.delta(session_id);
    for (i, msg) in delta.iter().enumerate() {
        assert_eq!(msg.content, contents[i]);
    }
}
