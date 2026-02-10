mod common;

use piccolo::{discard_changes, get_status};
use std::fs;
use std::path::Path;

#[test]
fn discard_restores_original_content() {
    let (_dir, repo_path) = common::init_test_repo();

    let original = fs::read_to_string(repo_path.join("README.md")).expect("read original");

    // Modify the file
    common::create_file(&repo_path, "README.md", "modified content\n");
    let modified = fs::read_to_string(repo_path.join("README.md")).expect("read modified");
    assert_ne!(original, modified);

    // Discard changes
    discard_changes(&repo_path, &["README.md"]).expect("discard_changes failed");

    let restored = fs::read_to_string(repo_path.join("README.md")).expect("read restored");
    assert_eq!(
        original, restored,
        "file should be restored to original content"
    );
}

#[test]
fn discard_specific_file_leaves_others() {
    let (_dir, repo_path) = common::init_test_repo();

    // Add another file
    common::create_file(&repo_path, "other.txt", "other content\n");
    common::commit_all(&repo_path, "Add other file");

    // Modify both files
    common::create_file(&repo_path, "README.md", "readme modified\n");
    common::create_file(&repo_path, "other.txt", "other modified\n");

    // Discard only README.md
    discard_changes(&repo_path, &["README.md"]).expect("discard_changes failed");

    let status = get_status(&repo_path).expect("get_status failed");

    // README.md should be clean (no longer in status)
    let readme = status.files.iter().find(|f| f.path == "README.md");
    assert!(
        readme.is_none(),
        "README.md should not appear in status after discard"
    );

    // other.txt should still be modified
    let other = status.files.iter().find(|f| f.path == "other.txt");
    assert!(other.is_some(), "other.txt should still be modified");
}

#[test]
fn discard_non_repo_returns_error() {
    let result = discard_changes(Path::new("/nonexistent/path"), &["file.txt"]);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Failed to open repository"));
}

#[test]
fn discard_on_clean_file_is_noop() {
    let (_dir, repo_path) = common::init_test_repo();

    // Discard on unmodified file should succeed without error
    discard_changes(&repo_path, &["README.md"])
        .expect("discard_changes on clean file should succeed");

    let status = get_status(&repo_path).expect("get_status failed");
    assert!(status.is_clean);
}
