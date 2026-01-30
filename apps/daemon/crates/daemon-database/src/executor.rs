//! Async SQLite executor using a dedicated background thread.
//!
//! This module provides an async-friendly interface to SQLite that:
//! - Uses a single dedicated thread for all SQLite operations
//! - Sends queries through a channel (non-blocking from caller's perspective)
//! - Keeps the Tokio runtime free for other async work
//!
//! # Design Principles
//!
//! 1. **Single writer**: SQLite serializes writes anyway, so one thread is optimal
//! 2. **No blocking in async context**: Callers await results without blocking threads
//! 3. **Predictable latency**: Queries execute in FIFO order
//! 4. **DB-only operations**: Only SQL queries should run inside `call()` - no crypto, no mutexes
//!
//! # Example
//!
//! ```ignore
//! let db = AsyncDatabase::open(path).await?;
//!
//! // Execute a query - runs on dedicated thread, caller awaits result
//! let repos = db.call(|conn| {
//!     queries::list_repositories(conn)
//! }).await?;
//!
//! // WRONG: Don't do heavy work inside call()
//! // db.call(|conn| {
//! //     let data = queries::get_data(conn)?;
//! //     decrypt_all(data)  // NO! Do this outside call()
//! // }).await;
//! ```

use crate::{migrations, DatabaseError, DatabaseResult};
use std::path::Path;
use tokio_rusqlite::Connection;
use tracing::{debug, info};

/// Convert a tokio_rusqlite::Error to DatabaseError.
fn from_tokio_rusqlite(e: tokio_rusqlite::Error) -> DatabaseError {
    match e {
        tokio_rusqlite::Error::Rusqlite(e) => DatabaseError::Sqlite(e),
        tokio_rusqlite::Error::Close(_) => DatabaseError::Connection("Connection closed".to_string()),
        other => DatabaseError::Connection(other.to_string()),
    }
}

/// Async SQLite database with a dedicated executor thread.
///
/// All operations are sent to a single background thread via channel.
/// This avoids blocking the Tokio runtime and provides predictable
/// query ordering (FIFO).
#[derive(Clone)]
pub struct AsyncDatabase {
    conn: Connection,
    path: String,
}

impl AsyncDatabase {
    /// Open a database at the given path.
    ///
    /// This will:
    /// - Create the database file if it doesn't exist
    /// - Enable WAL mode and performance pragmas
    /// - Run any pending migrations
    /// - Start the dedicated executor thread
    pub async fn open(path: &Path) -> DatabaseResult<Self> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let path_str = path.to_string_lossy().to_string();
        let path_for_open = path_str.clone();

        info!(path = %path_str, "Opening async database");

        // Open connection - this spawns the dedicated background thread
        let conn = Connection::open(&path_for_open)
            .await
            .map_err(|e| DatabaseError::Connection(e.to_string()))?;

        // Configure pragmas for performance
        conn.call(|conn| {
            conn.execute_batch(
                "
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = NORMAL;
                PRAGMA foreign_keys = ON;
                PRAGMA cache_size = -64000;
                PRAGMA temp_store = MEMORY;
                PRAGMA mmap_size = 268435456;
                PRAGMA busy_timeout = 5000;
                ",
            )?;
            Ok(())
        })
        .await
        .map_err(from_tokio_rusqlite)?;

        // Run migrations
        conn.call(|conn| {
            migrations::run_migrations(conn)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
            Ok(())
        })
        .await
        .map_err(from_tokio_rusqlite)?;

        info!(path = %path_str, "Async database initialized with WAL mode");

        Ok(Self {
            conn,
            path: path_str,
        })
    }

    /// Execute a closure on the database connection.
    ///
    /// The closure runs on the dedicated SQLite thread. The caller's async
    /// task is parked (not blocked) until the result is ready.
    ///
    /// # Critical Section Rules
    ///
    /// Inside the closure, you may ONLY do:
    /// - SQL queries (SELECT, INSERT, UPDATE, DELETE)
    /// - Lightweight row mapping
    ///
    /// You must NOT do:
    /// - Encryption/decryption
    /// - Mutex locking
    /// - File I/O
    /// - Network calls
    /// - Heavy computation
    ///
    /// These operations block the single DB thread, starving all other queries.
    ///
    /// # Example
    ///
    /// ```ignore
    /// // GOOD: SQL only
    /// let repos = db.call(|conn| {
    ///     queries::list_repositories(conn)
    /// }).await?;
    ///
    /// // BAD: Crypto inside call
    /// let data = db.call(|conn| {
    ///     let rows = queries::get_encrypted(conn)?;
    ///     decrypt_all(rows)  // WRONG! Do this outside
    /// }).await?;
    /// ```
    pub async fn call<F, T>(&self, f: F) -> DatabaseResult<T>
    where
        F: FnOnce(&rusqlite::Connection) -> DatabaseResult<T> + Send + 'static,
        T: Send + 'static,
    {
        // Strategy: Wrap our DatabaseResult<T> inside the tokio_rusqlite Ok variant.
        // tokio_rusqlite::Error implements From<rusqlite::Error>, so we use that.
        //
        // Inner type: Result<DatabaseResult<T>, tokio_rusqlite::Error>
        // After await: Result<DatabaseResult<T>, tokio_rusqlite::Error>
        // After flatten: DatabaseResult<T>
        let outer_result = self.conn
            .call(move |conn| {
                let inner_result = f(conn);
                // Return Ok with our DatabaseResult wrapped inside
                Ok(inner_result)
            })
            .await;

        match outer_result {
            Ok(inner) => inner,
            Err(e) => Err(from_tokio_rusqlite(e)),
        }
    }

    /// Execute a closure that returns a rusqlite::Result.
    ///
    /// Convenience method for simple queries that only produce rusqlite errors.
    pub async fn call_sqlite<F, T>(&self, f: F) -> DatabaseResult<T>
    where
        F: FnOnce(&rusqlite::Connection) -> rusqlite::Result<T> + Send + 'static,
        T: Send + 'static,
    {
        // Use ? to convert rusqlite::Error to tokio_rusqlite::Error
        self.conn
            .call(move |conn| Ok(f(conn)?))
            .await
            .map_err(from_tokio_rusqlite)
    }

    /// Get the database file path.
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Check if the database is healthy by executing a simple query.
    pub async fn health_check(&self) -> DatabaseResult<()> {
        self.call_sqlite(|conn| {
            conn.execute_batch("SELECT 1")
        })
        .await?;
        debug!("Database health check passed");
        Ok(())
    }

    /// Close the database connection.
    ///
    /// This will wait for any pending operations to complete,
    /// then shut down the executor thread.
    pub async fn close(self) -> DatabaseResult<()> {
        self.conn
            .close()
            .await
            .map_err(|e| DatabaseError::Connection(format!("Failed to close database: {:?}", e)))?;
        info!(path = %self.path, "Database closed");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_async_database_open() {
        let dir = tempdir().unwrap();
        let db_path = dir.path().join("test.db");

        let db = AsyncDatabase::open(&db_path).await.unwrap();
        assert!(db.health_check().await.is_ok());
    }

    #[tokio::test]
    async fn test_async_database_query() {
        let dir = tempdir().unwrap();
        let db_path = dir.path().join("test_query.db");

        let db = AsyncDatabase::open(&db_path).await.unwrap();

        // Create a test table
        db.call_sqlite(|conn| {
            conn.execute(
                "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, name TEXT)",
                [],
            )
        })
        .await
        .unwrap();

        // Insert data
        db.call_sqlite(|conn| {
            conn.execute("INSERT INTO test (name) VALUES (?1)", ["Alice"])
        })
        .await
        .unwrap();

        // Query data
        let names: Vec<String> = db
            .call(|conn| {
                let mut stmt = conn.prepare("SELECT name FROM test")?;
                let names: Vec<String> = stmt
                    .query_map([], |row| row.get(0))?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(names)
            })
            .await
            .unwrap();

        assert_eq!(names, vec!["Alice"]);
    }

    #[tokio::test]
    async fn test_concurrent_queries() {
        let dir = tempdir().unwrap();
        let db_path = dir.path().join("test_concurrent.db");

        let db = AsyncDatabase::open(&db_path).await.unwrap();

        // Create test table
        db.call_sqlite(|conn| {
            conn.execute_batch(
                "CREATE TABLE IF NOT EXISTS counter (id INTEGER PRIMARY KEY, val INTEGER);
                 INSERT INTO counter (val) VALUES (0);"
            )
        })
        .await
        .unwrap();

        // Spawn multiple concurrent tasks
        let mut handles = vec![];
        for _ in 0..10 {
            let db = db.clone();
            handles.push(tokio::spawn(async move {
                db.call_sqlite(|conn| {
                    conn.execute("UPDATE counter SET val = val + 1 WHERE id = 1", [])
                })
                .await
            }));
        }

        // Wait for all to complete
        for handle in handles {
            handle.await.unwrap().unwrap();
        }

        // Verify final count
        let count: i32 = db
            .call(|conn| {
                conn.query_row("SELECT val FROM counter WHERE id = 1", [], |row| row.get(0))
                    .map_err(DatabaseError::from)
            })
            .await
            .unwrap();

        assert_eq!(count, 10);
    }
}
