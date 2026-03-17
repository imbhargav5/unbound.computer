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
  dashboard_project_views?:
    | Record<
        string,
        {
          group_by?: "status" | "priority" | "assignee" | null;
        }
      >
    | null;
}

export interface Company {
  id: string;
  name: string;
  description?: string | null;
  status?: string | null;
  issue_prefix?: string | null;
  issue_counter?: number | null;
  budget_monthly_cents?: number | null;
  spent_monthly_cents?: number | null;
  require_board_approval_for_new_agents?: boolean | null;
  brand_color?: string | null;
  ceo_agent_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface AgentRecord {
  id: string;
  company_id?: string | null;
  name: string;
  slug?: string | null;
  role?: string | null;
  title?: string | null;
  icon?: string | null;
  status?: string | null;
  adapter_type?: string | null;
  adapter_config?: Record<string, unknown> | null;
  runtime_config?: Record<string, unknown> | null;
  permissions?: Record<string, unknown> | null;
  reports_to?: string | null;
  home_path?: string | null;
  instructions_path?: string | null;
  budget_monthly_cents?: number | null;
  spent_monthly_cents?: number | null;
  last_heartbeat_at?: string | null;
  capabilities?: string | null;
  metadata?: Record<string, unknown> | null;
  created_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface AgentRunRecord {
  id: string;
  company_id: string;
  agent_id: string;
  invocation_source: string;
  trigger_detail?: string | null;
  wake_reason?: string | null;
  status: string;
  started_at?: string | null;
  finished_at?: string | null;
  error?: string | null;
  wakeup_request_id?: string | null;
  exit_code?: number | null;
  signal?: string | null;
  usage_json?: unknown;
  result_json?: unknown;
  session_id_before?: string | null;
  session_id_after?: string | null;
  log_store?: string | null;
  log_ref?: string | null;
  log_bytes?: number | null;
  log_sha256?: string | null;
  log_compressed?: boolean | null;
  stdout_excerpt?: string | null;
  stderr_excerpt?: string | null;
  error_code?: string | null;
  external_run_id?: string | null;
  context_snapshot?: unknown;
  created_at: string;
  updated_at: string;
}

export interface AgentRunEventRecord {
  id: number;
  company_id: string;
  run_id: string;
  agent_id: string;
  seq: number;
  event_type: string;
  stream?: string | null;
  level?: string | null;
  color?: string | null;
  message?: string | null;
  payload?: unknown;
  created_at: string;
}

export interface AgentRunLogChunk {
  content: string;
  next_offset: number;
  done: boolean;
}

export interface GoalRecord {
  id: string;
  company_id?: string | null;
  title: string;
  description?: string | null;
  level?: string | null;
  status?: string | null;
  parent_id?: string | null;
  owner_agent_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface ProjectWorkspaceRecord {
  id: string;
  company_id?: string | null;
  project_id?: string | null;
  name: string;
  cwd?: string | null;
  repo_url?: string | null;
  repo_ref?: string | null;
  metadata?: Record<string, unknown> | null;
  is_primary?: boolean | null;
  created_at?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface ProjectRecord {
  id: string;
  company_id?: string | null;
  goal_id?: string | null;
  title?: string | null;
  name: string;
  description?: string | null;
  status: string;
  lead_agent_id?: string | null;
  target_date?: string | null;
  color?: string | null;
  execution_workspace_policy?: Record<string, unknown> | null;
  archived_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  primary_workspace?: ProjectWorkspaceRecord | null;
  [key: string]: unknown;
}

export interface IssueRecord {
  id: string;
  company_id: string;
  project_id?: string | null;
  goal_id?: string | null;
  parent_id?: string | null;
  title: string;
  description?: string | null;
  status: string;
  priority: string;
  assignee_agent_id?: string | null;
  assignee_user_id?: string | null;
  checkout_run_id?: string | null;
  execution_run_id?: string | null;
  execution_agent_name_key?: string | null;
  execution_locked_at?: string | null;
  created_by_agent_id?: string | null;
  created_by_user_id?: string | null;
  issue_number?: number | null;
  identifier?: string | null;
  request_depth: number;
  billing_code?: string | null;
  assignee_adapter_overrides?: Record<string, unknown> | null;
  execution_workspace_settings?: Record<string, unknown> | null;
  started_at?: string | null;
  completed_at?: string | null;
  cancelled_at?: string | null;
  hidden_at?: string | null;
  workspace_session_id?: string | null;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
}

export interface IssueCommentRecord {
  id: string;
  company_id: string;
  issue_id: string;
  author_agent_id?: string | null;
  author_user_id?: string | null;
  body: string;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
}

export interface ApprovalRecord {
  id: string;
  company_id?: string | null;
  approval_type?: string | null;
  requested_by_agent_id?: string | null;
  requested_by_user_id?: string | null;
  status?: string | null;
  payload?: Record<string, unknown> | null;
  decision_note?: string | null;
  decided_by_user_id?: string | null;
  decided_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
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
  goals: GoalRecord[];
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
