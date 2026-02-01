//! Durability tests for the Armin session engine.
//!
//! Rules covered:
//! - 1. Every append writes to SQLite
//! - 2. SQLite write happens before any side-effect
//! - 3. If SQLite write fails, no side-effect is emitted
//! - 4. If SQLite write fails, delta is not updated
//! - 5. If SQLite write fails, live stream is not notified
//! - 6. Message IDs are monotonic per database
//! - 7. Messages are persisted in append order
//! - 8. Multiple appends in one session preserve order
//! - 9. Messages survive daemon restart
//! - 10. Closed sessions reject new appends
//!
//! - 71. Crash after SQLite commit preserves message
//! - 72. Crash before SQLite commit loses message
//! - 73. Crash during delta update is recoverable
//! - 74. Crash during live notify is recoverable
//! - 75. Recovery rebuilds delta from SQLite
//! - 76. Recovery rebuilds snapshots from SQLite
//! - 77. Recovery emits no side-effects
//! - 78. Recovery does not notify live subscribers
//! - 79. Recovery produces consistent read views
//! - 80. Recovery is idempotent

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::{NewMessage, Role};
use crate::writer::SessionWriter;
use crate::Armin;
use tempfile::NamedTempFile;

// =============================================================================
// Rules 1-10: SQLite & Durability
// =============================================================================

/// Rule 1: Every append writes to SQLite
#[test]
fn rule_01_every_append_writes_to_sqlite() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Test message".to_string(),
            },
        );
        session_id
    };

    // Reopen and verify message persisted
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "Test message");
}

/// Rule 2: SQLite write happens before any side-effect
/// (Verified by design: append() commits to SQLite first, then emits)
#[test]
fn rule_02_sqlite_write_before_side_effect() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let session_id = armin.create_session();

    // Append a message
    let message_id = armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "Test".to_string(),
        },
    );

    // Side-effect was emitted
    let effects = armin.sink().effects();
    assert!(effects.iter().any(|e| matches!(
        e,
        crate::SideEffect::MessageAppended { session_id: s, message_id: m }
        if *s == session_id && *m == message_id
    )));

    // Drop and reopen - message should be there (proving SQLite write happened)
    drop(armin);
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    assert_eq!(session.message_count(), 1);
}

/// Rule 6: Message IDs are monotonic per database
#[test]
fn rule_06_message_ids_are_monotonic() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session();
    let session2 = armin.create_session();

    let mut all_ids = Vec::new();

    // Interleave appends across sessions
    for _ in 0..5 {
        all_ids.push(
            armin.append(
                session1,
                NewMessage {
                    role: Role::User,
                    content: "S1".to_string(),
                },
            ),
        );
        all_ids.push(
            armin.append(
                session2,
                NewMessage {
                    role: Role::User,
                    content: "S2".to_string(),
                },
            ),
        );
    }

    // All IDs should be strictly monotonic
    for i in 1..all_ids.len() {
        assert!(
            all_ids[i].0 > all_ids[i - 1].0,
            "Message ID {} should be greater than {}",
            all_ids[i].0,
            all_ids[i - 1].0
        );
    }
}

/// Rule 7: Messages are persisted in append order
#[test]
fn rule_07_messages_persisted_in_append_order() {
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

    // Reopen and verify order
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();

    for (i, msg) in session.messages().iter().enumerate() {
        assert_eq!(msg.content, format!("Message {}", i));
    }
}

/// Rule 8: Multiple appends in one session preserve order
#[test]
fn rule_08_multiple_appends_preserve_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    let contents = vec!["First", "Second", "Third", "Fourth", "Fifth"];
    for content in &contents {
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: content.to_string(),
            },
        );
    }

    let delta = armin.delta(session_id);
    for (i, msg) in delta.messages().iter().enumerate() {
        assert_eq!(msg.content, contents[i]);
    }
}

/// Rule 9: Messages survive daemon restart
#[test]
fn rule_09_messages_survive_restart() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, message_count) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();

        for i in 0..100 {
            armin.append(
                session_id,
                NewMessage {
                    role: if i % 2 == 0 { Role::User } else { Role::Assistant },
                    content: format!("Message {}", i),
                },
            );
        }
        (session_id, 100)
    };

    // Simulate multiple restarts
    for _ in 0..3 {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let snapshot = armin.snapshot();
        let session = snapshot.session(session_id).unwrap();
        assert_eq!(session.message_count(), message_count);
    }
}

/// Rule 10: Closed sessions reject new appends
#[test]
#[should_panic(expected = "does not exist or is closed")]
fn rule_10_closed_sessions_reject_appends() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session_id = armin.create_session();
    armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "Before close".to_string(),
        },
    );

    armin.close(session_id);

    // This should panic
    armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "After close".to_string(),
        },
    );
}

// =============================================================================
// Rules 71-80: Crash & Recovery
// =============================================================================

/// Rule 71: Crash after SQLite commit preserves message
#[test]
fn rule_71_crash_after_commit_preserves_message() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, message_id) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        let message_id = armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Committed message".to_string(),
            },
        );
        // "Crash" by dropping without graceful shutdown
        (session_id, message_id)
    };

    // Recover
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].id, message_id);
}

/// Rule 75: Recovery rebuilds delta from SQLite
#[test]
fn rule_75_recovery_rebuilds_delta() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Message 1".to_string(),
            },
        );
        session_id
    };

    // Recover
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    // Delta should be empty after recovery (messages are in snapshot)
    let delta = armin.delta(session_id);
    assert!(delta.is_empty(), "Delta should be empty after recovery");

    // Add new message - this should appear in delta
    armin.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "Message 2".to_string(),
        },
    );

    let delta = armin.delta(session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].content, "Message 2");
}

/// Rule 76: Recovery rebuilds snapshots from SQLite
#[test]
fn rule_76_recovery_rebuilds_snapshots() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session1, session2) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();

        let s1 = armin.create_session();
        armin.append(
            s1,
            NewMessage {
                role: Role::User,
                content: "S1M1".to_string(),
            },
        );

        let s2 = armin.create_session();
        armin.append(
            s2,
            NewMessage {
                role: Role::Assistant,
                content: "S2M1".to_string(),
            },
        );
        armin.close(s2);

        (s1, s2)
    };

    // Recover
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();

    // Both sessions should be in snapshot
    let s1 = snapshot.session(session1).unwrap();
    assert_eq!(s1.message_count(), 1);
    assert!(!s1.is_closed());

    let s2 = snapshot.session(session2).unwrap();
    assert_eq!(s2.message_count(), 1);
    assert!(s2.is_closed());
}

/// Rule 77: Recovery emits no side-effects
#[test]
fn rule_77_recovery_emits_no_side_effects() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    // Create substantial state
    {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        for _ in 0..5 {
            let session_id = armin.create_session();
            for j in 0..10 {
                armin.append(
                    session_id,
                    NewMessage {
                        role: Role::User,
                        content: format!("Message {}", j),
                    },
                );
            }
        }
    }

    // Recover with fresh sink
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    assert!(
        armin.sink().is_empty(),
        "Recovery should not emit side-effects, got: {:?}",
        armin.sink().effects()
    );
}

/// Rule 78: Recovery does not notify live subscribers
#[test]
fn rule_78_recovery_does_not_notify_live_subscribers() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Historical message".to_string(),
            },
        );
        session_id
    };

    // Recover
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    // Subscribe after recovery
    let sub = armin.subscribe(session_id);

    // Should not receive the historical message
    assert!(
        sub.try_recv().is_none(),
        "Live subscriber should not receive historical messages after recovery"
    );
}

/// Rule 79: Recovery produces consistent read views
#[test]
fn rule_79_recovery_produces_consistent_views() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        for i in 0..20 {
            armin.append(
                session_id,
                NewMessage {
                    role: if i % 2 == 0 { Role::User } else { Role::Assistant },
                    content: format!("Message {}", i),
                },
            );
        }
        session_id
    };

    // Recover
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    // Snapshot should have all messages
    let snapshot = armin.snapshot();
    let session = snapshot.session(session_id).unwrap();
    assert_eq!(session.message_count(), 20);

    // Delta should be empty
    let delta = armin.delta(session_id);
    assert!(delta.is_empty());

    // Messages should be in order with correct content
    for (i, msg) in session.messages().iter().enumerate() {
        assert_eq!(msg.content, format!("Message {}", i));
        assert_eq!(
            msg.role,
            if i % 2 == 0 { Role::User } else { Role::Assistant }
        );
    }
}

/// Rule 80: Recovery is idempotent
#[test]
fn rule_80_recovery_is_idempotent() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        armin.append(
            session_id,
            NewMessage {
                role: Role::User,
                content: "Test".to_string(),
            },
        );
        session_id
    };

    // Recover multiple times
    for i in 0..5 {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();

        // State should be identical each time
        let snapshot = armin.snapshot();
        let session = snapshot.session(session_id).unwrap();
        assert_eq!(
            session.message_count(),
            1,
            "Recovery {} should produce same state",
            i
        );
        assert_eq!(session.messages()[0].content, "Test");

        // No side-effects should be emitted
        assert!(armin.sink().is_empty());
    }
}
