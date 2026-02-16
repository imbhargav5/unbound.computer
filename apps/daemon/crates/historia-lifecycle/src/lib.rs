//! Daemon lifecycle management for the Unbound daemon.
//!
//! Handles singleton enforcement, PID file management, and graceful shutdown.

use std::path::{Path, PathBuf};
use thiserror::Error;

/// Errors from lifecycle management.
#[derive(Error, Debug)]
pub enum LifecycleError {
    #[error("Daemon is already running")]
    AlreadyRunning,
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Stale socket file detected and cleaned up")]
    StaleSocketCleaned,
    #[error("PID file error: {0}")]
    PidFile(String),
}

/// Result of checking whether the daemon is already running.
#[derive(Debug, PartialEq, Eq)]
pub enum SingletonCheck {
    /// No daemon running, safe to start.
    Available,
    /// A stale socket was found and cleaned up.
    StaleSocketCleaned,
    /// Another daemon is already running.
    AlreadyRunning,
}

/// Check if the daemon is already running by testing the socket file.
///
/// Returns `Available` if no socket exists, `StaleSocketCleaned` if a stale
/// socket was found and removed, or `AlreadyRunning` if a daemon responded.
pub fn check_singleton(socket_path: &Path) -> SingletonCheck {
    if !socket_path.exists() {
        return SingletonCheck::Available;
    }

    // Socket exists — try to connect to see if a daemon is actually running.
    // We use a sync connect attempt here to avoid requiring a tokio runtime.
    match std::os::unix::net::UnixStream::connect(socket_path) {
        Ok(_stream) => {
            // Something is listening — daemon is running
            SingletonCheck::AlreadyRunning
        }
        Err(_) => {
            // Socket exists but nothing is listening — stale
            let _ = std::fs::remove_file(socket_path);
            SingletonCheck::StaleSocketCleaned
        }
    }
}

/// Write the current process PID to the given path.
pub fn write_pid_file(pid_path: &Path) -> Result<u32, LifecycleError> {
    let pid = std::process::id();
    std::fs::write(pid_path, pid.to_string())?;
    Ok(pid)
}

/// Read a PID from the given file.
pub fn read_pid_file(pid_path: &Path) -> Result<Option<u32>, LifecycleError> {
    if !pid_path.exists() {
        return Ok(None);
    }
    let content = std::fs::read_to_string(pid_path)?;
    let pid = content
        .trim()
        .parse::<u32>()
        .map_err(|e| LifecycleError::PidFile(format!("Invalid PID: {}", e)))?;
    Ok(Some(pid))
}

/// Clean up PID file if it exists.
pub fn cleanup_pid_file(pid_path: &Path) -> Result<(), LifecycleError> {
    if pid_path.exists() {
        std::fs::remove_file(pid_path)?;
    }
    Ok(())
}

/// Clean up socket file if it exists.
pub fn cleanup_socket_file(socket_path: &Path) -> Result<(), LifecycleError> {
    if socket_path.exists() {
        std::fs::remove_file(socket_path)?;
    }
    Ok(())
}

/// Ensure a directory and its parents exist.
pub fn ensure_dir(path: &Path) -> Result<(), LifecycleError> {
    std::fs::create_dir_all(path)?;
    Ok(())
}

/// Information about a running daemon.
#[derive(Debug, Clone)]
pub struct DaemonInfo {
    pub pid: Option<u32>,
    pub socket_path: PathBuf,
    pub pid_path: PathBuf,
}

impl DaemonInfo {
    /// Create a new DaemonInfo.
    pub fn new(socket_path: PathBuf, pid_path: PathBuf) -> Self {
        Self {
            pid: None,
            socket_path,
            pid_path,
        }
    }

    /// Load PID from the PID file.
    pub fn load_pid(&mut self) -> Result<(), LifecycleError> {
        self.pid = read_pid_file(&self.pid_path)?;
        Ok(())
    }

    /// Check if the daemon appears to be running.
    pub fn is_running(&self) -> bool {
        check_singleton(&self.socket_path) == SingletonCheck::AlreadyRunning
    }

    /// Clean up all daemon files (socket + PID).
    pub fn cleanup(&self) -> Result<(), LifecycleError> {
        cleanup_socket_file(&self.socket_path)?;
        cleanup_pid_file(&self.pid_path)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::ErrorKind;
    use std::os::unix::net::UnixListener;
    use tempfile::TempDir;

    fn tmp() -> TempDir {
        tempfile::tempdir().unwrap()
    }

    fn bind_listener_or_skip(socket_path: &Path) -> Option<UnixListener> {
        match UnixListener::bind(socket_path) {
            Ok(listener) => Some(listener),
            Err(err) if err.kind() == ErrorKind::PermissionDenied => None,
            Err(err) => panic!("failed to bind unix listener at {:?}: {}", socket_path, err),
        }
    }

    // =========================================================================
    // SingletonCheck tests
    // =========================================================================

    #[test]
    fn singleton_available_when_no_socket() {
        let dir = tmp();
        let socket = dir.path().join("daemon.sock");
        assert_eq!(check_singleton(&socket), SingletonCheck::Available);
    }

    #[test]
    fn singleton_stale_when_socket_file_exists_but_no_listener() {
        let dir = tmp();
        let socket = dir.path().join("daemon.sock");
        // Create a regular file (not a socket)
        std::fs::write(&socket, "stale").unwrap();
        let result = check_singleton(&socket);
        // It should clean up the stale file
        assert_eq!(result, SingletonCheck::StaleSocketCleaned);
        assert!(!socket.exists());
    }

    #[test]
    fn singleton_already_running_when_listener_active() {
        let dir = tmp();
        let socket = dir.path().join("daemon.sock");
        // Bind a real Unix socket
        let Some(_listener) = bind_listener_or_skip(&socket) else {
            return;
        };
        assert_eq!(check_singleton(&socket), SingletonCheck::AlreadyRunning);
    }

    #[test]
    fn singleton_stale_socket_removed_after_listener_dropped() {
        let dir = tmp();
        let socket = dir.path().join("daemon.sock");
        {
            let Some(_listener) = bind_listener_or_skip(&socket) else {
                return;
            };
            assert_eq!(check_singleton(&socket), SingletonCheck::AlreadyRunning);
        }
        // Listener dropped — socket file still exists but nothing listening
        assert_eq!(check_singleton(&socket), SingletonCheck::StaleSocketCleaned);
    }

    // =========================================================================
    // PID file tests
    // =========================================================================

    #[test]
    fn write_pid_file_creates_file() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        let pid = write_pid_file(&pid_path).unwrap();
        assert!(pid > 0);
        assert!(pid_path.exists());

        let contents = std::fs::read_to_string(&pid_path).unwrap();
        assert_eq!(contents, pid.to_string());
    }

    #[test]
    fn read_pid_file_returns_pid() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&pid_path, "12345").unwrap();

        let pid = read_pid_file(&pid_path).unwrap();
        assert_eq!(pid, Some(12345));
    }

    #[test]
    fn read_pid_file_missing_returns_none() {
        let dir = tmp();
        let pid_path = dir.path().join("nonexistent.pid");
        let pid = read_pid_file(&pid_path).unwrap();
        assert_eq!(pid, None);
    }

    #[test]
    fn read_pid_file_invalid_content_returns_error() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&pid_path, "not-a-number").unwrap();

        let result = read_pid_file(&pid_path);
        assert!(matches!(result, Err(LifecycleError::PidFile(_))));
    }

    #[test]
    fn read_pid_file_with_whitespace() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&pid_path, "  42  \n").unwrap();

        let pid = read_pid_file(&pid_path).unwrap();
        assert_eq!(pid, Some(42));
    }

    #[test]
    fn write_then_read_roundtrip() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        let written = write_pid_file(&pid_path).unwrap();
        let read = read_pid_file(&pid_path).unwrap();
        assert_eq!(read, Some(written));
    }

    // =========================================================================
    // Cleanup tests
    // =========================================================================

    #[test]
    fn cleanup_pid_file_removes_it() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&pid_path, "123").unwrap();
        assert!(pid_path.exists());

        cleanup_pid_file(&pid_path).unwrap();
        assert!(!pid_path.exists());
    }

    #[test]
    fn cleanup_pid_file_noop_when_missing() {
        let dir = tmp();
        let pid_path = dir.path().join("missing.pid");
        cleanup_pid_file(&pid_path).unwrap(); // should not error
    }

    #[test]
    fn cleanup_socket_file_removes_it() {
        let dir = tmp();
        let socket_path = dir.path().join("daemon.sock");
        std::fs::write(&socket_path, "stub").unwrap();
        assert!(socket_path.exists());

        cleanup_socket_file(&socket_path).unwrap();
        assert!(!socket_path.exists());
    }

    #[test]
    fn cleanup_socket_file_noop_when_missing() {
        let dir = tmp();
        let socket_path = dir.path().join("missing.sock");
        cleanup_socket_file(&socket_path).unwrap(); // should not error
    }

    // =========================================================================
    // ensure_dir tests
    // =========================================================================

    #[test]
    fn ensure_dir_creates_directory() {
        let dir = tmp();
        let new_dir = dir.path().join("sub1").join("sub2").join("sub3");
        assert!(!new_dir.exists());
        ensure_dir(&new_dir).unwrap();
        assert!(new_dir.exists());
        assert!(new_dir.is_dir());
    }

    #[test]
    fn ensure_dir_noop_when_exists() {
        let dir = tmp();
        ensure_dir(dir.path()).unwrap(); // already exists
        assert!(dir.path().exists());
    }

    // =========================================================================
    // DaemonInfo tests
    // =========================================================================

    #[test]
    fn daemon_info_new() {
        let info = DaemonInfo::new(
            PathBuf::from("/tmp/test.sock"),
            PathBuf::from("/tmp/test.pid"),
        );
        assert!(info.pid.is_none());
        assert_eq!(info.socket_path, PathBuf::from("/tmp/test.sock"));
        assert_eq!(info.pid_path, PathBuf::from("/tmp/test.pid"));
    }

    #[test]
    fn daemon_info_load_pid() {
        let dir = tmp();
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&pid_path, "9876").unwrap();

        let mut info = DaemonInfo::new(dir.path().join("daemon.sock"), pid_path);
        info.load_pid().unwrap();
        assert_eq!(info.pid, Some(9876));
    }

    #[test]
    fn daemon_info_load_pid_missing() {
        let dir = tmp();
        let mut info = DaemonInfo::new(
            dir.path().join("daemon.sock"),
            dir.path().join("missing.pid"),
        );
        info.load_pid().unwrap();
        assert_eq!(info.pid, None);
    }

    #[test]
    fn daemon_info_is_running_no_socket() {
        let dir = tmp();
        let info = DaemonInfo::new(
            dir.path().join("daemon.sock"),
            dir.path().join("daemon.pid"),
        );
        assert!(!info.is_running());
    }

    #[test]
    fn daemon_info_is_running_with_listener() {
        let dir = tmp();
        let socket_path = dir.path().join("daemon.sock");
        let Some(_listener) = bind_listener_or_skip(&socket_path) else {
            return;
        };

        let info = DaemonInfo::new(socket_path, dir.path().join("daemon.pid"));
        assert!(info.is_running());
    }

    #[test]
    fn daemon_info_cleanup() {
        let dir = tmp();
        let socket_path = dir.path().join("daemon.sock");
        let pid_path = dir.path().join("daemon.pid");
        std::fs::write(&socket_path, "stub").unwrap();
        std::fs::write(&pid_path, "123").unwrap();

        let info = DaemonInfo::new(socket_path.clone(), pid_path.clone());
        info.cleanup().unwrap();

        assert!(!socket_path.exists());
        assert!(!pid_path.exists());
    }

    #[test]
    fn daemon_info_cleanup_when_nothing_exists() {
        let dir = tmp();
        let info = DaemonInfo::new(
            dir.path().join("phantom.sock"),
            dir.path().join("phantom.pid"),
        );
        info.cleanup().unwrap(); // should not error
    }

    // =========================================================================
    // Error display tests
    // =========================================================================

    #[test]
    fn error_already_running_display() {
        let e = LifecycleError::AlreadyRunning;
        assert_eq!(e.to_string(), "Daemon is already running");
    }

    #[test]
    fn error_pid_file_display() {
        let e = LifecycleError::PidFile("bad content".to_string());
        assert!(e.to_string().contains("bad content"));
    }

    #[test]
    fn error_stale_socket_display() {
        let e = LifecycleError::StaleSocketCleaned;
        assert!(e.to_string().contains("Stale socket"));
    }
}
