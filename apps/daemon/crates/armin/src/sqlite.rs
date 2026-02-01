//! SQLite storage layer for the Armin session engine.
//!
//! SQLite is the ONLY durable store. All derived state is rebuilt from SQLite on recovery.
//!
//! # Design Principles
//!
//! - SQLite is the only source of truth
//! - Every write commits to SQLite first
//! - Crash = rebuild from SQLite
//! - No pluggable engines, no alternative backends

use rusqlite::{params, Connection, Result as SqliteResult};
use std::path::Path;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::types::{Message, MessageId, NewMessage, SessionId};

/// Result of an atomic message insertion.
#[derive(Debug, Clone)]
pub struct InsertedMessage {
    pub id: MessageId,
    pub sequence_number: i64,
}

/// SQLite storage for sessions and messages.
///
/// Thread-safe via internal Mutex. All operations acquire the lock.
pub struct SqliteStore {
    conn: Mutex<Connection>,
}

/// A session record from the database.
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct SessionRecord {
    pub id: SessionId,
    pub closed: bool,
    pub created_at: i64,
}

impl SqliteStore {
    /// Opens a SQLite database at the given path.
    ///
    /// Creates the database and schema if they don't exist.
    pub fn open(path: impl AsRef<Path>) -> SqliteResult<Self> {
        let conn = Connection::open(path)?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    /// Creates an in-memory SQLite database.
    ///
    /// Useful for testing.
    pub fn in_memory() -> SqliteResult<Self> {
        let conn = Connection::open_in_memory()?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    /// Initializes the database schema.
    fn init_schema(&self) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                closed INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                content TEXT NOT NULL,
                sequence_number INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );

            CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);
            CREATE INDEX IF NOT EXISTS idx_messages_session_sequence ON messages(session_id, sequence_number);
            "#,
        )?;
        Ok(())
    }

    /// Returns the current Unix timestamp in milliseconds.
    fn now_millis() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time went backwards")
            .as_millis() as i64
    }

    // ========================================================================
    // Session operations
    // ========================================================================

    /// Creates a new session with a generated UUID.
    pub fn create_session(&self) -> SqliteResult<SessionId> {
        let id = SessionId::new();
        self.create_session_with_id(id.clone())?;
        Ok(id)
    }

    /// Creates a session with a specific ID.
    pub fn create_session_with_id(&self, id: SessionId) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_millis();
        conn.execute(
            "INSERT INTO sessions (id, closed, created_at) VALUES (?, 0, ?)",
            params![id.as_str(), now],
        )?;
        Ok(())
    }

    /// Gets a session by ID.
    #[allow(dead_code)]
    pub fn get_session(&self, id: &SessionId) -> SqliteResult<Option<SessionRecord>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare("SELECT id, closed, created_at FROM sessions WHERE id = ?")?;
        let mut rows = stmt.query(params![id.as_str()])?;

        if let Some(row) = rows.next()? {
            Ok(Some(SessionRecord {
                id: SessionId::from_string(row.get::<_, String>(0)?),
                closed: row.get::<_, i64>(1)? != 0,
                created_at: row.get(2)?,
            }))
        } else {
            Ok(None)
        }
    }

    /// Lists all sessions.
    pub fn list_sessions(&self) -> SqliteResult<Vec<SessionRecord>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare("SELECT id, closed, created_at FROM sessions ORDER BY created_at")?;
        let rows = stmt.query_map([], |row| {
            Ok(SessionRecord {
                id: SessionId::from_string(row.get::<_, String>(0)?),
                closed: row.get::<_, i64>(1)? != 0,
                created_at: row.get(2)?,
            })
        })?;

        let mut sessions = Vec::new();
        for row in rows {
            sessions.push(row?);
        }
        Ok(sessions)
    }

    /// Closes a session.
    ///
    /// Returns true if the session was open and is now closed.
    /// Returns false if the session didn't exist or was already closed.
    pub fn close_session(&self, id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let affected = conn.execute(
            "UPDATE sessions SET closed = 1 WHERE id = ? AND closed = 0",
            params![id.as_str()],
        )?;
        Ok(affected > 0)
    }

    /// Checks if a session exists and is not closed.
    pub fn is_session_open(&self, id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare("SELECT closed FROM sessions WHERE id = ?")?;
        let mut rows = stmt.query(params![id.as_str()])?;

        if let Some(row) = rows.next()? {
            let closed: i64 = row.get(0)?;
            Ok(closed == 0)
        } else {
            Ok(false)
        }
    }

    // ========================================================================
    // Message operations
    // ========================================================================

    /// Inserts a message into a session with atomic sequence assignment.
    ///
    /// The sequence number is computed in the same SQL statement as the insert,
    /// guaranteeing no race conditions. This is a single SQLite operation.
    ///
    /// Returns the assigned message ID and sequence number.
    pub fn insert_message(&self, session: &SessionId, msg: &NewMessage) -> SqliteResult<InsertedMessage> {
        let id = MessageId::new();
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_millis();

        // Atomic insert with sequence number computed in subquery
        let mut stmt = conn.prepare(
            r#"
            INSERT INTO messages (id, session_id, content, sequence_number, created_at)
            VALUES (?1, ?2, ?3,
                (SELECT COALESCE(MAX(sequence_number), 0) + 1 FROM messages WHERE session_id = ?2),
                ?4)
            RETURNING sequence_number
            "#,
        )?;

        let sequence_number: i64 = stmt.query_row(
            params![id.as_str(), session.as_str(), msg.content, now],
            |row| row.get(0),
        )?;

        Ok(InsertedMessage { id, sequence_number })
    }

    /// Inserts a message with a specific ID and sequence number.
    ///
    /// This is primarily for testing. Production code should use `insert_message()`
    /// which assigns sequence numbers atomically.
    #[cfg(test)]
    pub fn insert_message_with_id(
        &self,
        session: &SessionId,
        id: &MessageId,
        content: &str,
        sequence_number: i64,
    ) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_millis();
        conn.execute(
            "INSERT INTO messages (id, session_id, content, sequence_number, created_at) VALUES (?, ?, ?, ?, ?)",
            params![id.as_str(), session.as_str(), content, sequence_number, now],
        )?;
        Ok(())
    }

    /// Gets all messages for a session.
    pub fn get_messages(&self, session: &SessionId) -> SqliteResult<Vec<Message>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare(
            "SELECT id, content, sequence_number FROM messages WHERE session_id = ? ORDER BY sequence_number",
        )?;
        let rows = stmt.query_map(params![session.as_str()], |row| {
            let id = MessageId::from_string(row.get::<_, String>(0)?);
            let content: String = row.get(1)?;
            let sequence_number: i64 = row.get(2)?;
            Ok(Message {
                id,
                content,
                sequence_number,
            })
        })?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(row?);
        }
        Ok(messages)
    }

    /// Gets the message count for a session.
    #[allow(dead_code)]
    pub fn get_message_count(&self, session: &SessionId) -> SqliteResult<u64> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare("SELECT COUNT(*) FROM messages WHERE session_id = ?")?;
        let mut rows = stmt.query(params![session.as_str()])?;

        if let Some(row) = rows.next()? {
            let count: i64 = row.get(0)?;
            Ok(count as u64)
        } else {
            Ok(0)
        }
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_and_get_session() {
        let store = SqliteStore::in_memory().unwrap();
        let id = store.create_session().unwrap();

        let session = store.get_session(&id).unwrap().unwrap();
        assert_eq!(session.id, id);
        assert!(!session.closed);
    }

    #[test]
    fn create_session_with_specific_id() {
        let store = SqliteStore::in_memory().unwrap();
        let id = SessionId::from_string("my-custom-session-id");
        store.create_session_with_id(id.clone()).unwrap();

        let session = store.get_session(&id).unwrap().unwrap();
        assert_eq!(session.id.as_str(), "my-custom-session-id");
    }

    #[test]
    fn close_session() {
        let store = SqliteStore::in_memory().unwrap();
        let id = store.create_session().unwrap();

        assert!(store.is_session_open(&id).unwrap());
        store.close_session(&id).unwrap();
        assert!(!store.is_session_open(&id).unwrap());
    }

    #[test]
    fn insert_and_get_messages() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        let msg1 = NewMessage {
            content: "Hello".to_string(),
        };
        let msg2 = NewMessage {
            content: "Hi there!".to_string(),
        };

        let inserted1 = store.insert_message(&session_id, &msg1).unwrap();
        let inserted2 = store.insert_message(&session_id, &msg2).unwrap();

        // Verify atomic sequence assignment
        assert_eq!(inserted1.sequence_number, 1);
        assert_eq!(inserted2.sequence_number, 2);

        let messages = store.get_messages(&session_id).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, inserted1.id);
        assert_eq!(messages[0].content, "Hello");
        assert_eq!(messages[0].sequence_number, 1);
        assert_eq!(messages[1].id, inserted2.id);
        assert_eq!(messages[1].content, "Hi there!");
        assert_eq!(messages[1].sequence_number, 2);
    }

    #[test]
    fn message_count() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        assert_eq!(store.get_message_count(&session_id).unwrap(), 0);

        store
            .insert_message(
                &session_id,
                &NewMessage {
                    content: "Test".to_string(),
                },
            )
            .unwrap();

        assert_eq!(store.get_message_count(&session_id).unwrap(), 1);
    }

    #[test]
    fn atomic_sequence_assignment() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        // First message should get sequence 1
        let inserted1 = store
            .insert_message(&session_id, &NewMessage { content: "First".to_string() })
            .unwrap();
        assert_eq!(inserted1.sequence_number, 1);

        // Second message should get sequence 2
        let inserted2 = store
            .insert_message(&session_id, &NewMessage { content: "Second".to_string() })
            .unwrap();
        assert_eq!(inserted2.sequence_number, 2);

        // Third message should get sequence 3
        let inserted3 = store
            .insert_message(&session_id, &NewMessage { content: "Third".to_string() })
            .unwrap();
        assert_eq!(inserted3.sequence_number, 3);
    }

    #[test]
    fn sequence_is_per_session() {
        let store = SqliteStore::in_memory().unwrap();
        let session1 = store.create_session().unwrap();
        let session2 = store.create_session().unwrap();

        // Each session has independent sequence numbers
        let msg1 = store
            .insert_message(&session1, &NewMessage { content: "S1-M1".to_string() })
            .unwrap();
        let msg2 = store
            .insert_message(&session2, &NewMessage { content: "S2-M1".to_string() })
            .unwrap();
        let msg3 = store
            .insert_message(&session1, &NewMessage { content: "S1-M2".to_string() })
            .unwrap();

        assert_eq!(msg1.sequence_number, 1); // session1 starts at 1
        assert_eq!(msg2.sequence_number, 1); // session2 starts at 1
        assert_eq!(msg3.sequence_number, 2); // session1 continues to 2
    }
}
