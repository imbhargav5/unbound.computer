//! Git operations wrapper around daemon-core.

use std::path::Path;

// Re-export daemon_core git operations for convenience
pub use daemon_core::{get_file_diff, get_status};

/// Wrapper for get_status that takes a string path.
#[allow(dead_code)]
pub fn get_status_from_path(repo_path: &str) -> Result<daemon_core::GitStatusResult, String> {
    get_status(Path::new(repo_path))
}

/// Wrapper for get_file_diff that takes string paths.
#[allow(dead_code)]
pub fn get_file_diff_from_paths(
    repo_path: &str,
    file_path: &str,
    max_lines: Option<usize>,
) -> Result<daemon_core::GitDiffResult, String> {
    get_file_diff(Path::new(repo_path), file_path, max_lines)
}
