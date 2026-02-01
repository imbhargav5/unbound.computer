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
use std::time::{SystemTime, UNIX_EPOCH};

use crate::types::{Message, MessageId, NewMessage, Role, SessionId};

/// SQLite storage for sessions and messages.
pub struct SqliteStore {
    conn: Connection,
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
        let store = Self { conn };
        store.init_schema()?;
        Ok(store)
    }

    /// Creates an in-memory SQLite database.
    ///
    /// Useful for testing.
    pub fn in_memory() -> SqliteResult<Self> {
        let conn = Connection::open_in_memory()?;
        let store = Self { conn };
        store.init_schema()?;
        Ok(store)
    }

    /// Initializes the database schema.
    fn init_schema(&self) -> SqliteResult<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                closed INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                role INTEGER NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );

            CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);
            CREATE INDEX IF NOT EXISTS idx_messages_session_created ON messages(session_id, created_at);
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

    /// Creates a new session.
    pub fn create_session(&self) -> SqliteResult<SessionId> {
        let now = Self::now_millis();
        self.conn.execute(
            "INSERT INTO sessions (closed, created_at) VALUES (0, ?)",
            params![now],
        )?;
        let id = self.conn.last_insert_rowid() as u64;
        Ok(SessionId(id))
    }

    /// Gets a session by ID.
    #[allow(dead_code)]
    pub fn get_session(&self, id: SessionId) -> SqliteResult<Option<SessionRecord>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, closed, created_at FROM sessions WHERE id = ?")?;
        let mut rows = stmt.query(params![id.0])?;

        if let Some(row) = rows.next()? {
            Ok(Some(SessionRecord {
                id: SessionId(row.get::<_, i64>(0)? as u64),
                closed: row.get::<_, i64>(1)? != 0,
                created_at: row.get(2)?,
            }))
        } else {
            Ok(None)
        }
    }

    /// Lists all sessions.
    pub fn list_sessions(&self) -> SqliteResult<Vec<SessionRecord>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, closed, created_at FROM sessions ORDER BY id")?;
        let rows = stmt.query_map([], |row| {
            Ok(SessionRecord {
                id: SessionId(row.get::<_, i64>(0)? as u64),
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
    pub fn close_session(&self, id: SessionId) -> SqliteResult<bool> {
        let affected = self.conn.execute(
            "UPDATE sessions SET closed = 1 WHERE id = ? AND closed = 0",
            params![id.0],
        )?;
        Ok(affected > 0)
    }

    /// Checks if a session exists and is not closed.
    pub fn is_session_open(&self, id: SessionId) -> SqliteResult<bool> {
        let mut stmt = self
            .conn
            .prepare("SELECT closed FROM sessions WHERE id = ?")?;
        let mut rows = stmt.query(params![id.0])?;

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

    /// Inserts a message into a session.
    pub fn insert_message(&self, session: SessionId, msg: &NewMessage) -> SqliteResult<MessageId> {
        let now = Self::now_millis();
        self.conn.execute(
            "INSERT INTO messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            params![session.0, msg.role.to_i32(), msg.content, now],
        )?;
        let id = self.conn.last_insert_rowid() as u64;
        Ok(MessageId(id))
    }

    /// Gets all messages for a session.
    pub fn get_messages(&self, session: SessionId) -> SqliteResult<Vec<Message>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, role, content FROM messages WHERE session_id = ? ORDER BY id",
        )?;
        let rows = stmt.query_map(params![session.0], |row| {
            let id = MessageId(row.get::<_, i64>(0)? as u64);
            let role_int: i32 = row.get(1)?;
            let role = Role::from_i32(role_int).unwrap_or(Role::User);
            let content: String = row.get(2)?;
            Ok(Message { id, role, content })
        })?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(row?);
        }
        Ok(messages)
    }

    /// Gets messages for a session after a given message ID.
    #[allow(dead_code)]
    pub fn get_messages_after(
        &self,
        session: SessionId,
        after: MessageId,
    ) -> SqliteResult<Vec<Message>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, role, content FROM messages WHERE session_id = ? AND id > ? ORDER BY id",
        )?;
        let rows = stmt.query_map(params![session.0, after.0], |row| {
            let id = MessageId(row.get::<_, i64>(0)? as u64);
            let role_int: i32 = row.get(1)?;
            let role = Role::from_i32(role_int).unwrap_or(Role::User);
            let content: String = row.get(2)?;
            Ok(Message { id, role, content })
        })?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(row?);
        }
        Ok(messages)
    }

    /// Gets the last message ID for a session, or None if no messages exist.
    #[allow(dead_code)]
    pub fn get_last_message_id(&self, session: SessionId) -> SqliteResult<Option<MessageId>> {
        let mut stmt = self
            .conn
            .prepare("SELECT MAX(id) FROM messages WHERE session_id = ?")?;
        let mut rows = stmt.query(params![session.0])?;

        if let Some(row) = rows.next()? {
            let id: Option<i64> = row.get(0)?;
            Ok(id.map(|i| MessageId(i as u64)))
        } else {
            Ok(None)
        }
    }

    /// Gets the message count for a session.
    #[allow(dead_code)]
    pub fn get_message_count(&self, session: SessionId) -> SqliteResult<u64> {
        let mut stmt = self
            .conn
            .prepare("SELECT COUNT(*) FROM messages WHERE session_id = ?")?;
        let mut rows = stmt.query(params![session.0])?;

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

        let session = store.get_session(id).unwrap().unwrap();
        assert_eq!(session.id, id);
        assert!(!session.closed);
    }

    #[test]
    fn close_session() {
        let store = SqliteStore::in_memory().unwrap();
        let id = store.create_session().unwrap();

        assert!(store.is_session_open(id).unwrap());
        store.close_session(id).unwrap();
        assert!(!store.is_session_open(id).unwrap());
    }

    #[test]
    fn insert_and_get_messages() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        let msg1 = NewMessage {
            role: Role::User,
            content: "Hello".to_string(),
        };
        let msg2 = NewMessage {
            role: Role::Assistant,
            content: "Hi there!".to_string(),
        };

        let id1 = store.insert_message(session_id, &msg1).unwrap();
        let id2 = store.insert_message(session_id, &msg2).unwrap();

        let messages = store.get_messages(session_id).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, id1);
        assert_eq!(messages[0].role, Role::User);
        assert_eq!(messages[0].content, "Hello");
        assert_eq!(messages[1].id, id2);
        assert_eq!(messages[1].role, Role::Assistant);
        assert_eq!(messages[1].content, "Hi there!");
    }

    #[test]
    fn get_messages_after() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        let msg1 = NewMessage {
            role: Role::User,
            content: "First".to_string(),
        };
        let msg2 = NewMessage {
            role: Role::Assistant,
            content: "Second".to_string(),
        };
        let msg3 = NewMessage {
            role: Role::User,
            content: "Third".to_string(),
        };

        let id1 = store.insert_message(session_id, &msg1).unwrap();
        store.insert_message(session_id, &msg2).unwrap();
        store.insert_message(session_id, &msg3).unwrap();

        let messages = store.get_messages_after(session_id, id1).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].content, "Second");
        assert_eq!(messages[1].content, "Third");
    }

    #[test]
    fn message_count() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        assert_eq!(store.get_message_count(session_id).unwrap(), 0);

        store
            .insert_message(
                session_id,
                &NewMessage {
                    role: Role::User,
                    content: "Test".to_string(),
                },
            )
            .unwrap();

        assert_eq!(store.get_message_count(session_id).unwrap(), 1);
    }

    #[test]
    fn last_message_id() {
        let store = SqliteStore::in_memory().unwrap();
        let session_id = store.create_session().unwrap();

        assert!(store.get_last_message_id(session_id).unwrap().is_none());

        let id = store
            .insert_message(
                session_id,
                &NewMessage {
                    role: Role::User,
                    content: "Test".to_string(),
                },
            )
            .unwrap();

        assert_eq!(store.get_last_message_id(session_id).unwrap(), Some(id));
    }
}
