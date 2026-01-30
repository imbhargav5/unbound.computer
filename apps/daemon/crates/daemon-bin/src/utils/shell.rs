//! Shell command building utilities.

/// Escape a string for use in a shell command.
pub fn shell_escape(s: &str) -> String {
    // Use single quotes and escape any single quotes within
    let escaped = s.replace('\'', "'\"'\"'");
    format!("'{}'", escaped)
}
