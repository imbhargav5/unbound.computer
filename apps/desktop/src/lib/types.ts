export interface DesktopCompatibilityRange {
  min_version: string;
  max_version: string;
  strict: boolean;
}

export interface DaemonVersionInfo {
  daemon_version: string;
  protocol_version: number;
  desktop_compatibility: DesktopCompatibilityRange;
}

export type BootstrapState =
  | "ready"
  | "missing_daemon"
  | "incompatible_daemon"
  | "daemon_unavailable";

export interface DesktopBootstrapStatus {
  state: BootstrapState;
  message: string;
  expected_app_version: string;
  base_dir: string;
  socket_path: string;
  searched_paths: string[];
  resolved_daemon_path: string | null;
  daemon_info: DaemonVersionInfo | null;
}

export interface DesktopSettings {
  preferred_company_id?: string | null;
  preferred_repository_id?: string | null;
  preferred_view?: string | null;
  show_raw_message_json: boolean;
  last_repository_path?: string | null;
  theme_mode?: "system" | "light" | "dark" | null;
  font_size_preset?: "small" | "medium" | "large" | null;
}

export interface Company {
  id: string;
  name: string;
  description?: string | null;
  brand_color?: string | null;
  [key: string]: unknown;
}

export interface AgentRecord {
  id: string;
  name: string;
  role?: string | null;
  title?: string | null;
  status?: string | null;
  [key: string]: unknown;
}

export interface ProjectRecord {
  id: string;
  title?: string | null;
  name?: string | null;
  status?: string | null;
  [key: string]: unknown;
}

export interface IssueRecord {
  id: string;
  title: string;
  status?: string | null;
  priority?: string | null;
  [key: string]: unknown;
}

export interface ApprovalRecord {
  id: string;
  status?: string | null;
  type?: string | null;
  [key: string]: unknown;
}

export interface WorkspaceRecord {
  id: string;
  session_id: string;
  repository_id: string;
  company_id?: string | null;
  project_id?: string | null;
  issue_id?: string | null;
  agent_id?: string | null;
  title: string;
  status?: string | null;
  workspace_type?: string | null;
  workspace_status?: string | null;
  workspace_repo_path?: string | null;
  workspace_branch?: string | null;
  workspace_metadata?: Record<string, unknown> | null;
  issue_identifier?: string | null;
  issue_title?: string | null;
  project_name?: string | null;
  agent_name?: string | null;
  created_at?: string | null;
  last_accessed_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface CompanySnapshot {
  company: Company;
  agents: AgentRecord[];
  goals: Array<Record<string, unknown>>;
  projects: ProjectRecord[];
  issues: IssueRecord[];
  approvals: ApprovalRecord[];
  workspaces: WorkspaceRecord[];
}

export interface RepositoryRecord {
  id: string;
  path: string;
  name: string;
  is_git_repository?: boolean;
  default_branch?: string | null;
  [key: string]: unknown;
}

export interface SessionRecord {
  id: string;
  repository_id: string;
  title: string;
  status?: string;
  is_worktree?: boolean;
  worktree_path?: string | null;
  claude_session_id?: string | null;
  [key: string]: unknown;
}

export interface SessionMessage {
  id: string;
  session_id: string;
  sequence_number: number | string;
  content: unknown;
}

export interface FileEntry {
  name: string;
  path: string;
  is_dir: boolean;
  has_children: boolean;
}

export interface FileReadResult {
  content: string;
  is_truncated: boolean;
  revision?: unknown;
  total_lines?: number;
  read_only_reason?: string | null;
}

export interface GitStatusFile {
  path: string;
  status?: string | null;
  staged?: boolean;
  additions?: number;
  deletions?: number;
  [key: string]: unknown;
}

export interface GitStatusResult {
  files: GitStatusFile[];
  branch?: string | null;
  is_clean?: boolean;
}

export interface GitDiffResult {
  file_path: string;
  diff: string;
  is_binary: boolean;
  is_truncated: boolean;
  additions: number;
  deletions: number;
}

export interface GitCommit {
  oid: string;
  short_oid: string;
  message: string;
  summary: string;
  author_name: string;
  author_email: string;
  author_time: number;
  committer_name: string;
  committer_time: number;
  parent_oids: string[];
}

export interface GitLogResult {
  commits: GitCommit[];
  has_more: boolean;
  total_count?: number | null;
}

export interface GitBranch {
  name: string;
  is_current: boolean;
  is_remote: boolean;
  upstream?: string | null;
  ahead: number;
  behind: number;
  head_oid: string;
}

export interface GitBranchesResult {
  local: GitBranch[];
  remote: GitBranch[];
  current?: string | null;
}

export interface SessionStreamPayload {
  session_id: string;
  event: {
    event_type?: string;
    session_id?: string;
    data?: Record<string, unknown>;
    sequence?: number;
    [key: string]: unknown;
  };
}
