use daemon_database::DatabaseError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum BoardError {
    #[error(transparent)]
    Database(#[from] DatabaseError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error("Not found: {0}")]
    NotFound(String),
    #[error("Conflict: {0}")]
    Conflict(String),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("Agent runtime error: {0}")]
    Runtime(String),
}

pub type BoardResult<T> = Result<T, BoardError>;
