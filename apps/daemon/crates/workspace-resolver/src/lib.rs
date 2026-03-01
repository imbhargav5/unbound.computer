//! Session-to-working-directory resolution for the Unbound daemon.
//!
//! Provides a single place to resolve the working directory for a session,
//! eliminating the duplicated `session.worktree_path || repo.path` pattern
//! across handlers.

use agent_session_sqlite_persist_core::{ArminError, Repository, RepositoryId, Session, SessionId, SessionReader};
use std::path::Path;
use thiserror::Error;

/// Errors that can occur during workspace resolution.
#[derive(Error, Debug)]
pub enum ResolveError {
    #[error("Session not found: {0}")]
    SessionNotFound(String),
    #[error("Repository not found: {0}")]
    RepositoryNotFound(String),
    #[error(
        "Legacy worktree path is unsupported: {0}. Use '~/.unbound/<repo_id>/worktrees' and recreate the session."
    )]
    LegacyWorktreeUnsupported(String),
    #[error("Armin error: {0}")]
    Armin(#[from] ArminError),
}

/// The result of resolving a working directory for a session.
#[derive(Debug, Clone)]
pub struct ResolvedWorkspace {
    /// The effective working directory path.
    pub working_dir: String,
    /// The session that was resolved.
    pub session: Session,
    /// The repository that the session belongs to.
    pub repository: Repository,
    /// Whether the working dir comes from a worktree.
    pub is_worktree: bool,
}

/// Resolve the working directory for a session.
///
/// This is the core function — looks up the session and its repository,
/// then returns the worktree path if available, otherwise the repository path.
pub fn resolve_working_dir<R: SessionReader>(
    reader: &R,
    session_id: &SessionId,
) -> Result<ResolvedWorkspace, ResolveError> {
    let session = reader
        .get_session(session_id)?
        .ok_or_else(|| ResolveError::SessionNotFound(session_id.as_str().to_string()))?;

    let repository = reader
        .get_repository(&session.repository_id)?
        .ok_or_else(|| {
            ResolveError::RepositoryNotFound(session.repository_id.as_str().to_string())
        })?;

    let (working_dir, is_worktree) = match &session.worktree_path {
        Some(wt_path) => {
            if is_legacy_worktree_path(wt_path) {
                return Err(ResolveError::LegacyWorktreeUnsupported(wt_path.clone()));
            }
            (wt_path.clone(), true)
        }
        None => (repository.path.clone(), false),
    };

    Ok(ResolvedWorkspace {
        working_dir,
        session,
        repository,
        is_worktree,
    })
}

fn is_legacy_worktree_path(path: &str) -> bool {
    Path::new(path)
        .components()
        .any(|c| c.as_os_str().to_string_lossy() == ".unbound-worktrees")
}

/// Resolve the working directory from a session ID string.
///
/// Convenience wrapper that creates a `SessionId` from a string.
pub fn resolve_working_dir_from_str<R: SessionReader>(
    reader: &R,
    session_id: &str,
) -> Result<ResolvedWorkspace, ResolveError> {
    let sid = SessionId::from_string(session_id);
    resolve_working_dir(reader, &sid)
}

/// Resolve just the repository path for a repository ID string.
///
/// Used by handlers that only need the repo path (e.g., git operations).
pub fn resolve_repository_path<R: SessionReader>(
    reader: &R,
    repository_id: &str,
) -> Result<String, ResolveError> {
    let repo_id = RepositoryId::from_string(repository_id);
    let repository = reader
        .get_repository(&repo_id)?
        .ok_or_else(|| ResolveError::RepositoryNotFound(repository_id.to_string()))?;
    Ok(repository.path.clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_session_sqlite_persist_core::delta::DeltaView;
    use agent_session_sqlite_persist_core::live::LiveSubscription;
    use agent_session_sqlite_persist_core::snapshot::SnapshotView;
    use agent_session_sqlite_persist_core::*;

    // =========================================================================
    // Mock SessionReader for testing
    // =========================================================================

    struct MockReader {
        sessions: Vec<Session>,
        repositories: Vec<Repository>,
    }

    impl MockReader {
        fn new() -> Self {
            Self {
                sessions: vec![],
                repositories: vec![],
            }
        }

        fn with_repo(mut self, id: &str, path: &str) -> Self {
            let now = chrono::Utc::now();
            self.repositories.push(Repository {
                id: RepositoryId::from_string(id),
                path: path.to_string(),
                name: id.to_string(),
                is_git_repository: true,
                sessions_path: None,
                default_branch: None,
                default_remote: None,
                last_accessed_at: now,
                added_at: now,
                created_at: now,
                updated_at: now,
            });
            self
        }

        fn with_session(mut self, id: &str, repo_id: &str, worktree_path: Option<&str>) -> Self {
            let now = chrono::Utc::now();
            self.sessions.push(Session {
                id: SessionId::from_string(id),
                repository_id: RepositoryId::from_string(repo_id),
                title: format!("Session {}", id),
                claude_session_id: None,
                status: SessionStatus::Active,
                is_worktree: worktree_path.is_some(),
                worktree_path: worktree_path.map(String::from),
                created_at: now,
                last_accessed_at: now,
                updated_at: now,
            });
            self
        }
    }

    impl SessionReader for MockReader {
        fn list_repositories(&self) -> Result<Vec<Repository>, ArminError> {
            Ok(self.repositories.clone())
        }

        fn get_repository(&self, id: &RepositoryId) -> Result<Option<Repository>, ArminError> {
            Ok(self.repositories.iter().find(|r| r.id == *id).cloned())
        }

        fn get_repository_by_path(&self, path: &str) -> Result<Option<Repository>, ArminError> {
            Ok(self.repositories.iter().find(|r| r.path == path).cloned())
        }

        fn list_sessions(&self, repository_id: &RepositoryId) -> Result<Vec<Session>, ArminError> {
            Ok(self
                .sessions
                .iter()
                .filter(|s| s.repository_id == *repository_id)
                .cloned()
                .collect())
        }

        fn get_session(&self, id: &SessionId) -> Result<Option<Session>, ArminError> {
            Ok(self.sessions.iter().find(|s| s.id == *id).cloned())
        }

        fn get_session_state(
            &self,
            _session: &SessionId,
        ) -> Result<Option<SessionState>, ArminError> {
            Ok(None)
        }

        fn snapshot(&self) -> SnapshotView {
            unimplemented!("not needed for resolution tests")
        }

        fn delta(&self, _session: &SessionId) -> DeltaView {
            unimplemented!("not needed for resolution tests")
        }

        fn subscribe(&self, _session: &SessionId) -> LiveSubscription {
            unimplemented!("not needed for resolution tests")
        }

        fn get_session_secret(
            &self,
            _session: &SessionId,
        ) -> Result<Option<SessionSecret>, ArminError> {
            Ok(None)
        }

        fn has_session_secret(&self, _session: &SessionId) -> Result<bool, ArminError> {
            Ok(false)
        }

        fn get_pending_supabase_messages(
            &self,
            _limit: usize,
        ) -> Result<Vec<PendingSupabaseMessage>, ArminError> {
            Ok(vec![])
        }

        fn get_supabase_sync_state(
            &self,
            _session: &SessionId,
        ) -> Result<Option<SupabaseSyncState>, ArminError> {
            Ok(None)
        }

        fn get_sessions_pending_sync(
            &self,
            _limit_per_session: usize,
        ) -> Result<Vec<SessionPendingSync>, ArminError> {
            Ok(vec![])
        }

        fn get_ably_sync_state(
            &self,
            _session: &SessionId,
        ) -> Result<Option<AblySyncState>, ArminError> {
            Ok(None)
        }

        fn get_sessions_pending_ably_sync(
            &self,
            _limit_per_session: usize,
        ) -> Result<Vec<SessionPendingSync>, ArminError> {
            Ok(vec![])
        }
    }

    // =========================================================================
    // resolve_working_dir tests
    // =========================================================================

    #[test]
    fn resolve_uses_repo_path_when_no_worktree() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/home/user/my-project")
            .with_session("sess-1", "repo-1", None);

        let result = resolve_working_dir_from_str(&reader, "sess-1").unwrap();
        assert_eq!(result.working_dir, "/home/user/my-project");
        assert!(!result.is_worktree);
    }

    #[test]
    fn resolve_uses_worktree_path_when_available() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/home/user/my-project")
            .with_session(
                "sess-1",
                "repo-1",
                Some("/home/user/my-project/.worktrees/sess-1"),
            );

        let result = resolve_working_dir_from_str(&reader, "sess-1").unwrap();
        assert_eq!(
            result.working_dir,
            "/home/user/my-project/.worktrees/sess-1"
        );
        assert!(result.is_worktree);
    }

    #[test]
    fn resolve_returns_session_not_found_for_missing_session() {
        let reader = MockReader::new().with_repo("repo-1", "/home/user/project");

        let result = resolve_working_dir_from_str(&reader, "nonexistent");
        assert!(matches!(result, Err(ResolveError::SessionNotFound(_))));
    }

    #[test]
    fn resolve_returns_repo_not_found_for_missing_repo() {
        // Create a session that points to a non-existent repo
        let mut reader = MockReader::new();
        let now = chrono::Utc::now();
        reader.sessions.push(Session {
            id: SessionId::from_string("sess-1"),
            repository_id: RepositoryId::from_string("missing-repo"),
            title: "orphaned session".to_string(),
            claude_session_id: None,
            status: SessionStatus::Active,
            is_worktree: false,
            worktree_path: None,
            created_at: now,
            last_accessed_at: now,
            updated_at: now,
        });

        let result = resolve_working_dir_from_str(&reader, "sess-1");
        assert!(matches!(result, Err(ResolveError::RepositoryNotFound(_))));
    }

    #[test]
    fn resolve_returns_full_session_and_repo() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/home/user/project")
            .with_session("sess-1", "repo-1", None);

        let result = resolve_working_dir_from_str(&reader, "sess-1").unwrap();
        assert_eq!(result.session.id, SessionId::from_string("sess-1"));
        assert_eq!(result.repository.path, "/home/user/project");
    }

    #[test]
    fn resolve_with_typed_session_id() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/path/to/repo")
            .with_session("sess-typed", "repo-1", None);

        let sid = SessionId::from_string("sess-typed");
        let result = resolve_working_dir(&reader, &sid).unwrap();
        assert_eq!(result.working_dir, "/path/to/repo");
    }

    #[test]
    fn resolve_worktree_takes_precedence_over_repo_path() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/original/path")
            .with_session("sess-1", "repo-1", Some("/worktree/path"));

        let result = resolve_working_dir_from_str(&reader, "sess-1").unwrap();
        // The worktree path should win over the repo path
        assert_eq!(result.working_dir, "/worktree/path");
        assert_ne!(result.working_dir, "/original/path");
    }

    #[test]
    fn resolve_rejects_legacy_worktree_path() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/original/path")
            .with_session(
                "sess-1",
                "repo-1",
                Some("/original/path/.unbound-worktrees/sess-1"),
            );

        let result = resolve_working_dir_from_str(&reader, "sess-1");
        assert!(matches!(
            result,
            Err(ResolveError::LegacyWorktreeUnsupported(_))
        ));
    }

    #[test]
    fn resolve_rejects_legacy_worktree_path_with_nested_component() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/original/path")
            .with_session(
                "sess-1",
                "repo-1",
                Some("/original/path/custom/.unbound-worktrees/nested/sess-1"),
            );

        let result = resolve_working_dir_from_str(&reader, "sess-1");
        assert!(matches!(
            result,
            Err(ResolveError::LegacyWorktreeUnsupported(_))
        ));
    }

    // =========================================================================
    // resolve_repository_path tests
    // =========================================================================

    #[test]
    fn resolve_repo_path_returns_path() {
        let reader = MockReader::new().with_repo("repo-1", "/projects/my-app");

        let path = resolve_repository_path(&reader, "repo-1").unwrap();
        assert_eq!(path, "/projects/my-app");
    }

    #[test]
    fn resolve_repo_path_returns_error_for_missing_repo() {
        let reader = MockReader::new();

        let result = resolve_repository_path(&reader, "nonexistent");
        assert!(matches!(result, Err(ResolveError::RepositoryNotFound(_))));
    }

    #[test]
    fn resolve_repo_path_uses_correct_repo_among_many() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/path/one")
            .with_repo("repo-2", "/path/two")
            .with_repo("repo-3", "/path/three");

        assert_eq!(
            resolve_repository_path(&reader, "repo-2").unwrap(),
            "/path/two"
        );
    }

    // =========================================================================
    // Error display tests
    // =========================================================================

    #[test]
    fn error_session_not_found_message() {
        let e = ResolveError::SessionNotFound("sess-123".to_string());
        assert!(e.to_string().contains("sess-123"));
    }

    #[test]
    fn error_repository_not_found_message() {
        let e = ResolveError::RepositoryNotFound("repo-abc".to_string());
        assert!(e.to_string().contains("repo-abc"));
    }

    #[test]
    fn error_legacy_worktree_message() {
        let e = ResolveError::LegacyWorktreeUnsupported(
            "/tmp/repo/.unbound-worktrees/sess-1".to_string(),
        );
        assert!(e.to_string().contains("Legacy"));
        assert!(e.to_string().contains("~/.unbound/<repo_id>/worktrees"));
    }

    // =========================================================================
    // Multiple sessions per repo
    // =========================================================================

    #[test]
    fn resolve_different_sessions_same_repo_different_worktrees() {
        let reader = MockReader::new()
            .with_repo("repo-1", "/project")
            .with_session("sess-1", "repo-1", Some("/project/.wt/sess-1"))
            .with_session("sess-2", "repo-1", Some("/project/.wt/sess-2"))
            .with_session("sess-3", "repo-1", None);

        let r1 = resolve_working_dir_from_str(&reader, "sess-1").unwrap();
        let r2 = resolve_working_dir_from_str(&reader, "sess-2").unwrap();
        let r3 = resolve_working_dir_from_str(&reader, "sess-3").unwrap();

        assert_eq!(r1.working_dir, "/project/.wt/sess-1");
        assert_eq!(r2.working_dir, "/project/.wt/sess-2");
        assert_eq!(r3.working_dir, "/project");
        assert!(r1.is_worktree);
        assert!(r2.is_worktree);
        assert!(!r3.is_worktree);
    }
}
