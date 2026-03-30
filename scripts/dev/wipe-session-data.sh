#!/bin/zsh

set -euo pipefail

DB_PATH="$HOME/Library/Application Support/com.unbound.macos/unbound.sqlite"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if [[ ! -f "$DB_PATH" ]]; then
  echo "Database not found at $DB_PATH" >&2
  exit 1
fi

if pgrep -x unbound-daemon >/dev/null 2>&1 || pgrep -x unbound-macos >/dev/null 2>&1; then
  echo "Stop unbound-daemon and unbound-macos before running this script." >&2
  exit 1
fi

echo "Removing tracked worktrees from $DB_PATH"

while IFS=$'\t' read -r repo_path worktree_path; do
  [[ -n "${worktree_path:-}" ]] || continue

  if [[ -n "${repo_path:-}" && -d "$repo_path" ]]; then
    git -C "$repo_path" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
  fi

  if [[ -e "$worktree_path" ]]; then
    rm -rf "$worktree_path"
  fi
done < <(
  sqlite3 -separator $'\t' "$DB_PATH" "
    SELECT DISTINCT
      COALESCE(repositories.path, ''),
      COALESCE(local_llm_conversations.worktree_path, '')
    FROM local_llm_conversations
    JOIN repositories ON repositories.id = local_llm_conversations.repository_id
    WHERE local_llm_conversations.is_worktree = 1
      AND local_llm_conversations.worktree_path IS NOT NULL;
  "
)

sqlite3 "$DB_PATH" <<'SQL'
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
DELETE FROM local_llm_conversations;
COMMIT;
VACUUM;
SQL

echo "Wiped all session data from $DB_PATH"
