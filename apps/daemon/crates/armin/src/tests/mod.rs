//! Integration tests for the Armin session engine.
//!
//! Test organization follows the Armin Test Rules (120 rules):
//!
//! - `durability.rs`   - Rules 1-10 (SQLite & Durability) + 71-80 (Crash & Recovery)
//! - `side_effects.rs` - Rules 11-20 (Side-effect Emission)
//! - `delta.rs`        - Rules 21-30 (Delta/Live Tail)
//! - `live.rs`         - Rules 31-40 (Live Subscriptions)
//! - `snapshot.rs`     - Rules 41-50 (Snapshots)
//! - `reads.rs`        - Rules 51-60 (Read Path Purity)
//! - `ordering.rs`     - Rules 61-70 (Ordering & Consistency)
//! - `concurrency.rs`  - Rules 81-90 (Concurrency & Isolation)
//! - `failures.rs`     - Rules 91-100 (Failure Injection)
//! - `invariants.rs`   - Rules 101-120 (Boundary, Invariants, & Meta)

mod concurrency;
mod delta;
mod durability;
mod failures;
mod invariants;
mod live;
mod ordering;
mod reads;
mod recovery;
mod side_effects;
mod snapshot;

use crate::reader::SessionReader;
use crate::side_effect::RecordingSink;
use crate::types::{NewMessage, Role};
use crate::writer::SessionWriter;
use crate::{Armin, SideEffect};

/// Basic workflow test demonstrating core functionality.
#[test]
fn basic_workflow() {
    let sink = RecordingSink::new();
    let engine = Armin::in_memory(sink).unwrap();

    // Create session
    let session_id = engine.create_session();

    // Append messages
    let _msg1 = engine.append(
        session_id,
        NewMessage {
            role: Role::User,
            content: "Hello".to_string(),
        },
    );
    let _msg2 = engine.append(
        session_id,
        NewMessage {
            role: Role::Assistant,
            content: "Hi there!".to_string(),
        },
    );

    // Verify delta
    let delta = engine.delta(session_id);
    assert_eq!(delta.len(), 2);

    // Verify side-effects
    let effects = engine.sink().effects();
    assert_eq!(effects.len(), 3);
    assert!(matches!(effects[0], SideEffect::SessionCreated { .. }));
    assert!(matches!(effects[1], SideEffect::MessageAppended { .. }));
    assert!(matches!(effects[2], SideEffect::MessageAppended { .. }));

    // Close session
    engine.close(session_id);
    assert_eq!(engine.sink().len(), 4);
}
