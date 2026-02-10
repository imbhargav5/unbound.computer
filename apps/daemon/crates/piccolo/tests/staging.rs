mod common;

use piccolo::{get_status, stage_files, unstage_files, GitFileStatus};
use std::fs;
use std::path::Path;

// ============================================================
// stage_files tests
// ============================================================

#[test]
fn stage_new_file() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "new.txt", "hello\n");

    stage_files(&repo_path, &["new.txt"]).expect("stage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "new.txt")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Added);
    assert!(file.staged);
}

#[test]
fn stage_modified_file() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "README.md", "modified\n");

    stage_files(&repo_path, &["README.md"]).expect("stage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Modified);
    assert!(file.staged);
}

#[test]
fn stage_deleted_file() {
    let (_dir, repo_path) = common::init_test_repo();
    fs::remove_file(repo_path.join("README.md")).expect("delete file");

    stage_files(&repo_path, &["README.md"]).expect("stage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Deleted);
    assert!(file.staged);
}

#[test]
fn stage_multiple_files() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "a.txt", "a\n");
    common::create_file(&repo_path, "b.txt", "b\n");
    common::create_file(&repo_path, "c.txt", "c\n");

    stage_files(&repo_path, &["a.txt", "b.txt", "c.txt"]).expect("stage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    for name in &["a.txt", "b.txt", "c.txt"] {
        let file = status
            .files
            .iter()
            .find(|f| f.path == *name)
            .unwrap_or_else(|| panic!("{} not found in status", name));
        assert!(file.staged, "{} should be staged", name);
    }
}

#[test]
fn stage_empty_paths_is_noop() {
    let (_dir, repo_path) = common::init_test_repo();
    stage_files(&repo_path, &[]).expect("stage_files with empty paths should succeed");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(status.is_clean);
}

#[test]
fn stage_non_repo_returns_error() {
    let result = stage_files(Path::new("/nonexistent/path"), &["file.txt"]);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn stage_deleted_path_removes_from_index() {
    let (_dir, repo_path) = common::init_test_repo();

    // Add a file, commit it, then delete it
    common::create_file(&repo_path, "to_remove.txt", "will be deleted\n");
    common::commit_all(&repo_path, "Add file to remove");
    fs::remove_file(repo_path.join("to_remove.txt")).expect("delete file");

    // Stage the deletion
    stage_files(&repo_path, &["to_remove.txt"]).expect("stage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "to_remove.txt")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Deleted);
    assert!(file.staged);
}

// ============================================================
// unstage_files tests
// ============================================================

#[test]
fn unstage_staged_new_file() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "new.txt", "hello\n");
    stage_files(&repo_path, &["new.txt"]).expect("stage_files failed");

    unstage_files(&repo_path, &["new.txt"]).expect("unstage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "new.txt")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Untracked);
    assert!(!file.staged);
}

#[test]
fn unstage_staged_modification() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "README.md", "modified\n");
    stage_files(&repo_path, &["README.md"]).expect("stage_files failed");

    unstage_files(&repo_path, &["README.md"]).expect("unstage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "README.md")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Modified);
    assert!(!file.staged);
}

#[test]
fn unstage_on_initial_commit_no_head() {
    // Create a repo with NO commits, only staged files
    let dir = tempfile::TempDir::new().expect("create temp dir");
    let repo_path = dir.path();
    let repo = git2::Repository::init(repo_path).expect("init repo");

    // Create and stage a file without committing
    common::create_file(repo_path, "initial.txt", "content\n");
    let mut index = repo.index().expect("get index");
    index
        .add_path(Path::new("initial.txt"))
        .expect("add to index");
    index.write().expect("write index");

    // Unstage should work even without HEAD
    unstage_files(repo_path, &["initial.txt"]).expect("unstage_files failed");

    let status = get_status(repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "initial.txt")
        .expect("file not found");
    assert_eq!(file.status, GitFileStatus::Untracked);
    assert!(!file.staged);
}

#[test]
fn unstage_subset_of_staged_files() {
    let (_dir, repo_path) = common::init_test_repo();
    common::create_file(&repo_path, "a.txt", "a\n");
    common::create_file(&repo_path, "b.txt", "b\n");
    common::create_file(&repo_path, "c.txt", "c\n");
    stage_files(&repo_path, &["a.txt", "b.txt", "c.txt"]).expect("stage_files failed");

    // Unstage only b.txt
    unstage_files(&repo_path, &["b.txt"]).expect("unstage_files failed");

    let status = get_status(&repo_path).expect("get_status failed");

    let a = status
        .files
        .iter()
        .find(|f| f.path == "a.txt")
        .expect("a.txt not found");
    assert!(a.staged, "a.txt should still be staged");

    let b = status
        .files
        .iter()
        .find(|f| f.path == "b.txt")
        .expect("b.txt not found");
    assert!(!b.staged, "b.txt should be unstaged");

    let c = status
        .files
        .iter()
        .find(|f| f.path == "c.txt")
        .expect("c.txt not found");
    assert!(c.staged, "c.txt should still be staged");
}

#[test]
fn unstage_non_repo_returns_error() {
    let result = unstage_files(Path::new("/nonexistent/path"), &["file.txt"]);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}
