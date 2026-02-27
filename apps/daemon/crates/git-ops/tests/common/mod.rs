#![allow(dead_code)]

use git2::{Repository, Signature};
use std::fs;
use std::path::{Path, PathBuf};
use tempfile::TempDir;

/// Create a temp repo with an initial commit and return (TempDir, repo_path).
///
/// The repo is initialized with a single committed file `README.md`.
/// The default branch is determined by git's init defaults.
pub fn init_test_repo() -> (TempDir, PathBuf) {
    let dir = TempDir::new().expect("failed to create temp dir");
    let repo_path = dir.path().to_path_buf();

    let repo = Repository::init(&repo_path).expect("failed to init repo");

    // Create an initial file and commit it
    create_file(&repo_path, "README.md", "# Test Repo\n");

    let mut index = repo.index().expect("failed to get index");
    index
        .add_path(Path::new("README.md"))
        .expect("failed to add to index");
    index.write().expect("failed to write index");

    let tree_id = index.write_tree().expect("failed to write tree");
    let tree = repo.find_tree(tree_id).expect("failed to find tree");

    let sig = Signature::now("Test User", "test@example.com").expect("failed to create sig");
    repo.commit(Some("HEAD"), &sig, &sig, "Initial commit", &tree, &[])
        .expect("failed to create initial commit");

    (dir, repo_path)
}

/// Create a file in the repo working tree with the given content.
pub fn create_file(repo_path: &Path, name: &str, content: &str) {
    let file_path = repo_path.join(name);
    if let Some(parent) = file_path.parent() {
        fs::create_dir_all(parent).expect("failed to create parent dirs");
    }
    fs::write(&file_path, content).expect("failed to write file");
}

/// Stage all changes and create a commit with the given message.
pub fn commit_all(repo_path: &Path, message: &str) {
    let repo = Repository::open(repo_path).expect("failed to open repo");
    let mut index = repo.index().expect("failed to get index");
    index
        .add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
        .expect("failed to add all");
    index.write().expect("failed to write index");

    let tree_id = index.write_tree().expect("failed to write tree");
    let tree = repo.find_tree(tree_id).expect("failed to find tree");

    let sig = Signature::now("Test User", "test@example.com").expect("failed to create sig");

    let head = repo.head().expect("failed to get head");
    let parent = head.peel_to_commit().expect("failed to peel to commit");

    repo.commit(Some("HEAD"), &sig, &sig, message, &tree, &[&parent])
        .expect("failed to commit");
}

/// Create a repo with N sequential commits (plus the initial commit).
/// Returns (TempDir, repo_path) with N+1 total commits.
pub fn init_repo_with_commits(n: usize) -> (TempDir, PathBuf) {
    let (dir, repo_path) = init_test_repo();
    for i in 0..n {
        create_file(
            &repo_path,
            &format!("file_{}.txt", i),
            &format!("content {}\n", i),
        );
        commit_all(&repo_path, &format!("Commit {}", i + 1));
    }
    (dir, repo_path)
}

/// Stage specific paths in the repo index.
pub fn stage_path(repo_path: &Path, path: &str) {
    let repo = Repository::open(repo_path).expect("failed to open repo");
    let mut index = repo.index().expect("failed to get index");
    index
        .add_path(Path::new(path))
        .expect("failed to add to index");
    index.write().expect("failed to write index");
}
