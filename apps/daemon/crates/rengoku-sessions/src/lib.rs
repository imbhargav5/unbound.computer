//! Session lifecycle orchestration for the Unbound daemon.
//!
//! Manages session creation (with optional worktree), deletion (with cleanup),
//! and the session secret cache (memory → SQLite → keychain).

use agent_session_sqlite_persist_core::{
    ArminError, NewSession, NewSessionSecret, Repository, RepositoryId, Session, SessionId,
    SessionReader, SessionWriter,
};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use thiserror::Error;

/// Errors from session orchestration.
#[derive(Error, Debug)]
pub enum SessionError {
    #[error("Repository not found: {0}")]
    RepositoryNotFound(String),
    #[error("Session not found: {0}")]
    SessionNotFound(String),
    #[error("Failed to create worktree: {0}")]
    WorktreeCreation(String),
    #[error("Armin error: {0}")]
    Armin(#[from] ArminError),
    #[error("Encryption error: {0}")]
    Encryption(String),
}

/// Parameters for creating a new session.
#[derive(Debug, Clone)]
pub struct CreateSessionParams {
    pub repository_id: String,
    pub title: String,
    pub is_worktree: bool,
    pub worktree_name: Option<String>,
    pub branch_name: Option<String>,
}

/// Thread-safe session secret cache.
///
/// Provides fast in-memory access to session encryption keys.
/// Falls back to SQLite / keychain when not cached.
#[derive(Clone)]
pub struct SessionSecretCache {
    cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl SessionSecretCache {
    /// Create a new empty cache.
    pub fn new() -> Self {
        Self {
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Create from an existing shared cache.
    pub fn from_shared(cache: Arc<Mutex<HashMap<String, Vec<u8>>>>) -> Self {
        Self { cache }
    }

    /// Insert a session secret into the cache.
    pub fn insert(&self, session_id: &str, key: Vec<u8>) {
        let mut cache = self.cache.lock().unwrap();
        cache.insert(session_id.to_string(), key);
    }

    /// Get a cached session secret.
    pub fn get(&self, session_id: &str) -> Option<Vec<u8>> {
        let cache = self.cache.lock().unwrap();
        cache.get(session_id).cloned()
    }

    /// Remove a session secret from the cache.
    pub fn remove(&self, session_id: &str) -> Option<Vec<u8>> {
        let mut cache = self.cache.lock().unwrap();
        cache.remove(session_id)
    }

    /// Check if a session secret is cached.
    pub fn contains(&self, session_id: &str) -> bool {
        let cache = self.cache.lock().unwrap();
        cache.contains_key(session_id)
    }

    /// Get the number of cached secrets.
    pub fn len(&self) -> usize {
        let cache = self.cache.lock().unwrap();
        cache.len()
    }

    /// Check if the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Clear all cached secrets.
    pub fn clear(&self) {
        let mut cache = self.cache.lock().unwrap();
        cache.clear();
    }

    /// Get the underlying shared cache for interoperability.
    pub fn inner(&self) -> Arc<Mutex<HashMap<String, Vec<u8>>>> {
        self.cache.clone()
    }
}

impl Default for SessionSecretCache {
    fn default() -> Self {
        Self::new()
    }
}

/// Creates a session using Armin, handling the core database operations.
///
/// This is the pure orchestration logic extracted from the session handler.
/// Worktree creation and secret encryption are handled by the caller since
/// they require platform-specific dependencies.
pub fn create_session<A: SessionWriter + SessionReader>(
    armin: &A,
    params: &CreateSessionParams,
    session_id: SessionId,
    worktree_path: Option<String>,
) -> Result<Session, SessionError> {
    // Verify repo exists
    let repo_id = RepositoryId::from_string(&params.repository_id);
    let _repo: Repository = armin
        .get_repository(&repo_id)?
        .ok_or_else(|| SessionError::RepositoryNotFound(params.repository_id.clone()))?;

    let new_session = NewSession {
        id: session_id,
        repository_id: repo_id,
        title: params.title.clone(),
        claude_session_id: None,
        is_worktree: params.is_worktree,
        worktree_path,
    };

    let session = armin.create_session_with_metadata(new_session)?;
    Ok(session)
}

/// Delete a session, returning the session data for worktree cleanup.
///
/// The caller should handle worktree removal after this returns.
pub fn delete_session<A: SessionWriter + SessionReader>(
    armin: &A,
    session_id: &SessionId,
) -> Result<Option<Session>, SessionError> {
    let session = armin.get_session(session_id)?;
    if session.is_none() {
        return Ok(None);
    }
    let session = session.unwrap();

    armin.delete_session(session_id)?;
    Ok(Some(session))
}

/// Store an encrypted session secret via Armin.
pub fn store_session_secret<A: SessionWriter>(
    armin: &A,
    session_id: SessionId,
    encrypted_secret: Vec<u8>,
    nonce: Vec<u8>,
) -> Result<(), SessionError> {
    let secret = NewSessionSecret {
        session_id,
        encrypted_secret,
        nonce,
    };
    armin.set_session_secret(secret)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_session_sqlite_persist_core::{Armin, NewRepository, NullSink, SessionReader, SessionWriter};

    fn make_armin() -> Armin<NullSink> {
        Armin::in_memory(NullSink).unwrap()
    }

    fn setup_repo(armin: &Armin<NullSink>) -> RepositoryId {
        let repo = armin
            .create_repository(NewRepository {
                id: RepositoryId::from_string("repo-1"),
                path: "/test/project".to_string(),
                name: "test-project".to_string(),
                is_git_repository: true,
                sessions_path: None,
                default_branch: None,
                default_remote: None,
            })
            .unwrap();
        repo.id
    }

    // =========================================================================
    // SessionSecretCache tests
    // =========================================================================

    #[test]
    fn cache_starts_empty() {
        let cache = SessionSecretCache::new();
        assert!(cache.is_empty());
        assert_eq!(cache.len(), 0);
    }

    #[test]
    fn cache_insert_and_get() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1, 2, 3]);
        assert_eq!(cache.get("sess-1"), Some(vec![1, 2, 3]));
    }

    #[test]
    fn cache_get_missing_returns_none() {
        let cache = SessionSecretCache::new();
        assert_eq!(cache.get("missing"), None);
    }

    #[test]
    fn cache_contains() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1]);
        assert!(cache.contains("sess-1"));
        assert!(!cache.contains("sess-2"));
    }

    #[test]
    fn cache_remove() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1, 2]);
        let removed = cache.remove("sess-1");
        assert_eq!(removed, Some(vec![1, 2]));
        assert!(!cache.contains("sess-1"));
    }

    #[test]
    fn cache_remove_missing_returns_none() {
        let cache = SessionSecretCache::new();
        assert_eq!(cache.remove("missing"), None);
    }

    #[test]
    fn cache_clear() {
        let cache = SessionSecretCache::new();
        cache.insert("a", vec![1]);
        cache.insert("b", vec![2]);
        cache.insert("c", vec![3]);
        assert_eq!(cache.len(), 3);
        cache.clear();
        assert!(cache.is_empty());
    }

    #[test]
    fn cache_overwrite() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1, 2, 3]);
        cache.insert("sess-1", vec![4, 5, 6]);
        assert_eq!(cache.get("sess-1"), Some(vec![4, 5, 6]));
        assert_eq!(cache.len(), 1);
    }

    #[test]
    fn cache_multiple_sessions() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1]);
        cache.insert("sess-2", vec![2]);
        cache.insert("sess-3", vec![3]);
        assert_eq!(cache.len(), 3);
        assert_eq!(cache.get("sess-1"), Some(vec![1]));
        assert_eq!(cache.get("sess-2"), Some(vec![2]));
        assert_eq!(cache.get("sess-3"), Some(vec![3]));
    }

    #[test]
    fn cache_shared_inner() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![42]);
        let inner = cache.inner();
        let guard = inner.lock().unwrap();
        assert_eq!(guard.get("sess-1"), Some(&vec![42]));
    }

    #[test]
    fn cache_from_shared() {
        let shared = Arc::new(Mutex::new(HashMap::new()));
        shared
            .lock()
            .unwrap()
            .insert("pre-existing".to_string(), vec![99]);

        let cache = SessionSecretCache::from_shared(shared);
        assert_eq!(cache.get("pre-existing"), Some(vec![99]));
    }

    #[test]
    fn cache_default_is_empty() {
        let cache = SessionSecretCache::default();
        assert!(cache.is_empty());
    }

    #[test]
    fn cache_clone_shares_state() {
        let cache = SessionSecretCache::new();
        cache.insert("sess-1", vec![1]);
        let clone = cache.clone();
        clone.insert("sess-2", vec![2]);
        assert_eq!(cache.len(), 2);
        assert!(cache.contains("sess-2"));
    }

    // =========================================================================
    // create_session tests
    // =========================================================================

    #[test]
    fn create_session_basic() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);

        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "My Session".to_string(),
            is_worktree: false,
            worktree_name: None,
            branch_name: None,
        };

        let session = create_session(&armin, &params, SessionId::new(), None).unwrap();
        assert_eq!(session.title, "My Session");
        assert!(!session.is_worktree);
        assert!(session.worktree_path.is_none());
    }

    #[test]
    fn create_session_with_worktree_path() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);

        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "Worktree Session".to_string(),
            is_worktree: true,
            worktree_name: Some("wt-1".to_string()),
            branch_name: None,
        };

        let session = create_session(
            &armin,
            &params,
            SessionId::new(),
            Some("/test/project/.worktrees/wt-1".to_string()),
        )
        .unwrap();
        assert!(session.is_worktree);
        assert_eq!(
            session.worktree_path.as_deref(),
            Some("/test/project/.worktrees/wt-1")
        );
    }

    #[test]
    fn create_session_fails_for_missing_repo() {
        let armin = make_armin();

        let params = CreateSessionParams {
            repository_id: "nonexistent".to_string(),
            title: "Test".to_string(),
            is_worktree: false,
            worktree_name: None,
            branch_name: None,
        };

        let result = create_session(&armin, &params, SessionId::new(), None);
        assert!(matches!(result, Err(SessionError::RepositoryNotFound(_))));
    }

    #[test]
    fn create_session_uses_given_id() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);
        let custom_id = SessionId::from_string("my-custom-id");

        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "Custom ID".to_string(),
            is_worktree: false,
            worktree_name: None,
            branch_name: None,
        };

        let session = create_session(&armin, &params, custom_id.clone(), None).unwrap();
        assert_eq!(session.id, custom_id);
    }

    #[test]
    fn create_multiple_sessions_same_repo() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);

        for i in 0..5 {
            let params = CreateSessionParams {
                repository_id: "repo-1".to_string(),
                title: format!("Session {}", i),
                is_worktree: false,
                worktree_name: None,
                branch_name: None,
            };
            create_session(&armin, &params, SessionId::new(), None).unwrap();
        }

        let sessions = armin
            .list_sessions(&RepositoryId::from_string("repo-1"))
            .unwrap();
        assert_eq!(sessions.len(), 5);
    }

    // =========================================================================
    // delete_session tests
    // =========================================================================

    #[test]
    fn delete_session_returns_session() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);
        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "To Delete".to_string(),
            is_worktree: false,
            worktree_name: None,
            branch_name: None,
        };
        let session = create_session(&armin, &params, SessionId::new(), None).unwrap();

        let deleted = delete_session(&armin, &session.id).unwrap();
        assert!(deleted.is_some());
        assert_eq!(deleted.unwrap().title, "To Delete");
    }

    #[test]
    fn delete_session_missing_returns_none() {
        let armin = make_armin();
        let result = delete_session(&armin, &SessionId::from_string("nonexistent")).unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn delete_session_removes_from_armin() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);
        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "Gone".to_string(),
            is_worktree: false,
            worktree_name: None,
            branch_name: None,
        };
        let session = create_session(&armin, &params, SessionId::new(), None).unwrap();
        delete_session(&armin, &session.id).unwrap();

        let lookup = armin.get_session(&session.id).unwrap();
        assert!(lookup.is_none());
    }

    #[test]
    fn delete_worktree_session_returns_worktree_info() {
        let armin = make_armin();
        let _repo_id = setup_repo(&armin);
        let params = CreateSessionParams {
            repository_id: "repo-1".to_string(),
            title: "WT Delete".to_string(),
            is_worktree: true,
            worktree_name: Some("wt-del".to_string()),
            branch_name: None,
        };
        let session = create_session(
            &armin,
            &params,
            SessionId::new(),
            Some("/test/project/.wt/wt-del".to_string()),
        )
        .unwrap();

        let deleted = delete_session(&armin, &session.id).unwrap().unwrap();
        assert!(deleted.is_worktree);
        assert_eq!(
            deleted.worktree_path.as_deref(),
            Some("/test/project/.wt/wt-del")
        );
    }

    // =========================================================================
    // store_session_secret tests
    // =========================================================================

    #[test]
    fn store_session_secret_succeeds() {
        let armin = make_armin();
        let session_id = armin.create_session().unwrap();

        store_session_secret(&armin, session_id.clone(), vec![1, 2, 3, 4], vec![5, 6, 7]).unwrap();

        let secret = armin.get_session_secret(&session_id).unwrap();
        assert!(secret.is_some());
    }

    // =========================================================================
    // Error display tests
    // =========================================================================

    #[test]
    fn error_messages_are_descriptive() {
        let e = SessionError::RepositoryNotFound("repo-x".to_string());
        assert!(e.to_string().contains("repo-x"));

        let e = SessionError::SessionNotFound("sess-y".to_string());
        assert!(e.to_string().contains("sess-y"));

        let e = SessionError::WorktreeCreation("disk full".to_string());
        assert!(e.to_string().contains("disk full"));

        let e = SessionError::Encryption("bad key".to_string());
        assert!(e.to_string().contains("bad key"));
    }
}
