mod common;

use piccolo::get_branches;
use std::path::Path;

#[test]
fn single_branch_repo() {
    let (_dir, repo_path) = common::init_test_repo();

    let branches = get_branches(&repo_path).expect("get_branches failed");
    assert_eq!(branches.local.len(), 1);
    assert!(branches.local[0].is_current);
    assert!(!branches.local[0].is_remote);
    assert!(branches.current.is_some());
    assert_eq!(branches.current.as_deref(), Some(branches.local[0].name.as_str()));
}

#[test]
fn multiple_local_branches() {
    let (_dir, repo_path) = common::init_test_repo();

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("head");
    let commit = head.peel_to_commit().expect("peel");
    repo.branch("feature-a", &commit, false).expect("create branch a");
    repo.branch("feature-b", &commit, false).expect("create branch b");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    assert_eq!(branches.local.len(), 3);
}

#[test]
fn current_branch_is_first() {
    let (_dir, repo_path) = common::init_test_repo();

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("head");
    let commit = head.peel_to_commit().expect("peel");
    repo.branch("aaa-first-alphabetically", &commit, false)
        .expect("create branch");
    repo.branch("zzz-last-alphabetically", &commit, false)
        .expect("create branch");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    // Current branch should be first regardless of alphabetical order
    assert!(branches.local[0].is_current);
}

#[test]
fn non_current_branches_sorted_alphabetically() {
    let (_dir, repo_path) = common::init_test_repo();

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("head");
    let commit = head.peel_to_commit().expect("peel");
    repo.branch("zebra", &commit, false).expect("create branch");
    repo.branch("alpha", &commit, false).expect("create branch");
    repo.branch("middle", &commit, false).expect("create branch");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    // First is current, rest are alphabetical
    let non_current: Vec<&str> = branches
        .local
        .iter()
        .filter(|b| !b.is_current)
        .map(|b| b.name.as_str())
        .collect();

    let mut sorted = non_current.clone();
    sorted.sort();
    assert_eq!(non_current, sorted, "non-current branches should be alphabetically sorted");
}

#[test]
fn detached_head_returns_current_none() {
    let (_dir, repo_path) = common::init_test_repo();

    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("head");
    let oid = head.target().expect("target");
    repo.set_head_detached(oid).expect("detach head");

    let branches = get_branches(&repo_path).expect("get_branches failed");
    assert!(branches.current.is_none(), "expected None for detached HEAD");
}

#[test]
fn branch_without_upstream_has_zero_ahead_behind() {
    let (_dir, repo_path) = common::init_test_repo();

    let branches = get_branches(&repo_path).expect("get_branches failed");
    let branch = &branches.local[0];
    assert!(branch.upstream.is_none());
    assert_eq!(branch.ahead, 0);
    assert_eq!(branch.behind, 0);
}

#[test]
fn head_oid_is_populated() {
    let (_dir, repo_path) = common::init_test_repo();

    let branches = get_branches(&repo_path).expect("get_branches failed");
    let branch = &branches.local[0];
    assert_eq!(branch.head_oid.len(), 40, "head_oid should be 40 hex chars");
    assert!(
        branch.head_oid.chars().all(|c| c.is_ascii_hexdigit()),
        "head_oid should be hex"
    );
}

#[test]
fn non_repo_path_returns_error() {
    let result = get_branches(Path::new("/nonexistent/path"));
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn remote_branches_from_clone() {
    let (_dir, repo_path) = common::init_test_repo();

    // Create a bare remote from the test repo
    let remote_dir = tempfile::TempDir::new().expect("create temp dir");
    let bare_path = remote_dir.path().join("remote.git");
    git2::Repository::clone(
        repo_path.to_str().expect("path to str"),
        &bare_path,
    )
    .expect("clone repo");

    let branches = get_branches(&bare_path).expect("get_branches failed");
    // A clone should have remote-tracking branches
    assert!(
        !branches.remote.is_empty(),
        "expected remote branches in clone"
    );
    for branch in &branches.remote {
        assert!(branch.is_remote);
    }
}
