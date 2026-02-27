mod common;

use git_ops::get_log;
use std::path::Path;

#[test]
fn returns_correct_commit_count() {
    // init_repo_with_commits(4) creates 4 additional commits + 1 initial = 5 total
    let (_dir, repo_path) = common::init_repo_with_commits(4);

    let log = get_log(&repo_path, Some(10), None, None).expect("get_log failed");
    assert_eq!(log.commits.len(), 5, "expected 5 commits (1 initial + 4)");
    assert!(!log.has_more);
}

#[test]
fn limit_works() {
    let (_dir, repo_path) = common::init_repo_with_commits(4);

    let log = get_log(&repo_path, Some(3), None, None).expect("get_log failed");
    assert_eq!(log.commits.len(), 3);
    assert!(log.has_more);
}

#[test]
fn offset_works() {
    let (_dir, repo_path) = common::init_repo_with_commits(4);

    let log = get_log(&repo_path, Some(2), Some(2), None).expect("get_log failed");
    assert_eq!(log.commits.len(), 2);
}

#[test]
fn offset_and_limit_at_boundary() {
    let (_dir, repo_path) = common::init_repo_with_commits(4);

    let log = get_log(&repo_path, Some(10), Some(4), None).expect("get_log failed");
    assert_eq!(log.commits.len(), 1, "expected 1 commit at offset 4 of 5");
    assert!(!log.has_more);
}

#[test]
fn offset_beyond_total_returns_empty() {
    let (_dir, repo_path) = common::init_repo_with_commits(2);

    let log = get_log(&repo_path, Some(10), Some(100), None).expect("get_log failed");
    assert!(log.commits.is_empty());
    assert!(!log.has_more);
}

#[test]
fn log_with_specific_branch() {
    let (_dir, repo_path) = common::init_test_repo();

    // Create a feature branch and add a commit to it
    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("head");
    let head_commit = head.peel_to_commit().expect("peel to commit");
    repo.branch("feature", &head_commit, false)
        .expect("create branch");

    // Checkout the feature branch
    let obj = repo
        .revparse_single("refs/heads/feature")
        .expect("revparse");
    repo.checkout_tree(&obj, None).expect("checkout tree");
    repo.set_head("refs/heads/feature").expect("set head");

    common::create_file(&repo_path, "feature_file.txt", "feature work\n");
    common::commit_all(&repo_path, "Feature commit");

    // Now query log for the feature branch
    let log = get_log(&repo_path, None, None, Some("feature")).expect("get_log failed");
    assert!(!log.commits.is_empty());
    assert_eq!(
        log.commits[0].summary, "Feature commit",
        "expected most recent commit on feature branch"
    );
}

#[test]
fn log_with_nonexistent_branch_returns_error() {
    let (_dir, repo_path) = common::init_test_repo();

    let result = get_log(&repo_path, None, None, Some("nonexistent"));
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to find branch"));
}

#[test]
fn empty_repo_returns_error() {
    let dir = tempfile::TempDir::new().expect("create temp dir");
    let repo_path = dir.path();
    git2::Repository::init(repo_path).expect("init repo");

    let result = get_log(repo_path, None, None, None);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to get HEAD"));
}

#[test]
fn commit_metadata_is_populated() {
    let (_dir, repo_path) = common::init_test_repo();

    let log = get_log(&repo_path, Some(1), None, None).expect("get_log failed");
    assert_eq!(log.commits.len(), 1);

    let commit = &log.commits[0];
    assert_eq!(commit.oid.len(), 40, "oid should be 40 hex chars");
    assert_eq!(commit.short_oid.len(), 7, "short_oid should be 7 chars");
    assert_eq!(commit.summary, "Initial commit");
    assert!(!commit.message.is_empty());
    assert_eq!(commit.author_name, "Test User");
    assert_eq!(commit.author_email, "test@example.com");
    assert!(commit.author_time > 0);
    assert_eq!(commit.committer_name, "Test User");
    assert!(commit.committer_time > 0);
    // Initial commit has no parents
    assert!(
        commit.parent_oids.is_empty(),
        "initial commit should have no parents"
    );
}

#[test]
fn subsequent_commit_has_one_parent() {
    let (_dir, repo_path) = common::init_repo_with_commits(1);

    let log = get_log(&repo_path, Some(1), None, None).expect("get_log failed");
    let commit = &log.commits[0];
    assert_eq!(
        commit.parent_oids.len(),
        1,
        "non-initial commit should have one parent"
    );
}

#[test]
fn default_limit_is_50() {
    let (_dir, repo_path) = common::init_repo_with_commits(59);

    // 60 total commits (59 + 1 initial), default limit is 50
    let log = get_log(&repo_path, None, None, None).expect("get_log failed");
    assert_eq!(log.commits.len(), 50);
    assert!(log.has_more);
}

#[test]
fn total_count_is_none() {
    let (_dir, repo_path) = common::init_test_repo();

    let log = get_log(&repo_path, None, None, None).expect("get_log failed");
    assert!(log.total_count.is_none());
}

#[test]
fn non_repo_path_returns_error() {
    let result = get_log(Path::new("/nonexistent/path"), None, None, None);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn commits_are_in_reverse_chronological_order() {
    let (_dir, repo_path) = common::init_repo_with_commits(3);

    let log = get_log(&repo_path, None, None, None).expect("get_log failed");
    assert_eq!(log.commits.len(), 4); // 3 + 1 initial

    // Most recent commit should be first
    assert_eq!(log.commits[0].summary, "Commit 3");
    assert_eq!(log.commits[1].summary, "Commit 2");
    assert_eq!(log.commits[2].summary, "Commit 1");
    assert_eq!(log.commits[3].summary, "Initial commit");
}
