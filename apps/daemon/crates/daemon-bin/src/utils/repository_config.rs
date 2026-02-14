//! Repository-local configuration management (`<repo>/.unbound/config.json`).
#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use uuid::Uuid;

const SCHEMA_VERSION: u32 = 1;
const DEFAULT_WORKTREE_ROOT_DIR_TEMPLATE: &str = "~/.unbound/{repo_id}/worktrees";
const DEFAULT_HOOK_TIMEOUT_SECONDS: u64 = 300;

pub fn default_worktree_root_dir_for_repo(repo_id: &str) -> String {
    DEFAULT_WORKTREE_ROOT_DIR_TEMPLATE.replace("{repo_id}", repo_id)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RepositoryConfig {
    pub schema_version: u32,
    pub worktree: WorktreeConfig,
    pub setup_hooks: SetupHooksConfig,
}

impl Default for RepositoryConfig {
    fn default() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            worktree: WorktreeConfig::default(),
            setup_hooks: SetupHooksConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WorktreeConfig {
    pub root_dir: String,
    pub default_base_branch: Option<String>,
}

impl Default for WorktreeConfig {
    fn default() -> Self {
        Self {
            root_dir: DEFAULT_WORKTREE_ROOT_DIR_TEMPLATE.to_string(),
            default_base_branch: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SetupHooksConfig {
    pub pre_create: SetupHookStageConfig,
    pub post_create: SetupHookStageConfig,
}

impl Default for SetupHooksConfig {
    fn default() -> Self {
        Self {
            pre_create: SetupHookStageConfig::default(),
            post_create: SetupHookStageConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SetupHookStageConfig {
    pub command: Option<String>,
    pub timeout_seconds: u64,
}

impl Default for SetupHookStageConfig {
    fn default() -> Self {
        Self {
            command: None,
            timeout_seconds: DEFAULT_HOOK_TIMEOUT_SECONDS,
        }
    }
}

/// Partial update payload for managed config keys.
#[derive(Debug, Clone, Default)]
pub struct RepositoryConfigUpdate {
    pub worktree_root_dir: Option<String>,
    pub worktree_default_base_branch: Option<Option<String>>,
    pub pre_create_command: Option<Option<String>>,
    pub pre_create_timeout_seconds: Option<u64>,
    pub post_create_command: Option<Option<String>>,
    pub post_create_timeout_seconds: Option<u64>,
}

/// Load repository config, applying defaults for missing managed keys.
pub fn load_repository_config(
    repo_path: &Path,
    default_worktree_root_dir: &str,
) -> Result<RepositoryConfig, String> {
    let root = read_config_root(repo_path)?;
    Ok(extract_managed_config(&root, default_worktree_root_dir))
}

/// Merge managed keys into repository config and write atomically.
///
/// Unknown keys are preserved as-is.
pub fn update_repository_config(
    repo_path: &Path,
    update: &RepositoryConfigUpdate,
    default_worktree_root_dir: &str,
) -> Result<RepositoryConfig, String> {
    let mut root = read_config_root(repo_path)?;
    let mut managed = extract_managed_config(&root, default_worktree_root_dir);

    apply_update(&mut managed, update);
    merge_managed_into_root(&mut root, &managed);
    write_config_root_atomic(repo_path, &root)?;

    Ok(managed)
}

fn config_path(repo_path: &Path) -> PathBuf {
    repo_path.join(".unbound").join("config.json")
}

fn read_config_root(repo_path: &Path) -> Result<Map<String, Value>, String> {
    let path = config_path(repo_path);
    if !path.exists() {
        return Ok(Map::new());
    }

    let content = fs::read_to_string(&path)
        .map_err(|e| format!("failed to read config at {}: {}", path.display(), e))?;
    let value: Value = serde_json::from_str(&content)
        .map_err(|e| format!("failed to parse config at {}: {}", path.display(), e))?;
    value
        .as_object()
        .cloned()
        .ok_or_else(|| format!("config root at {} must be a JSON object", path.display()))
}

fn extract_managed_config(
    root: &Map<String, Value>,
    default_worktree_root_dir: &str,
) -> RepositoryConfig {
    let schema_version = root
        .get("schema_version")
        .and_then(Value::as_u64)
        .map(|v| v as u32)
        .unwrap_or(SCHEMA_VERSION);

    let worktree_obj = root.get("worktree").and_then(Value::as_object);
    let setup_hooks_obj = root.get("setup_hooks").and_then(Value::as_object);

    let root_dir = worktree_obj
        .and_then(|w| w.get("root_dir"))
        .and_then(Value::as_str)
        .unwrap_or(default_worktree_root_dir)
        .to_string();
    let default_base_branch = worktree_obj
        .and_then(|w| w.get("default_base_branch"))
        .and_then(Value::as_str)
        .map(String::from);

    let pre_create_obj = setup_hooks_obj
        .and_then(|s| s.get("pre_create"))
        .and_then(Value::as_object);
    let post_create_obj = setup_hooks_obj
        .and_then(|s| s.get("post_create"))
        .and_then(Value::as_object);

    let pre_create = SetupHookStageConfig {
        command: pre_create_obj
            .and_then(|s| s.get("command"))
            .and_then(Value::as_str)
            .map(String::from),
        timeout_seconds: pre_create_obj
            .and_then(|s| s.get("timeout_seconds"))
            .and_then(Value::as_u64)
            .unwrap_or(DEFAULT_HOOK_TIMEOUT_SECONDS),
    };

    let post_create = SetupHookStageConfig {
        command: post_create_obj
            .and_then(|s| s.get("command"))
            .and_then(Value::as_str)
            .map(String::from),
        timeout_seconds: post_create_obj
            .and_then(|s| s.get("timeout_seconds"))
            .and_then(Value::as_u64)
            .unwrap_or(DEFAULT_HOOK_TIMEOUT_SECONDS),
    };

    RepositoryConfig {
        schema_version,
        worktree: WorktreeConfig {
            root_dir,
            default_base_branch,
        },
        setup_hooks: SetupHooksConfig {
            pre_create,
            post_create,
        },
    }
}

fn apply_update(config: &mut RepositoryConfig, update: &RepositoryConfigUpdate) {
    if let Some(root_dir) = &update.worktree_root_dir {
        config.worktree.root_dir = root_dir.clone();
    }
    if let Some(default_base_branch) = &update.worktree_default_base_branch {
        config.worktree.default_base_branch = default_base_branch.clone();
    }
    if let Some(command) = &update.pre_create_command {
        config.setup_hooks.pre_create.command = command.clone();
    }
    if let Some(timeout_seconds) = update.pre_create_timeout_seconds {
        config.setup_hooks.pre_create.timeout_seconds = timeout_seconds;
    }
    if let Some(command) = &update.post_create_command {
        config.setup_hooks.post_create.command = command.clone();
    }
    if let Some(timeout_seconds) = update.post_create_timeout_seconds {
        config.setup_hooks.post_create.timeout_seconds = timeout_seconds;
    }
    config.schema_version = SCHEMA_VERSION;
}

fn merge_managed_into_root(root: &mut Map<String, Value>, config: &RepositoryConfig) {
    root.insert(
        "schema_version".to_string(),
        Value::Number(config.schema_version.into()),
    );

    let worktree = ensure_object(root, "worktree");
    worktree.insert(
        "root_dir".to_string(),
        Value::String(config.worktree.root_dir.clone()),
    );
    worktree.insert(
        "default_base_branch".to_string(),
        match &config.worktree.default_base_branch {
            Some(v) => Value::String(v.clone()),
            None => Value::Null,
        },
    );

    let setup_hooks = ensure_object(root, "setup_hooks");

    let pre_create = ensure_object(setup_hooks, "pre_create");
    pre_create.insert(
        "command".to_string(),
        match &config.setup_hooks.pre_create.command {
            Some(v) => Value::String(v.clone()),
            None => Value::Null,
        },
    );
    pre_create.insert(
        "timeout_seconds".to_string(),
        Value::Number(config.setup_hooks.pre_create.timeout_seconds.into()),
    );

    let post_create = ensure_object(setup_hooks, "post_create");
    post_create.insert(
        "command".to_string(),
        match &config.setup_hooks.post_create.command {
            Some(v) => Value::String(v.clone()),
            None => Value::Null,
        },
    );
    post_create.insert(
        "timeout_seconds".to_string(),
        Value::Number(config.setup_hooks.post_create.timeout_seconds.into()),
    );
}

fn ensure_object<'a>(parent: &'a mut Map<String, Value>, key: &str) -> &'a mut Map<String, Value> {
    if !matches!(parent.get(key), Some(Value::Object(_))) {
        parent.insert(key.to_string(), Value::Object(Map::new()));
    }
    parent
        .get_mut(key)
        .and_then(Value::as_object_mut)
        .expect("object must exist")
}

fn write_config_root_atomic(repo_path: &Path, root: &Map<String, Value>) -> Result<(), String> {
    let path = config_path(repo_path);
    let dir = path
        .parent()
        .ok_or_else(|| format!("invalid config path: {}", path.display()))?;
    fs::create_dir_all(dir)
        .map_err(|e| format!("failed to create config directory {}: {}", dir.display(), e))?;

    let tmp_path = dir.join(format!("config.json.tmp.{}", Uuid::new_v4()));
    let payload = serde_json::to_string_pretty(&Value::Object(root.clone()))
        .map_err(|e| format!("failed to serialize config: {}", e))?;

    let mut file = fs::File::create(&tmp_path)
        .map_err(|e| format!("failed to create temp config {}: {}", tmp_path.display(), e))?;
    file.write_all(payload.as_bytes())
        .and_then(|_| file.write_all(b"\n"))
        .map_err(|e| format!("failed to write temp config {}: {}", tmp_path.display(), e))?;
    file.sync_all()
        .map_err(|e| format!("failed to sync temp config {}: {}", tmp_path.display(), e))?;

    fs::rename(&tmp_path, &path).map_err(|e| {
        format!(
            "failed to atomically replace config {} with {}: {}",
            path.display(),
            tmp_path.display(),
            e
        )
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_repo_path() -> PathBuf {
        let path = std::env::temp_dir().join(format!("daemon-repo-config-test-{}", Uuid::new_v4()));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn load_defaults_when_config_missing() {
        let repo_path = temp_repo_path();
        let default_root = default_worktree_root_dir_for_repo("repo-123");
        let loaded = load_repository_config(&repo_path, &default_root).unwrap();
        assert_eq!(loaded.worktree.root_dir, default_root);
        assert_eq!(loaded.worktree.default_base_branch, None);
        assert_eq!(loaded.setup_hooks.pre_create.timeout_seconds, 300);
        assert_eq!(loaded.setup_hooks.post_create.timeout_seconds, 300);
        let _ = fs::remove_dir_all(repo_path);
    }

    #[test]
    fn update_creates_unbound_config_and_persists_values() {
        let repo_path = temp_repo_path();
        let default_root = default_worktree_root_dir_for_repo("repo-123");
        let updated = update_repository_config(
            &repo_path,
            &RepositoryConfigUpdate {
                worktree_default_base_branch: Some(Some("main".to_string())),
                pre_create_command: Some(Some("echo pre".to_string())),
                pre_create_timeout_seconds: Some(120),
                post_create_command: Some(Some("echo post".to_string())),
                post_create_timeout_seconds: Some(180),
                ..Default::default()
            },
            &default_root,
        )
        .unwrap();

        assert_eq!(updated.worktree.root_dir, default_root);
        assert_eq!(
            updated.worktree.default_base_branch,
            Some("main".to_string())
        );
        assert_eq!(
            updated.setup_hooks.pre_create.command,
            Some("echo pre".to_string())
        );
        assert_eq!(updated.setup_hooks.pre_create.timeout_seconds, 120);
        assert_eq!(
            updated.setup_hooks.post_create.command,
            Some("echo post".to_string())
        );
        assert_eq!(updated.setup_hooks.post_create.timeout_seconds, 180);

        let config_file = repo_path.join(".unbound").join("config.json");
        assert!(config_file.exists());

        let loaded = load_repository_config(&repo_path, &default_root).unwrap();
        assert_eq!(loaded, updated);
        let _ = fs::remove_dir_all(repo_path);
    }

    #[test]
    fn update_preserves_unknown_keys() {
        let repo_path = temp_repo_path();
        let config_dir = repo_path.join(".unbound");
        fs::create_dir_all(&config_dir).unwrap();
        let config_path = config_dir.join("config.json");
        fs::write(
            &config_path,
            r#"{
  "schema_version": 1,
  "unknown_top": { "keep": true },
  "worktree": {
    "root_dir": ".custom/worktrees",
    "custom_worktree_key": "keep-me"
  },
  "setup_hooks": {
    "another_hook_key": "keep-me-too",
    "pre_create": {
      "command": "echo old",
      "timeout_seconds": 10,
      "custom_pre_key": "keep-pre"
    },
    "post_create": {
      "command": null,
      "timeout_seconds": 20
    }
  }
}"#,
        )
        .unwrap();

        update_repository_config(
            &repo_path,
            &RepositoryConfigUpdate {
                worktree_default_base_branch: Some(Some("develop".to_string())),
                pre_create_command: Some(Some("echo new".to_string())),
                ..Default::default()
            },
            &default_worktree_root_dir_for_repo("repo-123"),
        )
        .unwrap();

        let content = fs::read_to_string(&config_path).unwrap();
        let root: Value = serde_json::from_str(&content).unwrap();
        assert_eq!(root["unknown_top"]["keep"], Value::Bool(true));
        assert_eq!(
            root["worktree"]["custom_worktree_key"],
            Value::String("keep-me".to_string())
        );
        assert_eq!(
            root["setup_hooks"]["another_hook_key"],
            Value::String("keep-me-too".to_string())
        );
        assert_eq!(
            root["setup_hooks"]["pre_create"]["custom_pre_key"],
            Value::String("keep-pre".to_string())
        );
        assert_eq!(
            root["setup_hooks"]["pre_create"]["command"],
            Value::String("echo new".to_string())
        );
        assert_eq!(
            root["worktree"]["default_base_branch"],
            Value::String("develop".to_string())
        );
        let _ = fs::remove_dir_all(repo_path);
    }
}
