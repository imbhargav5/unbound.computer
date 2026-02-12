//! File system paths for the daemon.

use crate::{CoreError, CoreResult};
use std::path::PathBuf;

/// Bundle identifier for the macOS app (shared database location).
const BUNDLE_IDENTIFIER: &str = "com.unbound.macos";
/// Falco socket filename under the base runtime directory.
const FALCO_SOCKET_NAME: &str = "falco.sock";
/// Nagato socket filename under the base runtime directory.
const NAGATO_SOCKET_NAME: &str = "nagato.sock";
/// Ably token broker socket filename under the base runtime directory.
const ABLY_AUTH_SOCKET_NAME: &str = "ably-auth.sock";

/// Manages file system paths for the daemon.
#[derive(Debug, Clone)]
pub struct Paths {
    /// Base directory for daemon runtime files (~/.unbound)
    base_dir: PathBuf,
    /// Application Support directory for shared data (database)
    app_support_dir: PathBuf,
}

impl Paths {
    /// Create a new Paths instance.
    ///
    /// Uses `~/.unbound` for runtime files and
    /// `~/Library/Application Support/com.unbound.macos` for shared data (database).
    pub fn new() -> CoreResult<Self> {
        let home = dirs::home_dir()
            .ok_or_else(|| CoreError::Path("Could not determine home directory".to_string()))?;

        let base_dir = home.join(".unbound");

        // Use the same Application Support directory as the macOS app
        let app_support_dir = home
            .join("Library")
            .join("Application Support")
            .join(BUNDLE_IDENTIFIER);

        Ok(Self {
            base_dir,
            app_support_dir,
        })
    }

    /// Create a new Paths instance with a custom base directory.
    pub fn with_base_dir(base_dir: PathBuf) -> Self {
        Self {
            app_support_dir: base_dir.clone(),
            base_dir,
        }
    }

    /// Get the base directory (~/.unbound).
    pub fn base_dir(&self) -> &PathBuf {
        &self.base_dir
    }

    /// Get the config file path (~/.unbound/config.json).
    pub fn config_file(&self) -> PathBuf {
        self.base_dir.join("config.json")
    }

    /// Get the database file path (~/Library/Application Support/com.unbound.macos/unbound.sqlite).
    /// This is shared with the macOS app.
    pub fn database_file(&self) -> PathBuf {
        self.app_support_dir.join("unbound.sqlite")
    }

    /// Get the IPC socket path (~/.unbound/daemon.sock).
    pub fn socket_file(&self) -> PathBuf {
        self.base_dir.join("daemon.sock")
    }

    /// Get the PID file path (~/.unbound/daemon.pid).
    pub fn pid_file(&self) -> PathBuf {
        self.base_dir.join("daemon.pid")
    }

    /// Get the Falco socket path (~/.unbound/falco.sock).
    pub fn falco_socket_file(&self) -> PathBuf {
        self.base_dir.join(FALCO_SOCKET_NAME)
    }

    /// Get the Nagato socket path (~/.unbound/nagato.sock).
    pub fn nagato_socket_file(&self) -> PathBuf {
        self.base_dir.join(NAGATO_SOCKET_NAME)
    }

    /// Get the Ably token broker socket path (~/.unbound/ably-auth.sock).
    pub fn ably_auth_socket_file(&self) -> PathBuf {
        self.base_dir.join(ABLY_AUTH_SOCKET_NAME)
    }

    /// Get the logs directory (~/.unbound/logs).
    pub fn logs_dir(&self) -> PathBuf {
        self.base_dir.join("logs")
    }

    /// Get the daemon log file path (~/.unbound/logs/daemon.log).
    pub fn daemon_log_file(&self) -> PathBuf {
        self.logs_dir().join("daemon.log")
    }

    /// Ensure all required directories exist.
    pub fn ensure_dirs(&self) -> CoreResult<()> {
        std::fs::create_dir_all(&self.base_dir)?;
        std::fs::create_dir_all(&self.app_support_dir)?;
        std::fs::create_dir_all(self.logs_dir())?;
        Ok(())
    }
}

impl Default for Paths {
    fn default() -> Self {
        Self::new().expect("Failed to determine home directory")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_paths_with_base_dir() {
        let base = PathBuf::from("/tmp/test-unbound");
        let paths = Paths::with_base_dir(base.clone());

        assert_eq!(paths.base_dir(), &base);
        assert_eq!(paths.config_file(), base.join("config.json"));
        assert_eq!(paths.database_file(), base.join("unbound.sqlite"));
        assert_eq!(paths.socket_file(), base.join("daemon.sock"));
        assert_eq!(paths.pid_file(), base.join("daemon.pid"));
        assert_eq!(paths.falco_socket_file(), base.join("falco.sock"));
        assert_eq!(paths.nagato_socket_file(), base.join("nagato.sock"));
        assert_eq!(paths.ably_auth_socket_file(), base.join("ably-auth.sock"));
        assert_eq!(paths.logs_dir(), base.join("logs"));
        assert_eq!(paths.daemon_log_file(), base.join("logs/daemon.log"));
    }

    #[test]
    fn test_paths_default() {
        let paths = Paths::new().unwrap();
        let home = dirs::home_dir().unwrap();

        assert_eq!(paths.base_dir(), &home.join(".unbound"));
    }

    #[test]
    fn test_ensure_dirs_creates_directories() {
        let dir = tempdir().unwrap();
        let base = dir.path().join("unbound");
        let paths = Paths::with_base_dir(base.clone());

        // Directories should not exist yet
        assert!(!base.exists());
        assert!(!paths.logs_dir().exists());

        // Ensure dirs
        paths.ensure_dirs().unwrap();

        // Directories should now exist
        assert!(base.exists());
        assert!(base.is_dir());
        assert!(paths.logs_dir().exists());
        assert!(paths.logs_dir().is_dir());
    }

    #[test]
    fn test_ensure_dirs_idempotent() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        // Call ensure_dirs multiple times
        paths.ensure_dirs().unwrap();
        paths.ensure_dirs().unwrap();
        paths.ensure_dirs().unwrap();

        // Should still work
        assert!(paths.base_dir().exists());
        assert!(paths.logs_dir().exists());
    }

    #[test]
    fn test_paths_all_accessors() {
        let base = PathBuf::from("/test/path");
        let paths = Paths::with_base_dir(base.clone());

        // Test all accessor methods return expected paths
        assert!(paths.base_dir().ends_with("path"));
        assert!(paths.config_file().ends_with("config.json"));
        assert!(paths.database_file().ends_with("unbound.sqlite"));
        assert!(paths.socket_file().ends_with("daemon.sock"));
        assert!(paths.pid_file().ends_with("daemon.pid"));
        assert!(paths.falco_socket_file().ends_with("falco.sock"));
        assert!(paths.nagato_socket_file().ends_with("nagato.sock"));
        assert!(paths.ably_auth_socket_file().ends_with("ably-auth.sock"));
        assert!(paths.logs_dir().ends_with("logs"));
        assert!(paths.daemon_log_file().ends_with("daemon.log"));
    }

    #[test]
    fn test_paths_clone() {
        let base = PathBuf::from("/test/clone");
        let paths = Paths::with_base_dir(base.clone());
        let cloned = paths.clone();

        assert_eq!(paths.base_dir(), cloned.base_dir());
        assert_eq!(paths.config_file(), cloned.config_file());
    }

    #[test]
    fn test_paths_nested_logs_dir() {
        let dir = tempdir().unwrap();
        let paths = Paths::with_base_dir(dir.path().to_path_buf());

        // Daemon log file should be inside logs dir
        let log_file = paths.daemon_log_file();
        let logs_dir = paths.logs_dir();

        assert!(log_file.starts_with(&logs_dir));
    }
}
