//! Yagami: Safe directory listing utility for file tree exploration.
//!
//! Provides secure directory enumeration with path traversal protection
//! and configurable filtering for hidden files and heavy directories.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

/// Configuration options for directory listing behavior.
///
/// Controls visibility of hidden files and specifies directories
/// to skip during enumeration (e.g., node_modules, .git).
#[derive(Debug, Clone)]
pub struct ListOptions {
    /// Whether to include files and directories starting with a dot.
    pub include_hidden: bool,
    /// Set of directory names to skip during listing (exact match).
    pub skip_dirs: HashSet<String>,
}

impl Default for ListOptions {
    /// Creates default options that hide dotfiles and skip common heavy directories.
    ///
    /// Excludes node_modules, .git, build artifacts, and other directories
    /// that typically contain many files irrelevant to code navigation.
    fn default() -> Self {
        Self {
            include_hidden: false,
            skip_dirs: default_skip_dirs(),
        }
    }
}

/// Represents a single file or directory entry in a listing.
///
/// Contains essential metadata for building file tree UIs without
/// requiring additional filesystem calls for basic display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    /// The file or directory name (without path components).
    pub name: String,
    /// The relative path from the listing root (using forward slashes).
    pub path: String,
    /// True if this entry is a directory (symlinks to directories are false).
    pub is_dir: bool,
    /// True if this directory contains visible children (for expand indicators).
    pub has_children: bool,
}

/// Error types for directory listing operations.
///
/// Covers security violations (path traversal), invalid inputs,
/// and underlying filesystem errors.
#[derive(thiserror::Error, Debug)]
pub enum YagamiError {
    /// The root path does not exist or cannot be canonicalized.
    #[error("root path does not exist or is invalid")]
    InvalidRoot,
    /// The relative path is malformed or cannot be resolved.
    #[error("relative path is invalid")]
    InvalidRelativePath,
    /// The resolved path would escape the root directory (security violation).
    #[error("path escapes root")]
    PathTraversal,
    /// The target path exists but is not a directory.
    #[error("target is not a directory")]
    NotADirectory,
    /// An underlying filesystem I/O error occurred.
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

/// Lists the contents of a directory with security checks and filtering.
///
/// Performs path traversal protection by canonicalizing paths and verifying
/// the target remains within the root. Returns entries sorted with directories
/// first, then alphabetically by name (case-insensitive).
///
/// # Arguments
/// * `root` - The root directory that bounds the listing (must exist)
/// * `relative_path` - Path relative to root to list (empty string for root itself)
/// * `options` - Filtering options for hidden files and skipped directories
///
/// # Errors
/// Returns an error if the path is invalid, escapes root, or is not a directory.
pub fn list_dir(
    root: &Path,
    relative_path: &str,
    options: ListOptions,
) -> Result<Vec<FileEntry>, YagamiError> {
    // Reject absolute paths in the relative path argument to prevent confusion
    if Path::new(relative_path).is_absolute() {
        return Err(YagamiError::InvalidRelativePath);
    }

    // Canonicalize root to resolve symlinks and get an absolute path
    let root_canon = root.canonicalize().map_err(|_| YagamiError::InvalidRoot)?;

    // Build the target path by joining root with the relative path
    let target_path = if relative_path.is_empty() {
        root_canon.clone()
    } else {
        root_canon.join(relative_path)
    };

    // Canonicalize to resolve any .. or symlinks in the target path
    let target_canon = target_path
        .canonicalize()
        .map_err(|_| YagamiError::InvalidRelativePath)?;

    // Security check: ensure the resolved path is still within root
    if !target_canon.starts_with(&root_canon) {
        return Err(YagamiError::PathTraversal);
    }

    // Verify the target is actually a directory
    let metadata = fs::metadata(&target_canon)?;
    if !metadata.is_dir() {
        return Err(YagamiError::NotADirectory);
    }

    // Enumerate directory contents with filtering
    let mut entries: Vec<FileEntry> = Vec::new();
    for entry in fs::read_dir(&target_canon)? {
        let entry = entry?;
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy().to_string();

        // Apply skip rules for hidden files and configured directories
        if should_skip(&name, &entry, &options) {
            continue;
        }

        // Determine if this is a real directory (not a symlink)
        let file_type = entry.file_type()?;
        let is_symlink = file_type.is_symlink();
        let is_dir = file_type.is_dir() && !is_symlink;

        // Compute the relative path from root for this entry
        let entry_path = entry.path();
        let relative = entry_path
            .strip_prefix(&root_canon)
            .map_err(|_| YagamiError::PathTraversal)?
            .to_path_buf();

        let rel_str = path_to_string(&relative);

        // Check if directory has visible children (for UI expand indicators)
        let has_children = if is_dir {
            dir_has_children(&entry_path, &options)
        } else {
            false
        };

        entries.push(FileEntry {
            name,
            path: rel_str,
            is_dir,
            has_children,
        });
    }

    // Sort: directories first, then alphabetically by name (case-insensitive)
    entries.sort_by(|a, b| match (a.is_dir, b.is_dir) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
    });

    Ok(entries)
}

/// Determines whether a directory entry should be excluded from the listing.
///
/// Checks if the entry is a hidden file (starts with dot) when hidden files
/// are not included, and if the entry is a directory in the skip list.
/// Returns true to skip on file type read errors as a safety measure.
fn should_skip(name: &str, entry: &fs::DirEntry, options: &ListOptions) -> bool {
    // Skip hidden files unless explicitly included
    if !options.include_hidden && name.starts_with('.') {
        return true;
    }

    // Skip if we can't read the file type (permission denied, etc.)
    let file_type = match entry.file_type() {
        Ok(file_type) => file_type,
        Err(_) => return true,
    };

    // Check skip list for directories only
    if file_type.is_dir() {
        let dir_name = name.to_string();
        if options.skip_dirs.contains(&dir_name) {
            return true;
        }
    }

    false
}

/// Checks if a directory contains any visible children based on filter options.
///
/// Performs a quick scan of the directory, returning true as soon as a
/// non-skipped entry is found. Returns false if the directory cannot be
/// read or contains only skipped entries. Used to populate the has_children
/// field for UI expand/collapse indicators.
fn dir_has_children(dir: &Path, options: &ListOptions) -> bool {
    // Return false if we can't read the directory (permissions, etc.)
    let read_dir = match fs::read_dir(dir) {
        Ok(read_dir) => read_dir,
        Err(_) => return false,
    };

    // Early exit on first visible child for performance
    for entry in read_dir.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if should_skip(&name, &entry, options) {
            continue;
        }
        return true;
    }

    false
}

/// Converts a PathBuf to a string using forward slashes as separators.
///
/// Ensures consistent path representation across platforms by always
/// using forward slashes, making paths suitable for display and API responses.
fn path_to_string(path: &PathBuf) -> String {
    path.components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

/// Returns the default set of directory names to skip during listing.
///
/// Includes common heavy directories that typically contain many files
/// irrelevant to code navigation: package managers (node_modules, vendor, Pods),
/// build outputs (dist, build, target, DerivedData, .next), and VCS (.git).
fn default_skip_dirs() -> HashSet<String> {
    let dirs = [
        "node_modules",
        ".git",
        ".unbound-worktrees",
        "dist",
        "build",
        ".next",
        "target",
        "DerivedData",
        "Pods",
        "vendor",
    ];

    dirs.iter().map(|s| s.to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{create_dir_all, File};
    use std::io::Write;

    #[test]
    fn list_dir_skips_hidden_and_heavy_dirs() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();

        create_dir_all(root.join("node_modules")).unwrap();
        create_dir_all(root.join("src")).unwrap();
        File::create(root.join("src/main.rs")).unwrap();
        File::create(root.join(".hidden")).unwrap();

        let entries = list_dir(root, "", ListOptions::default()).unwrap();
        let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();

        assert!(names.contains(&"src".to_string()));
        assert!(!names.contains(&"node_modules".to_string()));
        assert!(!names.contains(&".hidden".to_string()));
    }

    #[test]
    fn list_dir_rejects_traversal() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        let err = list_dir(root, "../", ListOptions::default()).unwrap_err();
        assert!(matches!(
            err,
            YagamiError::PathTraversal | YagamiError::InvalidRelativePath
        ));
    }
}
