//! Connection pool for concurrent database access.
//!
//! This module provides a thread-safe connection pool using r2d2 and SQLite WAL mode.
//! WAL mode allows concurrent readers while writes are serialized.

use crate::{migrations, DatabaseError, DatabaseResult};
use r2d2::{Pool, PooledConnection};
use r2d2_sqlite::SqliteConnectionManager;
use std::path::Path;
use std::time::Duration;
use tracing::{debug, info};

/// Configuration for the database pool.
#[derive(Debug, Clone)]
pub struct PoolConfig {
    /// Maximum connections in the pool.
    pub max_size: u32,
    /// Minimum idle connections to maintain.
    pub min_idle: Option<u32>,
    /// Connection acquisition timeout.
    pub connection_timeout: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_size: 10,
            min_idle: Some(2),
            connection_timeout: Duration::from_secs(30),
        }
    }
}

/// Pool statistics for monitoring.
#[derive(Debug, Clone)]
pub struct PoolState {
    /// Total connections (active + idle).
    pub connections: u32,
    /// Currently idle connections.
    pub idle_connections: u32,
}

/// Thread-safe database connection pool.
///
/// Uses SQLite WAL mode for concurrent read access.
/// Writes are still serialized by SQLite but don't block readers.
pub struct DatabasePool {
    pool: Pool<SqliteConnectionManager>,
    path: String,
}

impl DatabasePool {
    /// Create a new database pool at the given path.
    ///
    /// This will:
    /// - Create the database file if it doesn't exist
    /// - Enable WAL mode and performance pragmas
    /// - Run any pending migrations
    /// - Initialize the connection pool
    pub fn open(path: &Path, config: PoolConfig) -> DatabaseResult<Self> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let path_str = path.to_string_lossy().to_string();

        let manager = SqliteConnectionManager::file(path).with_init(|conn| {
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
        });

        let pool = Pool::builder()
            .max_size(config.max_size)
            .min_idle(config.min_idle)
            .connection_timeout(config.connection_timeout)
            .build(manager)
            .map_err(|e| DatabaseError::Connection(e.to_string()))?;

        info!(
            path = %path_str,
            max_size = config.max_size,
            "Database pool created"
        );

        // Run migrations on a dedicated connection
        {
            let conn = pool
                .get()
                .map_err(|e| DatabaseError::Connection(e.to_string()))?;
            migrations::run_migrations(&conn)?;
        }

        Ok(Self {
            pool,
            path: path_str,
        })
    }

    /// Get a connection from the pool.
    ///
    /// This will block until a connection is available or the timeout is reached.
    /// Connections are automatically returned to the pool when dropped.
    pub fn get(&self) -> DatabaseResult<PooledConnection<SqliteConnectionManager>> {
        self.pool
            .get()
            .map_err(|e| DatabaseError::Connection(e.to_string()))
    }

    /// Get pool statistics for monitoring.
    pub fn state(&self) -> PoolState {
        let state = self.pool.state();
        PoolState {
            connections: state.connections,
            idle_connections: state.idle_connections,
        }
    }

    /// Get the database path.
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Check if the pool is healthy by acquiring and releasing a connection.
    pub fn health_check(&self) -> DatabaseResult<()> {
        let conn = self.get()?;
        conn.execute_batch("SELECT 1")?;
        debug!("Database pool health check passed");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;

    #[test]
    fn test_pool_config_default() {
        let config = PoolConfig::default();
        assert_eq!(config.max_size, 10);
        assert_eq!(config.min_idle, Some(2));
        assert_eq!(config.connection_timeout, Duration::from_secs(30));
    }

    #[test]
    fn test_pool_open_in_memory() {
        // r2d2_sqlite doesn't support :memory: directly, use temp file
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("test.db");

        let pool = DatabasePool::open(&db_path, PoolConfig::default()).unwrap();
        assert!(pool.health_check().is_ok());

        let state = pool.state();
        assert!(state.connections >= 1);
    }

    #[test]
    fn test_pool_concurrent_access() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("test_concurrent.db");

        let pool = Arc::new(DatabasePool::open(&db_path, PoolConfig::default()).unwrap());

        // Spawn multiple threads that each get a connection and do a query
        let handles: Vec<_> = (0..5)
            .map(|i| {
                let pool = Arc::clone(&pool);
                thread::spawn(move || {
                    let conn = pool.get().unwrap();
                    let result: i32 = conn
                        .query_row("SELECT ?1", [i], |row| row.get(0))
                        .unwrap();
                    assert_eq!(result, i);
                })
            })
            .collect();

        for handle in handles {
            handle.join().unwrap();
        }
    }

    #[test]
    fn test_pool_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("test_state.db");

        let config = PoolConfig {
            max_size: 5,
            min_idle: Some(2),
            connection_timeout: Duration::from_secs(5),
        };

        let pool = DatabasePool::open(&db_path, config).unwrap();
        let state = pool.state();

        assert!(state.connections <= 5);
        assert!(state.idle_connections <= state.connections);
    }
}
