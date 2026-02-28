//! Delta (Live Tail) tests for the Armin session engine.
//!
//! Rules covered:
//! - 21. New messages appear in delta immediately after append
//! - 22. Delta only contains messages after last snapshot
//! - 23. Delta preserves message order
//! - 24. Delta is session-scoped
//! - 25. Delta is cleared after snapshot rebuild
//! - 26. Delta is rebuilt correctly after restart
//! - 27. Delta does not contain duplicate messages
//! - 28. Delta never contains messages not in SQLite
//! - 29. Delta growth does not block writes
//! - 30. Delta iteration is deterministic

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::Armin;
use tempfile::NamedTempFile;

/// Rule 21: New messages appear in delta immediately after append
#[test]
fn rule_21_messages_appear_immediately_in_delta() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Initially empty
    assert!(armin.delta(&session_id).is_empty());

    // After first append
    armin
        .append(
            &session_id,
            NewMessage {
                content: "First".to_string(),
            },
        )
        .unwrap();
    assert_eq!(armin.delta(&session_id).len(), 1);

    // After second append
    armin
        .append(
            &session_id,
            NewMessage {
                content: "Second".to_string(),
            },
        )
        .unwrap();
    assert_eq!(armin.delta(&session_id).len(), 2);
}

/// Rule 22: Delta only contains messages after last snapshot
#[test]
fn rule_22_delta_only_after_snapshot() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add messages before snapshot
    armin
        .append(
            &session_id,
            NewMessage {
                content: "Before snapshot".to_string(),
            },
        )
        .unwrap();

    // Refresh snapshot
    armin.refresh_snapshot().unwrap();

    // Delta should be empty now
    assert!(
        armin.delta(&session_id).is_empty(),
        "Delta should be empty after snapshot"
    );

    // Add message after snapshot
    armin
        .append(
            &session_id,
            NewMessage {
                content: "After snapshot".to_string(),
            },
        )
        .unwrap();

    // Delta should only have the new message
    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].content, "After snapshot");
}

/// Rule 23: Delta preserves message order
#[test]
fn rule_23_delta_preserves_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let contents = vec!["First", "Second", "Third", "Fourth", "Fifth"];
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
        assert_eq!(msg.content, contents[i], "Message {} out of order", i);
    }
}

/// Rule 24: Delta is session-scoped
#[test]
fn rule_24_delta_is_session_scoped() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session().unwrap();
    let session2 = armin.create_session().unwrap();

    armin
        .append(
            &session1,
            NewMessage {
                content: "Session 1 message".to_string(),
            },
        )
        .unwrap();
    armin
        .append(
            &session2,
            NewMessage {
                content: "Session 2 message".to_string(),
            },
        )
        .unwrap();
    armin
        .append(
            &session1,
            NewMessage {
                content: "Session 1 second".to_string(),
            },
        )
        .unwrap();

    // Session 1 delta
    let delta1 = armin.delta(&session1);
    assert_eq!(delta1.len(), 2);
    assert!(delta1
        .messages()
        .iter()
        .all(|m| m.content.starts_with("Session 1")));

    // Session 2 delta
    let delta2 = armin.delta(&session2);
    assert_eq!(delta2.len(), 1);
    assert_eq!(delta2.messages()[0].content, "Session 2 message");
}

/// Rule 25: Delta is cleared after snapshot rebuild
#[test]
fn rule_25_delta_cleared_after_snapshot_rebuild() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add messages
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

    assert_eq!(armin.delta(&session_id).len(), 10);

    // Rebuild snapshot
    armin.refresh_snapshot().unwrap();

    // Delta should be cleared
    assert!(
        armin.delta(&session_id).is_empty(),
        "Delta should be cleared after snapshot rebuild"
    );
}

/// Rule 26: Delta is rebuilt correctly after restart
#[test]
fn rule_26_delta_rebuilt_after_restart() {
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
                    content: "Message".to_string(),
                },
            )
            .unwrap();
        session_id
    };

    // Restart
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();

    // Delta should be empty (messages are in snapshot after recovery)
    let delta = armin.delta(&session_id);
    assert!(
        delta.is_empty(),
        "Delta should be empty after restart (messages in snapshot)"
    );

    // New messages should appear in delta
    armin
        .append(
            &session_id,
            NewMessage {
                content: "New message".to_string(),
            },
        )
        .unwrap();

    let delta = armin.delta(&session_id);
    assert_eq!(delta.len(), 1);
    assert_eq!(delta.messages()[0].content, "New message");
}

/// Rule 27: Delta does not contain duplicate messages
#[test]
fn rule_27_delta_no_duplicates() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add messages
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

    let delta = armin.delta(&session_id);
    let messages = delta.messages();

    // Check no duplicate IDs
    let mut seen_ids = std::collections::HashSet::new();
    for msg in messages {
        assert!(
            seen_ids.insert(msg.id.clone()),
            "Duplicate message ID {} in delta",
            msg.id.as_str()
        );
    }
}

/// Rule 28: Delta never contains messages not in SQLite
/// (By design: delta is updated AFTER SQLite commit)
#[test]
fn rule_28_delta_only_committed_messages() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session().unwrap();

        // Add message - it goes to both SQLite and delta
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "Committed".to_string(),
                },
            )
            .unwrap();

        let delta = armin.delta(&session_id);
        assert_eq!(delta.len(), 1);

        session_id
    };

    // Reopen - verify the message is in SQLite
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();

    // Message should be in snapshot (from SQLite)
    assert_eq!(session.message_count(), 1);
    assert_eq!(session.messages()[0].content, "Committed");
}

/// Rule 29: Delta growth does not block writes
#[test]
fn rule_29_delta_growth_no_blocking() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Write many messages without refreshing snapshot
    let count = 1000;
    for i in 0..count {
        armin
            .append(
                &session_id,
                NewMessage {
                    content: format!("Message {}", i),
                },
            )
            .unwrap();
    }

    // All messages should be in delta
    assert_eq!(armin.delta(&session_id).len(), count);
}

/// Rule 30: Delta iteration is deterministic
#[test]
fn rule_30_delta_iteration_deterministic() {
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

    // Get delta multiple times
    let delta1 = armin.delta(&session_id);
    let delta2 = armin.delta(&session_id);
    let delta3 = armin.delta(&session_id);

    // All should be identical
    let msgs1: Vec<_> = delta1.iter().map(|m| m.id.clone()).collect();
    let msgs2: Vec<_> = delta2.iter().map(|m| m.id.clone()).collect();
    let msgs3: Vec<_> = delta3.iter().map(|m| m.id.clone()).collect();

    assert_eq!(msgs1, msgs2);
    assert_eq!(msgs2, msgs3);
}

// =============================================================================
// Additional delta tests
// =============================================================================

#[test]
fn delta_empty_for_new_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let delta = armin.delta(&session_id);
    assert!(delta.is_empty());
    assert_eq!(delta.len(), 0);
}

#[test]
fn delta_empty_for_nonexistent_session() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let delta = armin.delta(&crate::types::SessionId::from_string(
        "nonexistent-session-9999",
    ));
    assert!(delta.is_empty());
}

#[test]
fn delta_into_iterator() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    armin
        .append(
            &session_id,
            NewMessage {
                content: "One".to_string(),
            },
        )
        .unwrap();
    armin
        .append(
            &session_id,
            NewMessage {
                content: "Two".to_string(),
            },
        )
        .unwrap();

    let delta = armin.delta(&session_id);
    let contents: Vec<_> = delta.into_iter().map(|m| m.content).collect();
    assert_eq!(contents, vec!["One", "Two"]);
}
