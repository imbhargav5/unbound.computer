//! Side-effect emission tests for the Armin session engine.
//!
//! Rules covered:
//! - 11. A side-effect is emitted for every successful append
//! - 12. Exactly one side-effect per successful append
//! - 13. Side-effects are emitted after SQLite commit
//! - 14. Side-effects contain correct session_id
//! - 15. Side-effects contain correct message_id
//! - 16. Side-effects preserve append order
//! - 17. Side-effects are not emitted on failed writes
//! - 18. Side-effects are not emitted during recovery
//! - 19. Side-effects are not emitted during snapshot rebuild
//! - 20. Side-effects are never emitted by reads

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::{NewMessage, SessionId};
use crate::writer::SessionWriter;
use crate::{Armin, SideEffect};
use tempfile::NamedTempFile;

/// Rule 11: A side-effect is emitted for every successful append
#[test]
fn rule_11_side_effect_for_every_append() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.sink().clear();

    let append_count = 10;
    for i in 0..append_count {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    let effects = armin.sink().effects();
    let append_effects: Vec<_> = effects
        .iter()
        .filter(|e| matches!(e, SideEffect::MessageAppended { .. }))
        .collect();

    assert_eq!(
        append_effects.len(),
        append_count,
        "Should have exactly {} MessageAppended side-effects",
        append_count
    );
}

/// Rule 12: Exactly one side-effect per successful append
#[test]
fn rule_12_exactly_one_side_effect_per_append() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.sink().clear();

    let message = armin.append(
        &session_id,
        NewMessage {
            content: "Single message".to_string(),
        },
    );

    let effects = armin.sink().effects();
    let matching: Vec<_> = effects
        .iter()
        .filter(|e| {
            matches!(
                e,
                SideEffect::MessageAppended { session_id: s, message_id: m, .. }
                if *s == session_id && *m == message.id
            )
        })
        .collect();

    assert_eq!(
        matching.len(),
        1,
        "Should have exactly one side-effect for the message"
    );
}

/// Rule 13: Side-effects are emitted after SQLite commit
#[test]
fn rule_13_side_effects_after_sqlite_commit() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, message) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        let message = armin.append(
            &session_id,
            NewMessage {
                content: "Test".to_string(),
            },
        );

        // Verify side-effect was emitted
        assert!(armin.sink().effects().iter().any(|e| matches!(
            e,
            SideEffect::MessageAppended { session_id: s, message_id: m, .. }
            if *s == session_id && *m == message.id
        )));

        (session_id, message)
    };

    // Reopen - message should be there (proving SQLite commit happened before side-effect)
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.messages()[0].id, message.id);
}

/// Rule 14: Side-effects contain correct session_id
#[test]
fn rule_14_side_effects_contain_correct_session_id() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session();
    let session2 = armin.create_session();
    armin.sink().clear();

    armin.append(
        &session1,
        NewMessage {
            content: "S1".to_string(),
        },
    );
    armin.append(
        &session2,
        NewMessage {
            content: "S2".to_string(),
        },
    );

    let effects = armin.sink().effects();

    // First effect should reference session1
    match &effects[0] {
        SideEffect::MessageAppended { session_id, .. } => {
            assert_eq!(*session_id, session1);
        }
        _ => panic!("Expected MessageAppended"),
    }

    // Second effect should reference session2
    match &effects[1] {
        SideEffect::MessageAppended { session_id, .. } => {
            assert_eq!(*session_id, session2);
        }
        _ => panic!("Expected MessageAppended"),
    }
}

/// Rule 15: Side-effects contain correct message_id
#[test]
fn rule_15_side_effects_contain_correct_message_id() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.sink().clear();

    let msg1 = armin.append(
        &session_id,
        NewMessage {
            content: "M1".to_string(),
        },
    );
    let msg2 = armin.append(
        &session_id,
        NewMessage {
            content: "M2".to_string(),
        },
    );

    let effects = armin.sink().effects();

    match &effects[0] {
        SideEffect::MessageAppended { message_id, .. } => {
            assert_eq!(*message_id, msg1.id);
        }
        _ => panic!("Expected MessageAppended"),
    }

    match &effects[1] {
        SideEffect::MessageAppended { message_id, .. } => {
            assert_eq!(*message_id, msg2.id);
        }
        _ => panic!("Expected MessageAppended"),
    }
}

/// Rule 16: Side-effects preserve append order
#[test]
fn rule_16_side_effects_preserve_append_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.sink().clear();

    let mut messages = Vec::new();
    for i in 0..20 {
        messages.push(armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        ));
    }

    let effects = armin.sink().effects();

    for (i, effect) in effects.iter().enumerate() {
        match effect {
            SideEffect::MessageAppended { message_id, .. } => {
                assert_eq!(
                    *message_id, messages[i].id,
                    "Side-effect {} has wrong message_id",
                    i
                );
            }
            _ => panic!("Expected MessageAppended at position {}", i),
        }
    }
}

/// Rule 17: Side-effects are not emitted on failed writes
/// (Tested implicitly - append to closed session panics before side-effect)
#[test]
fn rule_17_no_side_effect_on_failed_write() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();
    armin.close(&session_id);
    armin.sink().clear();

    // Attempt to append to closed session (will panic)
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        armin.append(
            &session_id,
            NewMessage {
                content: "Should fail".to_string(),
            },
        );
    }));

    assert!(result.is_err(), "Should panic on closed session");
    assert!(
        armin.sink().is_empty(),
        "No side-effect should be emitted for failed write"
    );
}

/// Rule 18: Side-effects are not emitted during recovery
#[test]
fn rule_18_no_side_effects_during_recovery() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    // Create state
    {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session();
        for i in 0..50 {
            armin.append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            );
        }
    }

    // Recover with fresh sink
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    assert!(
        armin.sink().is_empty(),
        "No side-effects during recovery, got: {:?}",
        armin.sink().effects()
    );
}

/// Rule 19: Side-effects are not emitted during snapshot rebuild
#[test]
fn rule_19_no_side_effects_during_snapshot_rebuild() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    for i in 0..10 {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        );
    }

    armin.sink().clear();

    // Rebuild snapshot
    armin.refresh_snapshot().unwrap();

    assert!(
        armin.sink().is_empty(),
        "No side-effects during snapshot rebuild"
    );
}

/// Rule 20: Side-effects are never emitted by reads
#[test]
fn rule_20_reads_never_emit_side_effects() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session();

    armin.append(
        &session_id,
        NewMessage {
            content: "Test".to_string(),
        },
    );

    armin.sink().clear();

    // Perform various read operations
    let _snapshot = armin.snapshot();
    let _delta = armin.delta(&session_id);
    let _sub = armin.subscribe(&session_id);

    // Access snapshot data
    let snapshot = armin.snapshot();
    if let Some(session) = snapshot.session(&session_id) {
        let _ = session.messages();
        let _ = session.message_count();
        let _ = session.is_closed();
    }

    // Access delta data
    let delta = armin.delta(&session_id);
    let _ = delta.len();
    let _ = delta.is_empty();
    for _ in delta.iter() {}

    assert!(
        armin.sink().is_empty(),
        "Reads should never emit side-effects"
    );
}

// =============================================================================
// Additional side-effect tests
// =============================================================================

#[test]
fn session_created_emits_side_effect() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session_id = armin.create_session();

    let effects = armin.sink().effects();
    assert_eq!(effects.len(), 1);
    assert_eq!(effects[0], SideEffect::SessionCreated { session_id });
}

#[test]
fn session_closed_emits_side_effect() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session_id = armin.create_session();
    armin.sink().clear();

    armin.close(&session_id);

    let effects = armin.sink().effects();
    assert_eq!(effects.len(), 1);
    assert_eq!(effects[0], SideEffect::SessionClosed { session_id: session_id.clone() });
}

#[test]
fn closing_nonexistent_session_emits_nothing() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    armin.close(&SessionId::from_string("nonexistent-session-9999"));

    assert!(armin.sink().is_empty());
}

#[test]
fn closing_already_closed_session_emits_nothing() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session_id = armin.create_session();
    armin.close(&session_id);
    armin.sink().clear();

    armin.close(&session_id);

    assert!(armin.sink().is_empty());
}

#[test]
fn multiple_sessions_emit_independent_side_effects() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session();
    let session2 = armin.create_session();

    armin.append(
        &session1,
        NewMessage {
            content: "Session 1".to_string(),
        },
    );
    armin.append(
        &session2,
        NewMessage {
            content: "Session 2".to_string(),
        },
    );

    let effects = armin.sink().effects();
    assert_eq!(effects.len(), 4); // 2 SessionCreated + 2 MessageAppended

    assert!(effects
        .iter()
        .any(|e| *e == SideEffect::SessionCreated { session_id: session1.clone() }));
    assert!(effects
        .iter()
        .any(|e| *e == SideEffect::SessionCreated { session_id: session2.clone() }));
}
