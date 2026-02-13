mod common;

use piccolo::{create_worktree, create_worktree_with_options, get_branches, remove_worktree};
use std::path::Path;

#[test]
fn create_worktree_default_branch_name() {
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path = create_worktree(&repo_path, "session-1", None).expect("create_worktree failed");

    assert!(
        wt_path.contains(".unbound/worktrees/session-1"),
        "worktree path should contain .unbound/worktrees/session-1, got: {}",
        wt_path
    );
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
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path = create_worktree(&repo_path, "work", Some("feature/my-thing"))
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
    let (_dir, repo_path) = common::init_test_repo();

    // Pre-create the branch
    {
        let repo = git2::Repository::open(&repo_path).expect("open repo");
        let head = repo.head().expect("head");
        let commit = head.peel_to_commit().expect("peel");
        repo.branch("unbound/test", &commit, false)
            .expect("create branch");
    }

    // create_worktree should reuse the existing branch
    let wt_path = create_worktree(&repo_path, "test", None).expect("create_worktree failed");
    assert!(Path::new(&wt_path).exists());
}

#[test]
fn duplicate_worktree_name_returns_error() {
    let (_dir, repo_path) = common::init_test_repo();

    create_worktree(&repo_path, "dup", None).expect("first create_worktree should succeed");

    let result = create_worktree(&repo_path, "dup", None);
    assert!(result.is_err());
    assert!(
        result.unwrap_err().contains("already exists"),
        "expected 'already exists' error"
    );
}

#[test]
fn worktree_is_valid_git_repo() {
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path =
        create_worktree(&repo_path, "valid-repo-test", None).expect("create_worktree failed");

    let result = git2::Repository::open(&wt_path);
    assert!(result.is_ok(), "worktree should be a valid git repository");
}

#[test]
fn create_worktree_non_repo_returns_error() {
    let result = create_worktree(Path::new("/nonexistent/path"), "test", None);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn create_worktree_invalid_name_returns_error() {
    let (_dir, repo_path) = common::init_test_repo();
    let invalid = ["", "   ", "foo/bar", "foo\\bar", "..", "a..b"];

    for name in invalid {
        let result = create_worktree(&repo_path, name, None);
        let err = result.err().unwrap_or_else(|| "unexpected success".to_string());
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
    let (_dir, repo_path) = common::init_test_repo();

    let worktrees_dir = repo_path.join(".unbound/worktrees");
    assert!(
        !worktrees_dir.exists(),
        ".unbound/worktrees should not exist before creating worktree"
    );

    create_worktree(&repo_path, "auto-dir", None).expect("create_worktree failed");

    assert!(
        worktrees_dir.exists(),
        ".unbound/worktrees should exist after creating worktree"
    );
}

// ============================================================
// remove_worktree tests
// ============================================================

#[test]
fn remove_existing_worktree() {
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path = create_worktree(&repo_path, "to-remove", None).expect("create_worktree failed");
    let wt_path = Path::new(&wt_path);
    assert!(wt_path.exists());

    remove_worktree(&repo_path, wt_path).expect("remove_worktree failed");

    assert!(!wt_path.exists(), "worktree directory should be removed");
}

#[test]
fn remove_worktree_cleans_empty_parent() {
    let (_dir, repo_path) = common::init_test_repo();

    let wt_path_str =
        create_worktree(&repo_path, "only-one", None).expect("create_worktree failed");
    let wt_path = Path::new(&wt_path_str);

    remove_worktree(&repo_path, wt_path).expect("remove_worktree failed");

    let worktrees_dir = repo_path.join(".unbound/worktrees");
    assert!(
        !worktrees_dir.exists(),
        ".unbound/worktrees should be removed when empty"
    );
}

#[test]
fn remove_nonexistent_worktree_succeeds() {
    let (_dir, repo_path) = common::init_test_repo();

    let fake_path = repo_path.join(".unbound/worktrees/nonexistent");

    // Should succeed gracefully (no error for missing directory)
    remove_worktree(&repo_path, &fake_path)
        .expect("remove_worktree should succeed for nonexistent path");
}

#[test]
fn remove_worktree_invalid_path_returns_error() {
    let (_dir, repo_path) = common::init_test_repo();

    // Path with no file_name component
    let result = remove_worktree(&repo_path, Path::new("/"));
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Invalid worktree path"));
}

#[test]
fn remove_worktree_non_repo_returns_error() {
    let result = remove_worktree(
        Path::new("/nonexistent/path"),
        Path::new("/nonexistent/path/.unbound/worktrees/test"),
    );
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn worktree_visible_in_branches_after_creation() {
    let (_dir, repo_path) = common::init_test_repo();

    create_worktree(&repo_path, "branch-check", None).expect("create_worktree failed");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    let branch_names: Vec<&str> = branches.local.iter().map(|b| b.name.as_str()).collect();
    assert!(
        branch_names.contains(&"unbound/branch-check"),
        "expected unbound/branch-check in branches, got: {:?}",
        branch_names
    );
}
