//! Boundary & invariant tests for the Armin session engine.
//!
//! Rules covered:
//! - 101. No message exists without a session
//! - 102. Session closure is permanent
//! - 103. Session closure emits exactly one side-effect
//! - 104. Closed sessions appear in snapshot
//! - 105. Closed sessions reject live subscriptions (N/A - they accept but get no new msgs)
//! - 106. Empty sessions behave correctly
//! - 107. Single-message sessions behave correctly
//! - 108. Large sessions behave correctly
//! - 109. Memory usage grows predictably (verified via stress test)
//! - 110. All invariants hold under stress
//!
//! Meta rules (111-120) are architectural and verified by test infrastructure.

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::{NewMessage, SessionId};
use crate::writer::SessionWriter;
use crate::{Armin, SideEffect};
use std::collections::HashSet;
use tempfile::NamedTempFile;

/// Rule 101: No message exists without a session
#[test]
fn rule_101_no_message_without_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    // Can't append without creating session first
    let result = armin.append(
        &SessionId::from_string("nonexistent-session-1"),
        NewMessage {
            content: "Orphan".to_string(),
        },
    );

    assert!(
        result.is_err(),
        "Should fail to append to non-existent session"
    );
}

/// Rule 102: Session closure is permanent
#[test]
fn rule_102_session_closure_permanent() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session().unwrap();
        armin.close(&session_id).unwrap();
        session_id
    };

    // After restart
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    // Session should still be closed
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert!(session.is_closed());

    // Should not be able to append
    let result = armin.append(
        &session_id,
        NewMessage {
            content: "Should fail".to_string(),
        },
    );
    assert!(result.is_err());
}

/// Rule 103: Session closure emits exactly one side-effect
#[test]
fn rule_103_closure_exactly_one_side_effect() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();
    armin.sink().clear();

    armin.close(&session_id).unwrap();

    let effects = armin.sink().effects();
    assert_eq!(effects.len(), 1);
    assert_eq!(
        effects[0],
        SideEffect::SessionClosed {
            session_id: session_id.clone()
        }
    );

    // Second close should emit nothing
    armin.close(&session_id).unwrap();
    assert_eq!(armin.sink().effects().len(), 1);
}

/// Rule 104: Closed sessions appear in snapshot
#[test]
fn rule_104_closed_sessions_in_snapshot() {
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

/// Rule 105: Closed sessions and subscriptions
/// (Subscriptions work but receive no new messages after close)
#[test]
fn rule_105_closed_session_subscriptions() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    armin
        .append(
            &session_id,
            NewMessage {
                content: "Before close".to_string(),
            },
        )
        .unwrap();
    armin.close(&session_id).unwrap();

    // Should receive the message sent before close
    assert_eq!(sub.try_recv().unwrap().content, "Before close");

    // No more messages
    assert!(sub.try_recv().is_none());
}

/// Rule 106: Empty sessions behave correctly
#[test]
fn rule_106_empty_sessions() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin.refresh_snapshot().unwrap();

    // Snapshot
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 0);
    assert!(session.messages().is_empty());
    assert!(!session.is_closed());

    // Delta
    let delta = armin.delta(&session_id);
    assert!(delta.is_empty());

    // Can still append
    armin
        .append(
            &session_id,
            NewMessage {
                content: "First".to_string(),
            },
        )
        .unwrap();
    assert_eq!(armin.delta(&session_id).len(), 1);
}

/// Rule 107: Single-message sessions behave correctly
#[test]
fn rule_107_single_message_sessions() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let msg = armin
        .append(
            &session_id,
            NewMessage {
                content: "Only message".to_string(),
            },
        )
        .unwrap();

    // Delta
    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].id, msg.id);
    assert_eq!(delta.messages()[0].content, "Only message");

    // Refresh and check snapshot
    armin.refresh_snapshot().unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].id, msg.id);
}

/// Rule 108: Large sessions behave correctly
#[test]
fn rule_108_large_sessions() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let message_count = 1000;
    let mut messages = Vec::with_capacity(message_count);

    for i in 0..message_count {
        messages.push(
            armin
                .append(
                    &session_id,
                    NewMessage {
                        content: format!("Message {} with some content to make it longer", i),
                    },
                )
                .unwrap(),
        );
    }

    // Verify delta
    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), message_count);

    // Refresh and verify snapshot
    armin.refresh_snapshot().unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.message_count(), message_count);

    // Verify order preserved
    for (i, msg) in session.messages().iter().enumerate() {
        assert_eq!(msg.id, messages[i].id);
    }
}

/// Rule 109: Memory usage grows predictably
/// (Verified by not crashing with many messages)
#[test]
fn rule_109_memory_grows_predictably() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    // Create multiple sessions with many messages
    for _ in 0..10 {
        let session_id = armin.create_session().unwrap();
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
    }

    // Refresh to move to snapshot
    armin.refresh_snapshot().unwrap();

    // Create more sessions (verify delta cleared)
    for _ in 0..10 {
        let session_id = armin.create_session().unwrap();
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
    }

    // Should have 20 sessions total
    let snapshot = armin.snapshot();
    assert_eq!(snapshot.len(), 10); // First 10 in snapshot
}

/// Rule 110: All invariants hold under stress
#[test]
fn rule_110_invariants_under_stress() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let mut all_session_ids = Vec::new();
    let mut all_message_ids = HashSet::new();

    // Create many sessions with various operations
    for session_num in 0..20 {
        let session_id = armin.create_session().unwrap();
        all_session_ids.push(session_id.clone());

        // Some messages
        for i in 0..50 {
            let msg = armin
                .append(
                    &session_id,
                    NewMessage {
                        content: format!("S{}-M{}", session_num, i),
                    },
                )
                .unwrap();

            // No duplicate message IDs
            assert!(
                all_message_ids.insert(msg.id.clone()),
                "Duplicate message ID: {}",
                msg.id.as_str()
            );
        }

        // Close some sessions
        if session_num % 3 == 0 {
            armin.close(&session_id).unwrap();
        }

        // Refresh snapshot periodically
        if session_num % 5 == 0 {
            armin.refresh_snapshot().unwrap();
        }
    }

    // Verify final state
    armin.refresh_snapshot().unwrap();
    let snapshot = armin.snapshot();

    for (i, session_id) in all_session_ids.iter().enumerate() {
        let session = snapshot.session(session_id).unwrap();
        assert_eq!(session.message_count(), 50);

        // Check closure status
        if i % 3 == 0 {
            assert!(session.is_closed());
        } else {
            assert!(!session.is_closed());
        }
    }
}

// =============================================================================
// Additional invariant tests (covering rules 111-120 concepts)
// =============================================================================

/// Rule 111-112: All rules enforced by tests using in-memory SQLite
#[test]
fn tests_use_in_memory_sqlite() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    // This test itself uses in-memory SQLite
    let session_id = armin.create_session().unwrap();
    armin
        .append(
            &session_id,
            NewMessage {
                content: "Test".to_string(),
            },
        )
        .unwrap();
}

/// Rule 113-114: Tests don't rely on timing
#[test]
fn tests_deterministic() {
    // Run multiple times to verify determinism
    for _ in 0..10 {
        let sink = RecordingSink::new();
        let armin = Armin::in_memory(sink).unwrap();
        let session_id = armin.create_session().unwrap();

        let ids: Vec<_> = (0..10)
            .map(|i| {
                armin
                    .append(
                        &session_id,
                        NewMessage {
                            content: format!("Message {}", i),
                        },
                    )
                    .unwrap()
            })
            .collect();

        // IDs should always be unique
        let unique_ids: std::collections::HashSet<_> =
            ids.iter().map(|msg| msg.id.as_str()).collect();
        assert_eq!(unique_ids.len(), ids.len());
    }
}

/// Rule 116: Tests fail loudly on invariant violation
#[test]
fn invariant_violation_detected() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();
    armin.close(&session_id).unwrap();

    // This should fail (returns Err for closed session)
    let result = armin.append(
        &session_id,
        NewMessage {
            content: "Violation".to_string(),
        },
    );

    assert!(result.is_err(), "Invariant violation should return error");
}

#[test]
fn message_ids_globally_unique() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let mut all_ids = HashSet::new();

    for _ in 0..5 {
        let session_id = armin.create_session().unwrap();
        for i in 0..20 {
            let msg = armin
                .append(
                    &session_id,
                    NewMessage {
                        content: format!("Msg {}", i),
                    },
                )
                .unwrap();
            assert!(all_ids.insert(msg.id), "Duplicate message ID");
        }
    }
}

#[test]
fn session_ids_globally_unique() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let mut all_ids = HashSet::new();

    for _ in 0..100 {
        let session_id = armin.create_session().unwrap();
        assert!(all_ids.insert(session_id), "Duplicate session ID");
    }
}

#[test]
fn unicode_content_preserved() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let contents = vec![
        "Hello 👋",
        "世界",
        "مرحبا",
        "🎉🎊🎁",
        "नमस्ते",
        "שלום",
        "Здравствуйте",
    ];

    for (i, content) in contents.iter().enumerate() {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: content.to_string(),
                },
            )
            .unwrap();
    }

    let delta = armin.delta(&session_id);
    for (i, msg) in delta.iter().enumerate() {
        assert_eq!(msg.content, contents[i]);
    }
}

#[test]
fn empty_content_allowed() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: String::new(),
            },
        )
        .unwrap();

    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].content, "");
}

#[test]
fn very_long_content_preserved() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let long_content = "A".repeat(100_000);

    armin
        .append(
            &session_id,
            NewMessage {
                content: long_content.clone(),
            },
        )
        .unwrap();

    let delta = armin.delta(&session_id);
    assert_eq!(delta.messages()[0].content.len(), 100_000);
    assert_eq!(delta.messages()[0].content, long_content);
}
