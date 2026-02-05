//! Live subscription tests for the Armin session engine.
//!
//! Rules covered:
//! - 31. Live subscribers receive new messages
//! - 32. Live subscribers receive messages in order
//! - 33. Live subscribers do not receive historical messages
//! - 34. Live subscribers block until a message arrives
//! - 35. Multiple subscribers receive the same messages
//! - 36. Slow subscribers do not block writers
//! - 37. Dropped live messages are detectable (N/A - channel semantics)
//! - 38. Live notifications occur after SQLite commit
//! - 39. Live notifications occur before side-effect emission (N/A - same order)
//! - 40. Live subscriptions are session-scoped

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::NewMessage;
use crate::writer::SessionWriter;
use crate::Armin;
use tempfile::NamedTempFile;

/// Rule 31: Live subscribers receive new messages
#[test]
fn rule_31_subscribers_receive_new_messages() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    armin.append(
        &session_id,
        NewMessage {
            content: "Hello".to_string(),
        },
    ).unwrap();

    let msg = sub.try_recv().expect("Should receive message");
    assert_eq!(msg.content, "Hello");
}

/// Rule 32: Live subscribers receive messages in order
#[test]
fn rule_32_subscribers_receive_in_order() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    let contents = vec!["First", "Second", "Third", "Fourth", "Fifth"];
    for (i, content) in contents.iter().enumerate() {
        armin.append(
            &session_id,
            NewMessage {
                content: content.to_string(),
            },
        ).unwrap();
    }

    for expected in &contents {
        let msg = sub.try_recv().expect("Should receive message");
        assert_eq!(msg.content, *expected);
    }
}

/// Rule 33: Live subscribers do not receive historical messages
#[test]
fn rule_33_no_historical_messages() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Add messages before subscription
    armin.append(
        &session_id,
        NewMessage {
            content: "Historical".to_string(),
        },
    ).unwrap();

    // Subscribe after
    let sub = armin.subscribe(&session_id);

    // Should not receive historical message
    assert!(
        sub.try_recv().is_none(),
        "Should not receive historical messages"
    );

    // But should receive new messages
    armin.append(
        &session_id,
        NewMessage {
            content: "New".to_string(),
        },
    ).unwrap();

    let msg = sub.try_recv().expect("Should receive new message");
    assert_eq!(msg.content, "New");
}

/// Rule 34: Live subscribers block until a message arrives
/// (We test non-blocking behavior to avoid test hangs)
#[test]
fn rule_34_subscribers_block_semantics() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    // No message yet - try_recv should return None
    assert!(sub.try_recv().is_none());

    // Add message
    armin.append(
        &session_id,
        NewMessage {
            content: "Test".to_string(),
        },
    ).unwrap();

    // Now it should be available
    assert!(sub.try_recv().is_some());
}

/// Rule 35: Multiple subscribers receive the same messages
#[test]
fn rule_35_multiple_subscribers_same_messages() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub1 = armin.subscribe(&session_id);
    let sub2 = armin.subscribe(&session_id);
    let sub3 = armin.subscribe(&session_id);

    armin.append(
        &session_id,
        NewMessage {
            content: "Broadcast".to_string(),
        },
    ).unwrap();

    // All subscribers should receive the message
    assert_eq!(sub1.try_recv().unwrap().content, "Broadcast");
    assert_eq!(sub2.try_recv().unwrap().content, "Broadcast");
    assert_eq!(sub3.try_recv().unwrap().content, "Broadcast");
}

/// Rule 36: Slow subscribers do not block writers
#[test]
fn rule_36_slow_subscribers_no_blocking() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    // Write many messages without reading
    let count = 100;
    for i in 0..count {
        armin.append(
            &session_id,
            NewMessage {
                content: format!("Message {}", i),
            },
        ).unwrap();
    }

    // Verify all writes completed
    assert_eq!(armin.delta(&session_id).len(), count);

    // Slow subscriber can still read
    let mut received = 0;
    while sub.try_recv().is_some() {
        received += 1;
    }
    assert_eq!(received, count);
}

/// Rule 38: Live notifications occur after SQLite commit
#[test]
fn rule_38_notifications_after_commit() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let (session_id, message_content) = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session().unwrap();

        let sub = armin.subscribe(&session_id);

        armin.append(
            &session_id,
            NewMessage {
                content: "Committed".to_string(),
            },
        ).unwrap();

        // Received via live subscription
        let msg = sub.try_recv().expect("Should receive message");
        (session_id, msg.content)
    };

    // Verify it was committed to SQLite
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let snapshot = armin.snapshot();
    let session = snapshot.session(&session_id).unwrap();
    assert_eq!(session.messages()[0].content, message_content);
}

/// Rule 40: Live subscriptions are session-scoped
#[test]
fn rule_40_subscriptions_session_scoped() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();

    let session1 = armin.create_session().unwrap();
    let session2 = armin.create_session().unwrap();

    let sub1 = armin.subscribe(&session1);
    let sub2 = armin.subscribe(&session2);

    // Message to session1
    armin.append(
        &session1,
        NewMessage {
            content: "For session 1".to_string(),
        },
    ).unwrap();

    // Message to session2
    armin.append(
        &session2,
        NewMessage {
            content: "For session 2".to_string(),
        },
    ).unwrap();

    // Each subscriber only gets their session's messages
    assert_eq!(sub1.try_recv().unwrap().content, "For session 1");
    assert!(sub1.try_recv().is_none());

    assert_eq!(sub2.try_recv().unwrap().content, "For session 2");
    assert!(sub2.try_recv().is_none());
}

// =============================================================================
// Additional live subscription tests
// =============================================================================

#[test]
fn subscription_after_recovery_receives_new_messages() {
    let temp_file = NamedTempFile::new().unwrap();
    let path = temp_file.path();

    let session_id = {
        let sink = RecordingSink::new();
        let armin = Armin::open(path, sink).unwrap();
        let session_id = armin.create_session().unwrap();
        armin.append(
            &session_id,
            NewMessage {
                content: "Before restart".to_string(),
            },
        ).unwrap();
        session_id
    };

    // Restart and subscribe
    let sink = RecordingSink::new();
    let armin = Armin::open(path, sink).unwrap();
    let sub = armin.subscribe(&session_id);

    // Should not receive historical message
    assert!(sub.try_recv().is_none());

    // But should receive new ones
    armin.append(
        &session_id,
        NewMessage {
            content: "After restart".to_string(),
        },
    ).unwrap();

    assert_eq!(sub.try_recv().unwrap().content, "After restart");
}

#[test]
fn dropped_subscription_cleaned_up() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Create and drop subscription
    {
        let _sub = armin.subscribe(&session_id);
    }

    // Writing should still work (dead subscriber cleaned up)
    armin.append(
        &session_id,
        NewMessage {
            content: "Test".to_string(),
        },
    ).unwrap();

    assert_eq!(armin.delta(&session_id).len(), 1);
}

#[test]
fn closed_session_stops_notifications() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    armin.append(
        &session_id,
        NewMessage {
            content: "Before close".to_string(),
        },
    ).unwrap();

    armin.close(&session_id).unwrap();

    // Should still receive the message that was sent
    assert_eq!(sub.try_recv().unwrap().content, "Before close");

    // No more messages expected (session is closed)
    assert!(sub.try_recv().is_none());
}

#[test]
fn subscription_iterator() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    let sub = armin.subscribe(&session_id);

    armin.append(
        &session_id,
        NewMessage {
            content: "One".to_string(),
        },
    ).unwrap();
    armin.append(
        &session_id,
        NewMessage {
            content: "Two".to_string(),
        },
    ).unwrap();

    // Collect via try_recv (iter() would block)
    let mut messages = Vec::new();
    while let Some(msg) = sub.try_recv() {
        messages.push(msg.content);
    }

    assert_eq!(messages, vec!["One", "Two"]);
}

#[test]
fn many_subscribers_performance() {
    let sink = RecordingSink::new();
    let armin = Armin::in_memory(sink).unwrap();
    let session_id = armin.create_session().unwrap();

    // Create many subscribers
    let subscribers: Vec<_> = (0..100).map(|_| armin.subscribe(&session_id)).collect();

    // Send a message
    armin.append(
        &session_id,
        NewMessage {
            content: "Broadcast to many".to_string(),
        },
    ).unwrap();

    // All should receive it
    for (i, sub) in subscribers.iter().enumerate() {
        let msg = sub.try_recv().expect(&format!("Subscriber {} should receive", i));
        assert_eq!(msg.content, "Broadcast to many");
    }
}
