mod common;

use piccolo::{create_worktree, create_worktree_with_options, get_branches, remove_worktree};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};
use tempfile::TempDir;

struct RepoIdCleanup {
    repo_root: PathBuf,
}

impl Drop for RepoIdCleanup {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.repo_root);
    }
}

fn home_env_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

struct HomeOverride {
    _lock: std::sync::MutexGuard<'static, ()>,
    old_home: Option<String>,
    _temp_home: TempDir,
}

impl Drop for HomeOverride {
    fn drop(&mut self) {
        if let Some(old_home) = &self.old_home {
            std::env::set_var("HOME", old_home);
        } else {
            std::env::remove_var("HOME");
        }
    }
}

fn with_temp_home() -> HomeOverride {
    let lock = home_env_lock()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let temp_home = tempfile::tempdir().expect("create temp HOME");
    let old_home = std::env::var("HOME").ok();
    std::env::set_var("HOME", temp_home.path());
    HomeOverride {
        _lock: lock,
        old_home,
        _temp_home: temp_home,
    }
}

fn test_repo_id(prefix: &str) -> (String, RepoIdCleanup) {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock should be monotonic")
        .as_nanos();
    let repo_id = format!("{}-{}", prefix, nonce);
    let repo_root = default_repo_root(&repo_id);
    let _ = std::fs::remove_dir_all(&repo_root);
    (repo_id, RepoIdCleanup { repo_root })
}

fn default_repo_root(repo_id: &str) -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME must be set"))
        .join(".unbound")
        .join(repo_id)
}

fn default_worktrees_dir(repo_id: &str) -> PathBuf {
    default_repo_root(repo_id).join("worktrees")
}

#[test]
fn create_worktree_default_branch_name() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-default-branch");

    let wt_path =
        create_worktree(&repo_path, &repo_id, "session-1", None).expect("create_worktree failed");
    let expected_root = default_worktrees_dir(&repo_id);
    let expected_dir = expected_root.join("session-1");
    let wt_path_canon = Path::new(&wt_path)
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(&wt_path));
    let expected_root_canon = expected_root
        .canonicalize()
        .unwrap_or_else(|_| expected_root.clone());
    let expected_dir_canon = expected_dir
        .canonicalize()
        .unwrap_or_else(|_| expected_dir.clone());

    assert!(
        wt_path_canon.starts_with(&expected_root_canon),
        "worktree path should be under ~/.unbound/<repo_id>/worktrees, got: {}",
        wt_path
    );
    assert_eq!(wt_path_canon, expected_dir_canon);
    assert!(
        Path::new(&wt_path).exists(),
        "worktree directory should exist"
    );

    // Branch unbound/session-1 should exist
    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let branch = repo.find_branch("unbound/session-1", git2::BranchType::Local);
    assert!(branch.is_ok(), "branch unbound/session-1 should exist");
}

#[test]
fn create_worktree_custom_branch_name() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-custom-branch");

    let wt_path = create_worktree(&repo_path, &repo_id, "work", Some("feature/my-thing"))
        .expect("create_worktree failed");

    assert!(Path::new(&wt_path).exists());

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let branch = repo.find_branch("feature/my-thing", git2::BranchType::Local);
    assert!(
        branch.is_ok(),
        "custom branch feature/my-thing should exist"
    );
}

#[test]
fn create_worktree_with_options_custom_root_dir() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path = create_worktree_with_options(
        &repo_path,
        "custom-root",
        Path::new(".custom-worktrees"),
        None,
        None,
    )
    .expect("create_worktree_with_options failed");

    assert!(
        wt_path.contains(".custom-worktrees/custom-root"),
        "worktree path should contain .custom-worktrees/custom-root, got: {}",
        wt_path
    );
    assert!(Path::new(&wt_path).exists());
}

#[test]
fn create_worktree_with_options_uses_base_branch_reference() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();

    let base_commit_id = {
        let repo = git2::Repository::open(&repo_path).expect("open repo");
        let head = repo.head().expect("head");
        let head_commit = head.peel_to_commit().expect("peel");
        repo.branch("base-branch", &head_commit, false)
            .expect("create base branch");
        head_commit.id()
    };

    common::create_file(&repo_path, "later-change.txt", "later change\n");
    common::commit_all(&repo_path, "later change");

    let wt_path = create_worktree_with_options(
        &repo_path,
        "from-base",
        Path::new(".unbound/worktrees"),
        Some("base-branch"),
        Some("feature/from-base"),
    )
    .expect("create_worktree_with_options failed");
    assert!(Path::new(&wt_path).exists());

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let feature_tip = repo
        .find_branch("feature/from-base", git2::BranchType::Local)
        .expect("feature branch")
        .into_reference()
        .target()
        .expect("feature branch target");
    assert_eq!(
        feature_tip, base_commit_id,
        "new worktree branch should start from explicit base branch"
    );
}

#[test]
fn create_worktree_reuses_existing_branch() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-reuse-branch");

    // Pre-create the branch
    {
        let repo = git2::Repository::open(&repo_path).expect("open repo");
        let head = repo.head().expect("head");
        let commit = head.peel_to_commit().expect("peel");
        repo.branch("unbound/test", &commit, false)
            .expect("create branch");
    }

    // create_worktree should reuse the existing branch
    let wt_path =
        create_worktree(&repo_path, &repo_id, "test", None).expect("create_worktree failed");
    assert!(Path::new(&wt_path).exists());
}

#[test]
fn duplicate_worktree_name_returns_error() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-duplicate");

    create_worktree(&repo_path, &repo_id, "dup", None)
        .expect("first create_worktree should succeed");

    let result = create_worktree(&repo_path, &repo_id, "dup", None);
    assert!(result.is_err());
    assert!(
        result.unwrap_err().contains("already exists"),
        "expected 'already exists' error"
    );
}

#[test]
fn worktree_is_valid_git_repo() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-valid-repo");

    let wt_path = create_worktree(&repo_path, &repo_id, "valid-repo-test", None)
        .expect("create_worktree failed");

    let result = git2::Repository::open(&wt_path);
    assert!(result.is_ok(), "worktree should be a valid git repository");
}

#[test]
fn create_worktree_non_repo_returns_error() {
    let _home = with_temp_home();
    let result = create_worktree(
        Path::new("/nonexistent/path"),
        "repo-nonexistent",
        "test",
        None,
    );
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn create_worktree_invalid_name_returns_error() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-invalid-name");
    let invalid = ["", "   ", "foo/bar", "foo\\bar", ".", "..", "a..b"];

    for name in invalid {
        let result = create_worktree(&repo_path, &repo_id, name, None);
        let err = result
            .err()
            .unwrap_or_else(|| "unexpected success".to_string());
        assert!(
            err.contains("Invalid worktree name"),
            "expected invalid name error for {:?}, got: {:?}",
            name,
            err
        );
    }
}

#[test]
fn unbound_worktrees_dir_created_automatically() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-auto-dir");

    let worktrees_dir = default_worktrees_dir(&repo_id);
    assert!(
        !worktrees_dir.exists(),
        "default worktrees dir should not exist before creating worktree"
    );

    create_worktree(&repo_path, &repo_id, "auto-dir", None).expect("create_worktree failed");

    assert!(
        worktrees_dir.exists(),
        "default worktrees dir should exist after creating worktree"
    );
}

// ============================================================
// remove_worktree tests
// ============================================================

#[test]
fn remove_existing_worktree() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-remove-existing");

    let wt_path =
        create_worktree(&repo_path, &repo_id, "to-remove", None).expect("create_worktree failed");
    let wt_path = Path::new(&wt_path);
    assert!(wt_path.exists());

    remove_worktree(&repo_path, wt_path).expect("remove_worktree failed");

    assert!(!wt_path.exists(), "worktree directory should be removed");
}

#[test]
fn remove_worktree_cleans_empty_parent() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-remove-parent");

    let wt_path_str =
        create_worktree(&repo_path, &repo_id, "only-one", None).expect("create_worktree failed");
    let wt_path = Path::new(&wt_path_str);

    remove_worktree(&repo_path, wt_path).expect("remove_worktree failed");

    let worktrees_dir = default_worktrees_dir(&repo_id);
    assert!(
        !worktrees_dir.exists(),
        "default worktrees dir should be removed when empty"
    );
}

#[test]
fn remove_nonexistent_worktree_succeeds() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-remove-nonexistent");

    let fake_path = default_worktrees_dir(&repo_id).join("nonexistent");

    // Should succeed gracefully (no error for missing directory)
    remove_worktree(&repo_path, &fake_path)
        .expect("remove_worktree should succeed for nonexistent path");
}

#[test]
fn remove_worktree_invalid_path_returns_error() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();

    // Path with no file_name component
    let result = remove_worktree(&repo_path, Path::new("/"));
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Invalid worktree path"));
}

#[test]
fn remove_worktree_non_repo_returns_error() {
    let _home = with_temp_home();
    let result = remove_worktree(
        Path::new("/nonexistent/path"),
        Path::new("/Users/nonexistent/.unbound/repo-123/worktrees/test"),
    );
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn worktree_visible_in_branches_after_creation() {
    let _home = with_temp_home();
    let (_dir, repo_path) = common::init_test_repo();
    let (repo_id, _cleanup) = test_repo_id("wt-branch-visible");

    create_worktree(&repo_path, &repo_id, "branch-check", None).expect("create_worktree failed");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    let branch_names: Vec<&str> = branches.local.iter().map(|b| b.name.as_str()).collect();
    assert!(
        branch_names.contains(&"unbound/branch-check"),
        "expected unbound/branch-check in branches, got: {:?}",
        branch_names
    );
}
