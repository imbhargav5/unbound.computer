//! Error types for dependency checking operations.

use thiserror::Error;

/// Errors that can occur during dependency checking.
#[derive(Debug, Error)]
pub enum TienError {
    /// A dependency check command failed to execute.
    #[error("Dependency check failed: {0}")]
    CheckFailed(String),
}

impl From<std::io::Error> for TienError {
    fn from(err: std::io::Error) -> Self {
        TienError::CheckFailed(err.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_check_failed() {
        let err = TienError::CheckFailed("command not found".into());
        assert_eq!(
            err.to_string(),
            "Dependency check failed: command not found"
        );
    }

    #[test]
    fn from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "no such file");
        let err: TienError = io_err.into();
        assert!(err.to_string().contains("no such file"));
    }
}
