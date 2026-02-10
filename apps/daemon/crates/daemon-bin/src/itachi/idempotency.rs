use crate::itachi::contracts::SessionSecretResponsePayload;
use std::collections::HashMap;
use std::time::{Duration, Instant};

const DEFAULT_TTL: Duration = Duration::from_secs(300);

#[derive(Debug, Clone)]
enum EntryState {
    InFlight,
    Completed(SessionSecretResponsePayload),
}

#[derive(Debug, Clone)]
struct Entry {
    expires_at: Instant,
    state: EntryState,
}

#[derive(Debug, Clone)]
pub enum BeginResult {
    New,
    InFlight,
    Completed(SessionSecretResponsePayload),
}

/// In-memory idempotency store for UM secret requests.
#[derive(Debug, Clone)]
pub struct IdempotencyStore {
    ttl: Duration,
    entries: HashMap<String, Entry>,
}

impl Default for IdempotencyStore {
    fn default() -> Self {
        Self::new(DEFAULT_TTL)
    }
}

impl IdempotencyStore {
    pub fn new(ttl: Duration) -> Self {
        Self {
            ttl,
            entries: HashMap::new(),
        }
    }

    pub fn begin(&mut self, key: &str, now: Instant) -> BeginResult {
        self.cleanup(now);

        match self.entries.get_mut(key) {
            Some(entry) => match &entry.state {
                EntryState::InFlight => {
                    entry.expires_at = now + self.ttl;
                    BeginResult::InFlight
                }
                EntryState::Completed(payload) => {
                    entry.expires_at = now + self.ttl;
                    BeginResult::Completed(payload.clone())
                }
            },
            None => {
                self.entries.insert(
                    key.to_string(),
                    Entry {
                        expires_at: now + self.ttl,
                        state: EntryState::InFlight,
                    },
                );
                BeginResult::New
            }
        }
    }

    pub fn complete(&mut self, key: &str, payload: SessionSecretResponsePayload, now: Instant) {
        self.cleanup(now);
        self.entries.insert(
            key.to_string(),
            Entry {
                expires_at: now + self.ttl,
                state: EntryState::Completed(payload),
            },
        );
    }

    pub fn remove(&mut self, key: &str) {
        self.entries.remove(key);
    }

    fn cleanup(&mut self, now: Instant) {
        self.entries.retain(|_, entry| entry.expires_at > now);
    }
}

#[cfg(test)]
mod tests {
    use super::{BeginResult, IdempotencyStore};
    use crate::itachi::contracts::SessionSecretResponsePayload;
    use crate::itachi::errors::ResponseErrorCode;
    use std::time::{Duration, Instant};

    fn make_payload(request_id: &str) -> SessionSecretResponsePayload {
        SessionSecretResponsePayload::error(
            request_id.to_string(),
            "session-1".to_string(),
            "sender".to_string(),
            "receiver".to_string(),
            ResponseErrorCode::InternalError,
            123,
        )
    }

    #[test]
    fn begin_transitions_new_to_inflight() {
        let now = Instant::now();
        let mut store = IdempotencyStore::new(Duration::from_secs(5));

        match store.begin("k1", now) {
            BeginResult::New => {}
            _ => panic!("expected new"),
        }
        match store.begin("k1", now + Duration::from_secs(1)) {
            BeginResult::InFlight => {}
            _ => panic!("expected inflight"),
        }
    }

    #[test]
    fn complete_returns_completed_payload_on_duplicate() {
        let now = Instant::now();
        let mut store = IdempotencyStore::new(Duration::from_secs(5));
        assert!(matches!(store.begin("k1", now), BeginResult::New));

        let payload = make_payload("request-1");
        store.complete("k1", payload.clone(), now);

        match store.begin("k1", now + Duration::from_secs(1)) {
            BeginResult::Completed(found) => assert_eq!(found.request_id, payload.request_id),
            _ => panic!("expected completed"),
        }
    }

    #[test]
    fn ttl_expiration_evicts_entries() {
        let now = Instant::now();
        let mut store = IdempotencyStore::new(Duration::from_secs(1));
        assert!(matches!(store.begin("k1", now), BeginResult::New));
        assert!(matches!(
            store.begin("k1", now + Duration::from_millis(500)),
            BeginResult::InFlight
        ));
        assert!(matches!(
            store.begin("k1", now + Duration::from_secs(2)),
            BeginResult::New
        ));
    }
}
