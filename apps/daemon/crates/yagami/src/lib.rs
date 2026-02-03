use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct ListOptions {
    pub include_hidden: bool,
    pub skip_dirs: HashSet<String>,
}

impl Default for ListOptions {
    fn default() -> Self {
        Self {
            include_hidden: false,
            skip_dirs: default_skip_dirs(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub has_children: bool,
}

#[derive(thiserror::Error, Debug)]
pub enum YagamiError {
    #[error("root path does not exist or is invalid")]
    InvalidRoot,
    #[error("relative path is invalid")]
    InvalidRelativePath,
    #[error("path escapes root")]
    PathTraversal,
    #[error("target is not a directory")]
    NotADirectory,
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

pub fn list_dir(root: &Path, relative_path: &str, options: ListOptions) -> Result<Vec<FileEntry>, YagamiError> {
    if Path::new(relative_path).is_absolute() {
        return Err(YagamiError::InvalidRelativePath);
    }

    let root_canon = root.canonicalize().map_err(|_| YagamiError::InvalidRoot)?;

    let target_path = if relative_path.is_empty() {
        root_canon.clone()
    } else {
        root_canon.join(relative_path)
    };

    let target_canon = target_path.canonicalize().map_err(|_| YagamiError::InvalidRelativePath)?;

    if !target_canon.starts_with(&root_canon) {
        return Err(YagamiError::PathTraversal);
    }

    let metadata = fs::metadata(&target_canon)?;
    if !metadata.is_dir() {
        return Err(YagamiError::NotADirectory);
    }

    let mut entries: Vec<FileEntry> = Vec::new();
    for entry in fs::read_dir(&target_canon)? {
        let entry = entry?;
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy().to_string();

        if should_skip(&name, &entry, &options) {
            continue;
        }

        let file_type = entry.file_type()?;
        let is_symlink = file_type.is_symlink();
        let is_dir = file_type.is_dir() && !is_symlink;

        let entry_path = entry.path();
        let relative = entry_path
            .strip_prefix(&root_canon)
            .map_err(|_| YagamiError::PathTraversal)?
            .to_path_buf();

        let rel_str = path_to_string(&relative);

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

    entries.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    Ok(entries)
}

fn should_skip(name: &str, entry: &fs::DirEntry, options: &ListOptions) -> bool {
    if !options.include_hidden && name.starts_with('.') {
        return true;
    }

    let file_type = match entry.file_type() {
        Ok(file_type) => file_type,
        Err(_) => return true,
    };

    if file_type.is_dir() {
        let dir_name = name.to_string();
        if options.skip_dirs.contains(&dir_name) {
            return true;
        }
    }

    false
}

fn dir_has_children(dir: &Path, options: &ListOptions) -> bool {
    let read_dir = match fs::read_dir(dir) {
        Ok(read_dir) => read_dir,
        Err(_) => return false,
    };

    for entry in read_dir.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if should_skip(&name, &entry, options) {
            continue;
        }
        return true;
    }

    false
}

fn path_to_string(path: &PathBuf) -> String {
    path.components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

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
        assert!(matches!(err, YagamiError::PathTraversal | YagamiError::InvalidRelativePath));
    }
}
