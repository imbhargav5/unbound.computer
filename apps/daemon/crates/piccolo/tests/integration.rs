mod common;

use piccolo::{
    discard_changes, get_branches, get_file_diff, get_log, get_status, stage_files, unstage_files,
    GitFileStatus,
};
use std::fs;
use std::path::Path;

#[test]
fn full_staging_cycle() {
    let (_dir, repo_path) = common::init_test_repo();

    // 1. Create a new file - should be untracked
    common::create_file(&repo_path, "new_file.txt", "hello world\n");
    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);
    let file = status
        .files
        .iter()
        .find(|f| f.path == "new_file.txt")
        .expect("new_file not found");
    assert_eq!(file.status, GitFileStatus::Untracked);

    // 2. Stage it
    stage_files(&repo_path, &["new_file.txt"]).expect("stage_files failed");
    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "new_file.txt")
        .expect("new_file not found after staging");
    assert_eq!(file.status, GitFileStatus::Added);
    assert!(file.staged);

    // 3. Unstage it
    unstage_files(&repo_path, &["new_file.txt"]).expect("unstage_files failed");
    let status = get_status(&repo_path).expect("get_status failed");
    let file = status
        .files
        .iter()
        .find(|f| f.path == "new_file.txt")
        .expect("new_file not found after unstaging");
    assert_eq!(file.status, GitFileStatus::Untracked);
    assert!(!file.staged);

    // 4. Modify a committed file and get diff
    common::create_file(&repo_path, "README.md", "modified readme\n");
    let diff = get_file_diff(&repo_path, "README.md", None).expect("get_file_diff failed");
    assert!(
        diff.additions > 0 || diff.deletions > 0,
        "expected changes in diff"
    );

    // 5. Discard changes
    discard_changes(&repo_path, &["README.md"]).expect("discard_changes failed");
    let status = get_status(&repo_path).expect("get_status failed");
    let readme_in_status = status.files.iter().find(|f| f.path == "README.md");
    assert!(
        readme_in_status.is_none(),
        "README.md should not appear in status after discard"
    );
}

#[test]
fn worktree_lifecycle() {
    let (_dir, repo_path) = common::init_test_repo();

    // 1. Create worktree
    let wt_path_str =
        piccolo::create_worktree(&repo_path, "repo-lifecycle-test", "lifecycle-test", None)
            .expect("create_worktree failed");
    let wt_path = Path::new(&wt_path_str);
    assert!(wt_path.exists());

    // 2. Create a file in the worktree
    common::create_file(wt_path, "worktree_file.txt", "worktree content\n");

    // 3. Check status in the worktree
    let status = get_status(wt_path).expect("get_status in worktree failed");
    assert!(!status.is_clean);
    let file = status
        .files
        .iter()
        .find(|f| f.path == "worktree_file.txt")
        .expect("worktree_file not found");
    assert_eq!(file.status, GitFileStatus::Untracked);

    // 4. Verify branch is visible from main repo
    let branches = get_branches(&repo_path).expect("get_branches failed");
    let branch_names: Vec<&str> = branches.local.iter().map(|b| b.name.as_str()).collect();
    assert!(branch_names.contains(&"unbound/lifecycle-test"));

    // 5. Remove the worktree
    piccolo::remove_worktree(&repo_path, wt_path).expect("remove_worktree failed");
    assert!(!wt_path.exists());
}

#[test]
fn log_pagination_end_to_end() {
    // Create 14 additional commits + 1 initial = 15 total
    let (_dir, repo_path) = common::init_repo_with_commits(14);

    let mut all_oids = Vec::new();

    // Page 1: commits 0-4
    let page1 = get_log(&repo_path, Some(5), Some(0), None).expect("page 1 failed");
    assert_eq!(page1.commits.len(), 5);
    assert!(page1.has_more);
    for c in &page1.commits {
        all_oids.push(c.oid.clone());
    }

    // Page 2: commits 5-9
    let page2 = get_log(&repo_path, Some(5), Some(5), None).expect("page 2 failed");
    assert_eq!(page2.commits.len(), 5);
    assert!(page2.has_more);
    for c in &page2.commits {
        all_oids.push(c.oid.clone());
    }

    // Page 3: commits 10-14
    let page3 = get_log(&repo_path, Some(5), Some(10), None).expect("page 3 failed");
    assert_eq!(page3.commits.len(), 5);
    assert!(!page3.has_more);
    for c in &page3.commits {
        all_oids.push(c.oid.clone());
    }

    // All 15 commits should be unique
    assert_eq!(all_oids.len(), 15);
    let mut deduped = all_oids.clone();
    deduped.sort();
    deduped.dedup();
    assert_eq!(deduped.len(), 15, "all commit OIDs should be unique");
}

#[test]
fn diff_after_stage_and_unstage() {
    let (_dir, repo_path) = common::init_test_repo();

    // Modify a file
    common::create_file(&repo_path, "README.md", "new content\n");

    // Get unstaged diff
    let diff_before = get_file_diff(&repo_path, "README.md", None).expect("diff failed");
    assert!(diff_before.additions > 0 || diff_before.deletions > 0);

    // Stage, then get diff (should show staged diff)
    stage_files(&repo_path, &["README.md"]).expect("stage failed");
    let diff_staged = get_file_diff(&repo_path, "README.md", None).expect("diff failed");
    assert!(diff_staged.additions > 0 || diff_staged.deletions > 0);

    // Unstage, file should be back to unstaged diff
    unstage_files(&repo_path, &["README.md"]).expect("unstage failed");
    let diff_after = get_file_diff(&repo_path, "README.md", None).expect("diff failed");
    assert!(diff_after.additions > 0 || diff_after.deletions > 0);
}

#[test]
fn status_reflects_subdirectory_files() {
    let (_dir, repo_path) = common::init_test_repo();

    // Create nested files
    common::create_file(&repo_path, "src/main.rs", "fn main() {}\n");
    common::create_file(&repo_path, "src/lib/utils.rs", "pub fn helper() {}\n");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(!status.is_clean);

    let paths: Vec<&str> = status.files.iter().map(|f| f.path.as_str()).collect();
    assert!(
        paths.contains(&"src/main.rs"),
        "expected src/main.rs in status"
    );
    assert!(
        paths.contains(&"src/lib/utils.rs"),
        "expected src/lib/utils.rs in status"
    );
}

#[test]
fn multiple_discard_idempotent() {
    let (_dir, repo_path) = common::init_test_repo();

    common::create_file(&repo_path, "README.md", "modified\n");

    discard_changes(&repo_path, &["README.md"]).expect("first discard failed");
    discard_changes(&repo_path, &["README.md"]).expect("second discard should also succeed");

    let original = fs::read_to_string(repo_path.join("README.md")).expect("read");
    assert_eq!(original, "# Test Repo\n");
}
