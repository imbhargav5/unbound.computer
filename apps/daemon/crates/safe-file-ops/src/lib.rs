//! SafeFileOps: secure rope-backed text file reading and writing.

use lru::LruCache;
use ropey::Rope;
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::{self, Write};
use std::num::NonZeroUsize;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::UNIX_EPOCH;

pub const DEFAULT_CACHE_MAX_BYTES: usize = 128 * 1024 * 1024;
pub const DEFAULT_EDITABLE_MAX_BYTES: u64 = 4 * 1024 * 1024;

#[derive(thiserror::Error, Debug)]
pub enum SafeFileOpsError {
    #[error("root path does not exist or is invalid")]
    InvalidRoot,
    #[error("relative path is invalid")]
    InvalidRelativePath,
    #[error("path escapes root")]
    PathTraversal,
    #[error("target is not a file")]
    NotAFile,
    #[error("file not found")]
    NotFound,
    #[error("file is not valid UTF-8")]
    InvalidUtf8,
    #[error("expected revision is required unless force=true")]
    MissingExpectedRevision,
    #[error("revision conflict")]
    RevisionConflict { current_revision: FileRevision },
    #[error("invalid line range")]
    InvalidRange,
    #[error("io error: {0}")]
    Io(#[from] io::Error),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FileRevision {
    pub token: String,
    pub len_bytes: u64,
    pub modified_unix_ns: u128,
}

#[derive(Debug, Clone)]
pub struct ReadFullResult {
    pub content: String,
    pub is_truncated: bool,
    pub revision: FileRevision,
    pub total_lines: u64,
    pub read_only_reason: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ReadSliceResult {
    pub content: String,
    pub start_line: u64,
    pub end_line_exclusive: u64,
    pub total_lines: u64,
    pub has_more_before: bool,
    pub has_more_after: bool,
    pub is_truncated: bool,
    pub revision: FileRevision,
}

#[derive(Debug, Clone)]
pub struct WriteResult {
    pub revision: FileRevision,
    pub bytes_written: u64,
    pub total_lines: u64,
}

#[derive(Clone)]
pub struct SafeFileOps {
    cache: Arc<Mutex<RopeCache>>,
    editable_max_bytes: u64,
}

impl SafeFileOps {
    pub fn with_defaults() -> Self {
        Self::new(DEFAULT_CACHE_MAX_BYTES, DEFAULT_EDITABLE_MAX_BYTES)
    }

    pub fn new(cache_max_bytes: usize, editable_max_bytes: u64) -> Self {
        Self {
            cache: Arc::new(Mutex::new(RopeCache::new(cache_max_bytes))),
            editable_max_bytes,
        }
    }

    pub fn read_full(
        &self,
        root: &Path,
        relative_path: &str,
        max_bytes: usize,
    ) -> Result<ReadFullResult, SafeFileOpsError> {
        let path = resolve_existing_file_path(root, relative_path)?;
        let (rope, revision) = self.load_or_get_rope(&path)?;
        let raw_content = rope.to_string();
        let (content, is_truncated) = truncate_utf8_to_max_bytes(&raw_content, max_bytes);

        let read_only_reason = if revision.len_bytes > self.editable_max_bytes {
            Some(format!(
                "file is larger than editable limit ({} bytes)",
                self.editable_max_bytes
            ))
        } else {
            None
        };

        Ok(ReadFullResult {
            content,
            is_truncated,
            revision,
            total_lines: rope.len_lines() as u64,
            read_only_reason,
        })
    }

    pub fn read_slice(
        &self,
        root: &Path,
        relative_path: &str,
        start_line: usize,
        line_count: usize,
        max_bytes: usize,
    ) -> Result<ReadSliceResult, SafeFileOpsError> {
        let path = resolve_existing_file_path(root, relative_path)?;
        let (rope, revision) = self.load_or_get_rope(&path)?;

        let total_lines = rope.len_lines();
        let bounded_start = start_line.min(total_lines);
        let bounded_end = if line_count == 0 {
            bounded_start
        } else {
            bounded_start.saturating_add(line_count).min(total_lines)
        };

        let start_char = rope.line_to_char(bounded_start);
        let end_char = rope.line_to_char(bounded_end);
        let raw_content = rope.slice(start_char..end_char).to_string();
        let (content, is_truncated) = truncate_utf8_to_max_bytes(&raw_content, max_bytes);

        Ok(ReadSliceResult {
            content,
            start_line: bounded_start as u64,
            end_line_exclusive: bounded_end as u64,
            total_lines: total_lines as u64,
            has_more_before: bounded_start > 0,
            has_more_after: bounded_end < total_lines,
            is_truncated,
            revision,
        })
    }

    pub fn write_full(
        &self,
        root: &Path,
        relative_path: &str,
        content: &str,
        expected_revision: Option<&FileRevision>,
        force: bool,
    ) -> Result<WriteResult, SafeFileOpsError> {
        let path = resolve_writable_file_path(root, relative_path)?;
        let current = self.current_revision_for_write(&path)?;
        self.validate_expected_revision(&current, expected_revision, force)?;

        atomic_write_text(&path, content)?;
        let metadata = fs::metadata(&path).map_err(map_io_not_found)?;
        let revision = revision_from_metadata(&path, &metadata);
        let rope = Arc::new(Rope::from_str(content));

        self.insert_cache(
            path_to_key(&path),
            rope.clone(),
            revision.clone(),
            content.len(),
        );

        Ok(WriteResult {
            revision,
            bytes_written: content.len() as u64,
            total_lines: rope.len_lines() as u64,
        })
    }

    pub fn replace_range(
        &self,
        root: &Path,
        relative_path: &str,
        start_line: usize,
        end_line_exclusive: usize,
        replacement: &str,
        expected_revision: Option<&FileRevision>,
        force: bool,
    ) -> Result<WriteResult, SafeFileOpsError> {
        let path = resolve_existing_file_path(root, relative_path)?;
        let (current_rope, current_revision) = self.load_or_get_rope(&path)?;
        self.validate_expected_revision(&current_revision, expected_revision, force)?;

        let total_lines = current_rope.len_lines();
        if start_line > end_line_exclusive || end_line_exclusive > total_lines {
            return Err(SafeFileOpsError::InvalidRange);
        }

        let mut next_rope = (*current_rope).clone();
        let start_char = next_rope.line_to_char(start_line);
        let end_char = next_rope.line_to_char(end_line_exclusive);
        next_rope.remove(start_char..end_char);
        next_rope.insert(start_char, replacement);

        let next_content = next_rope.to_string();
        atomic_write_text(&path, &next_content)?;

        let metadata = fs::metadata(&path).map_err(map_io_not_found)?;
        let revision = revision_from_metadata(&path, &metadata);
        let next_rope = Arc::new(next_rope);

        self.insert_cache(
            path_to_key(&path),
            next_rope.clone(),
            revision.clone(),
            next_content.len(),
        );

        Ok(WriteResult {
            revision,
            bytes_written: next_content.len() as u64,
            total_lines: next_rope.len_lines() as u64,
        })
    }

    pub fn editable_max_bytes(&self) -> u64 {
        self.editable_max_bytes
    }

    #[cfg(test)]
    fn cache_entry_count(&self) -> usize {
        self.cache
            .lock()
            .expect("cache lock poisoned")
            .entries
            .len()
    }

    fn current_revision_for_write(&self, path: &Path) -> Result<FileRevision, SafeFileOpsError> {
        if path.exists() {
            let (_, revision) = self.load_or_get_rope(path)?;
            Ok(revision)
        } else {
            Ok(missing_revision(path))
        }
    }

    fn validate_expected_revision(
        &self,
        current: &FileRevision,
        expected: Option<&FileRevision>,
        force: bool,
    ) -> Result<(), SafeFileOpsError> {
        if force {
            return Ok(());
        }

        let expected = expected.ok_or(SafeFileOpsError::MissingExpectedRevision)?;
        if revisions_match(expected, current) {
            Ok(())
        } else {
            Err(SafeFileOpsError::RevisionConflict {
                current_revision: current.clone(),
            })
        }
    }

    fn load_or_get_rope(&self, path: &Path) -> Result<(Arc<Rope>, FileRevision), SafeFileOpsError> {
        let metadata = fs::metadata(path).map_err(map_io_not_found)?;
        if metadata.is_dir() {
            return Err(SafeFileOpsError::NotAFile);
        }

        let revision = revision_from_metadata(path, &metadata);
        let key = path_to_key(path);

        {
            let mut cache = self.cache.lock().expect("cache lock poisoned");
            if let Some((rope, cached_revision)) = cache.get_valid(&key, &revision) {
                return Ok((rope, cached_revision));
            }
        }

        let content = fs::read_to_string(path).map_err(map_utf8_or_io)?;
        let rope = Arc::new(Rope::from_str(&content));

        self.insert_cache(key, rope.clone(), revision.clone(), content.len());

        Ok((rope, revision))
    }

    fn insert_cache(&self, key: String, rope: Arc<Rope>, revision: FileRevision, bytes: usize) {
        let mut cache = self.cache.lock().expect("cache lock poisoned");
        cache.insert(
            key,
            CacheEntry {
                rope,
                revision,
                bytes,
            },
        );
    }
}

struct RopeCache {
    entries: LruCache<String, CacheEntry>,
    total_bytes: usize,
    max_bytes: usize,
}

struct CacheEntry {
    rope: Arc<Rope>,
    revision: FileRevision,
    bytes: usize,
}

impl RopeCache {
    fn new(max_bytes: usize) -> Self {
        let capacity = NonZeroUsize::new(1024).expect("capacity must be non-zero");
        Self {
            entries: LruCache::new(capacity),
            total_bytes: 0,
            max_bytes,
        }
    }

    fn get_valid(
        &mut self,
        key: &str,
        revision: &FileRevision,
    ) -> Option<(Arc<Rope>, FileRevision)> {
        let is_match = self
            .entries
            .peek(key)
            .map(|entry| revisions_match(&entry.revision, revision))
            .unwrap_or(false);

        if !is_match {
            self.remove(key);
            return None;
        }

        self.entries
            .get(key)
            .map(|entry| (entry.rope.clone(), entry.revision.clone()))
    }

    fn insert(&mut self, key: String, entry: CacheEntry) {
        if let Some(existing) = self.entries.pop(&key) {
            self.total_bytes = self.total_bytes.saturating_sub(existing.bytes);
        }

        self.total_bytes = self.total_bytes.saturating_add(entry.bytes);
        self.entries.put(key, entry);

        while self.total_bytes > self.max_bytes {
            if let Some((_key, evicted)) = self.entries.pop_lru() {
                self.total_bytes = self.total_bytes.saturating_sub(evicted.bytes);
            } else {
                break;
            }
        }
    }

    fn remove(&mut self, key: &str) {
        if let Some(existing) = self.entries.pop(key) {
            self.total_bytes = self.total_bytes.saturating_sub(existing.bytes);
        }
    }
}

fn resolve_existing_file_path(root: &Path, relative_path: &str) -> Result<PathBuf, SafeFileOpsError> {
    validate_relative_path(relative_path)?;

    let root_canon = root.canonicalize().map_err(|_| SafeFileOpsError::InvalidRoot)?;
    let target = root_canon.join(relative_path);
    let target_canon = target.canonicalize().map_err(map_io_not_found)?;

    if !target_canon.starts_with(&root_canon) {
        return Err(SafeFileOpsError::PathTraversal);
    }

    let metadata = fs::metadata(&target_canon).map_err(map_io_not_found)?;
    if metadata.is_dir() {
        return Err(SafeFileOpsError::NotAFile);
    }

    Ok(target_canon)
}

fn resolve_writable_file_path(root: &Path, relative_path: &str) -> Result<PathBuf, SafeFileOpsError> {
    validate_relative_path(relative_path)?;

    let root_canon = root.canonicalize().map_err(|_| SafeFileOpsError::InvalidRoot)?;
    let target = root_canon.join(relative_path);

    if target.exists() {
        let target_canon = target.canonicalize().map_err(map_io_not_found)?;
        if !target_canon.starts_with(&root_canon) {
            return Err(SafeFileOpsError::PathTraversal);
        }

        let metadata = fs::metadata(&target_canon).map_err(map_io_not_found)?;
        if metadata.is_dir() {
            return Err(SafeFileOpsError::NotAFile);
        }

        return Ok(target_canon);
    }

    let parent = target.parent().ok_or(SafeFileOpsError::InvalidRelativePath)?;
    let parent_canon = parent.canonicalize().map_err(map_io_not_found)?;
    if !parent_canon.starts_with(&root_canon) {
        return Err(SafeFileOpsError::PathTraversal);
    }

    Ok(target)
}

fn validate_relative_path(relative_path: &str) -> Result<(), SafeFileOpsError> {
    if relative_path.is_empty() {
        return Err(SafeFileOpsError::InvalidRelativePath);
    }

    let path = Path::new(relative_path);
    if path.is_absolute() {
        return Err(SafeFileOpsError::InvalidRelativePath);
    }

    if path
        .components()
        .any(|component| matches!(component, Component::ParentDir))
    {
        return Err(SafeFileOpsError::PathTraversal);
    }

    Ok(())
}

fn map_utf8_or_io(err: io::Error) -> SafeFileOpsError {
    if err.kind() == io::ErrorKind::InvalidData {
        SafeFileOpsError::InvalidUtf8
    } else {
        map_io_not_found(err)
    }
}

fn map_io_not_found(err: io::Error) -> SafeFileOpsError {
    if err.kind() == io::ErrorKind::NotFound {
        SafeFileOpsError::NotFound
    } else {
        SafeFileOpsError::Io(err)
    }
}

fn atomic_write_text(path: &Path, content: &str) -> Result<(), SafeFileOpsError> {
    let dir = path.parent().ok_or(SafeFileOpsError::InvalidRelativePath)?;
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or(SafeFileOpsError::InvalidRelativePath)?;

    let tmp_name = format!(
        ".{}.unbound.tmp.{}",
        file_name,
        std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let tmp_path = dir.join(tmp_name);

    #[cfg(unix)]
    let existing_mode = if path.exists() {
        use std::os::unix::fs::PermissionsExt;
        Some(
            fs::metadata(path)
                .map_err(map_io_not_found)?
                .permissions()
                .mode(),
        )
    } else {
        None
    };

    let write_result = (|| -> Result<(), io::Error> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp_path)?;
        file.write_all(content.as_bytes())?;
        file.sync_all()?;

        #[cfg(unix)]
        if let Some(mode) = existing_mode {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&tmp_path, fs::Permissions::from_mode(mode))?;
        }

        fs::rename(&tmp_path, path)?;

        if let Ok(parent_dir) = fs::File::open(dir) {
            let _ = parent_dir.sync_all();
        }

        Ok(())
    })();

    if let Err(err) = write_result {
        let _ = fs::remove_file(&tmp_path);
        return Err(map_io_not_found(err));
    }

    Ok(())
}

fn path_to_key(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

fn revision_from_metadata(path: &Path, metadata: &fs::Metadata) -> FileRevision {
    let len_bytes = metadata.len();
    let modified_unix_ns = metadata
        .modified()
        .ok()
        .and_then(|ts| ts.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);

    let mut hasher = DefaultHasher::new();
    path.hash(&mut hasher);
    len_bytes.hash(&mut hasher);
    modified_unix_ns.hash(&mut hasher);
    let token = format!("{:016x}", hasher.finish());

    FileRevision {
        token,
        len_bytes,
        modified_unix_ns,
    }
}

fn missing_revision(path: &Path) -> FileRevision {
    let mut hasher = DefaultHasher::new();
    path.hash(&mut hasher);
    0u64.hash(&mut hasher);
    0u128.hash(&mut hasher);

    FileRevision {
        token: format!("missing-{:016x}", hasher.finish()),
        len_bytes: 0,
        modified_unix_ns: 0,
    }
}

fn revisions_match(a: &FileRevision, b: &FileRevision) -> bool {
    a.token == b.token && a.len_bytes == b.len_bytes && a.modified_unix_ns == b.modified_unix_ns
}

fn truncate_utf8_to_max_bytes(content: &str, max_bytes: usize) -> (String, bool) {
    if content.len() <= max_bytes {
        return (content.to_string(), false);
    }

    if max_bytes == 0 {
        return (String::new(), true);
    }

    let mut end = max_bytes.min(content.len());
    while end > 0 && !content.is_char_boundary(end) {
        end -= 1;
    }

    (content[..end].to_string(), true)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_file(path: &Path, content: &str) {
        let mut file = fs::File::create(path).expect("create file");
        file.write_all(content.as_bytes()).expect("write file");
    }

    #[test]
    fn rejects_traversal() {
        let temp = tempfile::tempdir().expect("tempdir");
        let safe_file_ops = SafeFileOps::with_defaults();

        let err = safe_file_ops
            .read_full(temp.path(), "../outside.txt", 100)
            .expect_err("traversal should fail");
        assert!(matches!(err, SafeFileOpsError::PathTraversal));
    }

    #[test]
    fn rejects_absolute_relative_path() {
        let temp = tempfile::tempdir().expect("tempdir");
        let safe_file_ops = SafeFileOps::with_defaults();

        let err = safe_file_ops
            .read_full(temp.path(), "/tmp/absolute.txt", 100)
            .expect_err("absolute path should fail");
        assert!(matches!(err, SafeFileOpsError::InvalidRelativePath));
    }

    #[test]
    fn read_full_and_slice_work() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("main.rs");
        make_file(&file_path, "a\nb\nc\nd\n");

        let safe_file_ops = SafeFileOps::with_defaults();
        let full = safe_file_ops
            .read_full(temp.path(), "main.rs", 1024)
            .expect("read full");
        assert_eq!(full.content, "a\nb\nc\nd\n");
        assert!(!full.is_truncated);

        let slice = safe_file_ops
            .read_slice(temp.path(), "main.rs", 1, 2, 1024)
            .expect("read slice");
        assert_eq!(slice.content, "b\nc\n");
        assert_eq!(slice.start_line, 1);
        assert_eq!(slice.end_line_exclusive, 3);
        assert!(slice.has_more_before);
        assert!(slice.has_more_after);
    }

    #[test]
    fn read_full_zero_max_bytes_is_empty_and_truncated() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("file.txt"), "hello world");

        let safe_file_ops = SafeFileOps::with_defaults();
        let full = safe_file_ops
            .read_full(temp.path(), "file.txt", 0)
            .expect("read full");
        assert_eq!(full.content, "");
        assert!(full.is_truncated);
    }

    #[test]
    fn read_slice_zero_line_count_returns_empty_content() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("main.rs"), "a\nb\nc");

        let safe_file_ops = SafeFileOps::with_defaults();
        let slice = safe_file_ops
            .read_slice(temp.path(), "main.rs", 1, 0, 1024)
            .expect("read slice");
        assert_eq!(slice.content, "");
        assert_eq!(slice.start_line, 1);
        assert_eq!(slice.end_line_exclusive, 1);
        assert!(slice.has_more_before);
        assert!(slice.has_more_after);
    }

    #[test]
    fn read_slice_clamps_start_beyond_end_of_file() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("main.rs"), "a\nb\nc");

        let safe_file_ops = SafeFileOps::with_defaults();
        let slice = safe_file_ops
            .read_slice(temp.path(), "main.rs", 99, 10, 1024)
            .expect("read slice");
        assert_eq!(slice.content, "");
        assert_eq!(slice.start_line, slice.total_lines);
        assert_eq!(slice.end_line_exclusive, slice.total_lines);
        assert!(slice.has_more_before);
        assert!(!slice.has_more_after);
    }

    #[test]
    fn utf8_safe_truncation() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("emoji.txt");
        make_file(&file_path, "hello🙂world");

        let safe_file_ops = SafeFileOps::with_defaults();
        let full = safe_file_ops
            .read_full(temp.path(), "emoji.txt", 7)
            .expect("read full");
        assert!(full.is_truncated);
        assert!(std::str::from_utf8(full.content.as_bytes()).is_ok());
    }

    #[test]
    fn read_full_rejects_invalid_utf8() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("invalid.bin");
        fs::write(&file_path, [0x66, 0x6f, 0x80]).expect("write invalid utf8");

        let safe_file_ops = SafeFileOps::with_defaults();
        let err = safe_file_ops
            .read_full(temp.path(), "invalid.bin", 1024)
            .expect_err("invalid utf8 should fail");
        assert!(matches!(err, SafeFileOpsError::InvalidUtf8));
    }

    #[test]
    fn cache_invalidates_on_file_change() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("data.txt");
        make_file(&file_path, "one");

        let safe_file_ops = SafeFileOps::with_defaults();
        let first = safe_file_ops
            .read_full(temp.path(), "data.txt", 1024)
            .expect("read first");
        assert_eq!(first.content, "one");

        std::thread::sleep(std::time::Duration::from_millis(1));
        make_file(&file_path, "two");

        let second = safe_file_ops
            .read_full(temp.path(), "data.txt", 1024)
            .expect("read second");
        assert_eq!(second.content, "two");
        assert_ne!(first.revision.token, second.revision.token);
    }

    #[test]
    fn lru_eviction_respects_size_cap() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("a.txt"), "aaaaaaaaaa");
        make_file(&temp.path().join("b.txt"), "bbbbbbbbbb");

        let safe_file_ops = SafeFileOps::new(12, 1024 * 1024);
        safe_file_ops
            .read_full(temp.path(), "a.txt", 1024)
            .expect("read a");
        safe_file_ops
            .read_full(temp.path(), "b.txt", 1024)
            .expect("read b");

        // With 12-byte cap and ~10-byte files, one of the entries must be evicted.
        assert_eq!(safe_file_ops.cache_entry_count(), 1);
    }

    #[test]
    fn write_full_requires_expected_revision_unless_force() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("main.rs"), "before\n");
        let safe_file_ops = SafeFileOps::with_defaults();

        let err = safe_file_ops
            .write_full(temp.path(), "main.rs", "after\n", None, false)
            .expect_err("missing expected revision should fail");
        assert!(matches!(err, SafeFileOpsError::MissingExpectedRevision));
    }

    #[test]
    fn write_full_force_can_create_new_file_without_expected_revision() {
        let temp = tempfile::tempdir().expect("tempdir");
        let safe_file_ops = SafeFileOps::with_defaults();

        let result = safe_file_ops
            .write_full(temp.path(), "created.txt", "hello\n", None, true)
            .expect("force create");
        assert_eq!(result.bytes_written, 6);
        assert_eq!(
            fs::read_to_string(temp.path().join("created.txt")).expect("read created"),
            "hello\n"
        );
    }

    #[test]
    fn write_full_force_can_overwrite_without_expected_revision() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("main.rs"), "before\n");
        let safe_file_ops = SafeFileOps::with_defaults();

        safe_file_ops
            .write_full(temp.path(), "main.rs", "after\n", None, true)
            .expect("force overwrite");
        assert_eq!(
            fs::read_to_string(temp.path().join("main.rs")).expect("read content"),
            "after\n"
        );
    }

    #[cfg(unix)]
    #[test]
    fn write_full_preserves_existing_unix_mode_bits() {
        use std::os::unix::fs::PermissionsExt;

        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("main.rs");
        make_file(&file_path, "before\n");
        fs::set_permissions(&file_path, fs::Permissions::from_mode(0o640)).expect("set mode");

        let safe_file_ops = SafeFileOps::with_defaults();
        let snapshot = safe_file_ops
            .read_full(temp.path(), "main.rs", 1024)
            .expect("snapshot");
        safe_file_ops
            .write_full(
                temp.path(),
                "main.rs",
                "after\n",
                Some(&snapshot.revision),
                false,
            )
            .expect("write");

        let mode = fs::metadata(&file_path)
            .expect("metadata")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o640);
    }

    #[test]
    fn write_conflict_and_force_overwrite() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("main.rs");
        make_file(&file_path, "before\n");

        let safe_file_ops = SafeFileOps::with_defaults();
        let snapshot = safe_file_ops
            .read_full(temp.path(), "main.rs", 1024)
            .expect("snapshot read");

        make_file(&file_path, "external\n");

        let err = safe_file_ops
            .write_full(
                temp.path(),
                "main.rs",
                "local\n",
                Some(&snapshot.revision),
                false,
            )
            .expect_err("must conflict");
        assert!(matches!(err, SafeFileOpsError::RevisionConflict { .. }));

        safe_file_ops
            .write_full(
                temp.path(),
                "main.rs",
                "force\n",
                Some(&snapshot.revision),
                true,
            )
            .expect("force write should succeed");

        let content = fs::read_to_string(&file_path).expect("read content");
        assert_eq!(content, "force\n");
    }

    #[test]
    fn replace_range_requires_expected_revision_unless_force() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("mod.rs"), "line1\nline2\n");
        let safe_file_ops = SafeFileOps::with_defaults();

        let err = safe_file_ops
            .replace_range(temp.path(), "mod.rs", 0, 1, "new\n", None, false)
            .expect_err("missing expected revision should fail");
        assert!(matches!(err, SafeFileOpsError::MissingExpectedRevision));
    }

    #[test]
    fn replace_range_rejects_invalid_range() {
        let temp = tempfile::tempdir().expect("tempdir");
        make_file(&temp.path().join("mod.rs"), "line1\nline2\n");
        let safe_file_ops = SafeFileOps::with_defaults();
        let full = safe_file_ops
            .read_full(temp.path(), "mod.rs", 1024)
            .expect("read full");

        let err = safe_file_ops
            .replace_range(
                temp.path(),
                "mod.rs",
                2,
                1,
                "new\n",
                Some(&full.revision),
                false,
            )
            .expect_err("invalid range");
        assert!(matches!(err, SafeFileOpsError::InvalidRange));
    }

    #[test]
    fn replace_range_applies_changes() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("mod.rs");
        make_file(&file_path, "line1\nline2\nline3\n");

        let safe_file_ops = SafeFileOps::with_defaults();
        let full = safe_file_ops
            .read_full(temp.path(), "mod.rs", 1024)
            .expect("read full");

        let result = safe_file_ops
            .replace_range(
                temp.path(),
                "mod.rs",
                1,
                2,
                "replacement\n",
                Some(&full.revision),
                false,
            )
            .expect("replace range");

        assert!(result.total_lines >= 3);
        let content = fs::read_to_string(&file_path).expect("read content");
        assert_eq!(content, "line1\nreplacement\nline3\n");
    }

    #[test]
    fn read_only_reason_for_large_edit_file() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file_path = temp.path().join("huge.txt");
        make_file(&file_path, "abcdefghijklmnopqrstuvwxyz");

        let safe_file_ops = SafeFileOps::new(DEFAULT_CACHE_MAX_BYTES, 8);
        let full = safe_file_ops
            .read_full(temp.path(), "huge.txt", 1024)
            .expect("read full");

        assert!(full.read_only_reason.is_some());
    }
}
