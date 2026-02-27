mod common;

use git_ops::{get_status, GitFileStatus};
use std::fs;
use std::path::Path;

#[test]
fn clean_repo_returns_is_clean() {
    let (_dir, repo_path) = common::init_test_repo();

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(status.is_clean, "expected clean repo");
    assert!(status.files.is_empty(), "expected no files");
    assert!(status.branch.is_some(), "expected a branch name");
}

#[test]
fn untracked_file_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "new_file.txt", "hello\n");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);
    assert_eq!(status.files.len(), 1);
    assert_eq!(status.files[0].path, "new_file.txt");
    assert_eq!(status.files[0].status, GitFileStatus::Untracked);
    assert!(!status.files[0].staged);
}

#[test]
fn staged_new_file_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "new_file.txt", "hello\n");
    common::stage_path(&repo_path, "new_file.txt");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let file = status
        .files
        .iter()
        .find(|f| f.path == "new_file.txt")
        .expect("file not found in status");
    assert_eq!(file.status, GitFileStatus::Added);
    assert!(file.staged);
}

#[test]
fn unstaged_modification_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    // Modify the committed file
    common::create_file(&repo_path, "README.md", "modified content\n");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found in status");
    assert_eq!(file.status, GitFileStatus::Modified);
    assert!(!file.staged);
}

#[test]
fn staged_modification_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "README.md", "modified content\n");
    common::stage_path(&repo_path, "README.md");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found in status");
    assert_eq!(file.status, GitFileStatus::Modified);
    assert!(file.staged);
}

#[test]
fn deleted_file_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    fs::remove_file(repo_path.join("README.md")).expect("failed to delete");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found in status");
    assert_eq!(file.status, GitFileStatus::Deleted);
    assert!(!file.staged);
}

#[test]
fn staged_deletion_detected() {
    let (_dir, repo_path) = common::init_test_repo();
    fs::remove_file(repo_path.join("README.md")).expect("failed to delete");

    // Stage the deletion via git2
    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let mut index = repo.index().expect("get index");
    index
        .remove_path(Path::new("README.md"))
        .expect("remove from index");
    index.write().expect("write index");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found in status");
    assert_eq!(file.status, GitFileStatus::Deleted);
    assert!(file.staged);
}

#[test]
fn detached_head_returns_head_as_branch() {
    let (_dir, repo_path) = common::init_test_repo();

    // Detach HEAD by checking out the commit directly
    let repo = git2::Repository::open(&repo_path).expect("open repo");
    let head = repo.head().expect("get head");
    let oid = head.target().expect("head target");
    repo.set_head_detached(oid).expect("detach head");

    let status = get_status(&repo_path).expect("get_status failed");
    // NOTE: In detached HEAD state, git2's head().shorthand() returns "HEAD"
    // rather than None. The current implementation doesn't distinguish between
    // a branch named "HEAD" and detached HEAD state. The `get_branches` function
    // handles this correctly by checking `head.is_branch()`.
    assert_eq!(
        status.branch.as_deref(),
        Some("HEAD"),
        "detached HEAD should report 'HEAD' as branch name"
    );
}

#[test]
fn non_existent_path_returns_error() {
    let result = get_status(Path::new("/nonexistent/path/to/repo"));
    assert!(result.is_err());
    assert!(
        result.unwrap_err().contains("Failed to open repository"),
        "expected error about opening repository"
    );
}

#[test]
fn multiple_files_with_mixed_states() {
    let (_dir, repo_path) = common::init_test_repo();

    // One untracked file
    common::create_file(&repo_path, "untracked.txt", "untracked\n");
    // One staged modification
    common::create_file(&repo_path, "README.md", "modified\n");
    common::stage_path(&repo_path, "README.md");
    // One unstaged new file that we stage then un-modify working tree
    common::create_file(&repo_path, "new_staged.txt", "staged content\n");
    common::stage_path(&repo_path, "new_staged.txt");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);
    assert!(
        status.files.len() >= 3,
        "expected at least 3 files, got {}",
        status.files.len()
    );

    let untracked = status
        .files
        .iter()
        .find(|f| f.path == "untracked.txt")
        .expect("untracked not found");
    assert_eq!(untracked.status, GitFileStatus::Untracked);
    assert!(!untracked.staged);

    let modified = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("README not found");
    assert_eq!(modified.status, GitFileStatus::Modified);
    assert!(modified.staged);

    let new_staged = status
        .files
        .iter()
        .find(|f| f.path == "new_staged.txt")
        .expect("new_staged not found");
    assert_eq!(new_staged.status, GitFileStatus::Added);
    assert!(new_staged.staged);
}
