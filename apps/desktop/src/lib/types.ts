export interface DesktopCompatibilityRange {
  max_version: string;
  min_version: string;
  strict: boolean;
}

export interface DaemonVersionInfo {
  daemon_version: string;
  desktop_compatibility: DesktopCompatibilityRange;
  protocol_version: number;
}

export type BootstrapState =
  | "ready"
  | "missing_daemon"
  | "incompatible_daemon"
  | "daemon_unavailable";

export interface DesktopBootstrapStatus {
  base_dir: string;
  daemon_info: DaemonVersionInfo | null;
  expected_app_version: string;
  message: string;
  resolved_daemon_path: string | null;
  searched_paths: string[];
  socket_path: string;
  state: BootstrapState;
}

export interface ToolCapabilities {
  installed: boolean;
  models?: string[] | null;
  path?: string | null;
}

export interface CliCapabilities {
  claude: ToolCapabilities;
  codex: ToolCapabilities;
  gh: ToolCapabilities;
  ollama: ToolCapabilities;
}

export interface CapabilitiesMetadata {
  collected_at: string;
  schema_version: number;
}

export interface RuntimeCapabilities {
  cli: CliCapabilities;
  metadata: CapabilitiesMetadata;
}

export interface DesktopSettings {
  birds_eye_canvas?: Record<string, BirdsEyeCanvasCompanyState> | null;
  dashboard_project_views?: Record<
    string,
    {
      group_by?: "status" | "priority" | "assignee" | null;
      saved_views?: Array<{
        id: string;
        name?: string | null;
        group_by?: "status" | "priority" | "assignee" | null;
      }> | null;
    }
  > | null;
  font_size_preset?: "small" | "medium" | "large" | null;
  last_repository_path?: string | null;
  preferred_company_id?: string | null;
  preferred_repository_id?: string | null;
  preferred_space_id?: string | null;
  preferred_view?: string | null;
  show_raw_message_json: boolean;
  theme_mode?: "system" | "light" | "dark" | null;
}

export interface CurrentMachineRecord {
  id: string;
  name: string;
  user_id: string;
}

export interface CurrentSpaceRecord {
  color: string;
  created_at: string;
  id: string;
  machine_id: string;
  name: string;
  user_id: string;
}

export interface CurrentSpaceScope {
  machine: CurrentMachineRecord;
  space: CurrentSpaceRecord;
}

export interface BirdsEyeCanvasViewportState {
  x: number;
  y: number;
  zoom_index: number;
}

export interface BirdsEyeCanvasRepoRegionState {
  page?: number | null;
  x: number;
  y: number;
}

export interface BirdsEyeCanvasWorktreeTileState {
  active_issue_id?: string | null;
  issue_ids?: string[] | null;
  lru_issue_ids?: string[] | null;
}

export interface BirdsEyeCanvasFocusTargetState {
  issue_id?: string | null;
  kind: "repo" | "worktree" | "chat" | "tile";
  project_id: string;
  worktree_key?: string | null;
}

export interface BirdsEyeCanvasCompanyState {
  focused_target?: BirdsEyeCanvasFocusTargetState | null;
  repo_regions?: Record<string, BirdsEyeCanvasRepoRegionState> | null;
  viewport?: BirdsEyeCanvasViewportState | null;
  worktree_tiles?: Record<string, BirdsEyeCanvasWorktreeTileState> | null;
}

export interface Company {
  brand_color?: string | null;
  budget_monthly_cents?: number | null;
  ceo_agent_id?: string | null;
  created_at?: string | null;
  description?: string | null;
  id: string;
  issue_counter?: number | null;
  issue_prefix?: string | null;
  name: string;
  require_board_approval_for_new_agents?: boolean | null;
  spent_monthly_cents?: number | null;
  status?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface AgentRecord {
  adapter_config?: Record<string, unknown> | null;
  adapter_type?: string | null;
  budget_monthly_cents?: number | null;
  capabilities?: string | null;
  company_id?: string | null;
  created_at?: string | null;
  home_path?: string | null;
  icon?: string | null;
  id: string;
  instructions_path?: string | null;
  last_heartbeat_at?: string | null;
  metadata?: Record<string, unknown> | null;
  name: string;
  permissions?: Record<string, unknown> | null;
  reports_to?: string | null;
  role?: string | null;
  runtime_config?: Record<string, unknown> | null;
  slug?: string | null;
  spent_monthly_cents?: number | null;
  status?: string | null;
  title?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface AgentRunRecord {
  agent_id: string;
  company_id: string;
  context_snapshot?: unknown;
  created_at: string;
  error?: string | null;
  error_code?: string | null;
  exit_code?: number | null;
  external_run_id?: string | null;
  finished_at?: string | null;
  id: string;
  invocation_source: string;
  issue_id?: string | null;
  log_bytes?: number | null;
  log_compressed?: boolean | null;
  log_ref?: string | null;
  log_sha256?: string | null;
  log_store?: string | null;
  result_json?: unknown;
  session_id_after?: string | null;
  session_id_before?: string | null;
  signal?: string | null;
  started_at?: string | null;
  status: string;
  stderr_excerpt?: string | null;
  stdout_excerpt?: string | null;
  trigger_detail?: string | null;
  updated_at: string;
  usage_json?: unknown;
  wake_reason?: string | null;
  wakeup_request_id?: string | null;
}

export interface AgentRunEventRecord {
  agent_id: string;
  color?: string | null;
  company_id: string;
  created_at: string;
  event_type: string;
  id: number;
  level?: string | null;
  message?: string | null;
  payload?: unknown;
  run_id: string;
  seq: number;
  stream?: string | null;
}

export interface IssueRunCardUpdateRecord {
  agent_id: string;
  issue_id: string;
  issue_status: string;
  last_activity_at: string;
  last_event_type?: string | null;
  run_id: string;
  run_status: string;
  summary?: string | null;
}

export interface AgentLiveRunCountRecord {
  agent_id: string;
  live_count: number;
}

export interface AgentRunLogChunk {
  content: string;
  done: boolean;
  next_offset: number;
}

export interface GoalRecord {
  company_id?: string | null;
  created_at?: string | null;
  description?: string | null;
  id: string;
  level?: string | null;
  owner_agent_id?: string | null;
  parent_id?: string | null;
  status?: string | null;
  title: string;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface ProjectWorkspaceRecord {
  company_id?: string | null;
  created_at?: string | null;
  cwd?: string | null;
  id: string;
  is_primary?: boolean | null;
  metadata?: Record<string, unknown> | null;
  name: string;
  project_id?: string | null;
  repo_ref?: string | null;
  repo_url?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface ProjectRecord {
  archived_at?: string | null;
  color?: string | null;
  company_id?: string | null;
  created_at?: string | null;
  description?: string | null;
  execution_workspace_policy?: Record<string, unknown> | null;
  goal_id?: string | null;
  id: string;
  lead_agent_id?: string | null;
  name: string;
  primary_workspace?: ProjectWorkspaceRecord | null;
  status: string;
  target_date?: string | null;
  title?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface IssueRecord {
  assignee_adapter_overrides?: Record<string, unknown> | null;
  assignee_agent_id?: string | null;
  assignee_user_id?: string | null;
  billing_code?: string | null;
  cancelled_at?: string | null;
  checkout_run_id?: string | null;
  company_id: string;
  completed_at?: string | null;
  created_at: string;
  created_by_agent_id?: string | null;
  created_by_user_id?: string | null;
  description?: string | null;
  execution_agent_name_key?: string | null;
  execution_locked_at?: string | null;
  execution_run_id?: string | null;
  execution_workspace_settings?: Record<string, unknown> | null;
  goal_id?: string | null;
  hidden_at?: string | null;
  id: string;
  identifier?: string | null;
  issue_number?: number | null;
  parent_id?: string | null;
  priority: string;
  project_id?: string | null;
  request_depth: number;
  started_at?: string | null;
  status: string;
  title: string;
  updated_at: string;
  workspace_session_id?: string | null;
  [key: string]: unknown;
}

export interface IssueCommentRecord {
  author_agent_id?: string | null;
  author_user_id?: string | null;
  body: string;
  company_id: string;
  created_at: string;
  id: string;
  issue_id: string;
  target_agent_id?: string | null;
  updated_at: string;
  [key: string]: unknown;
}

export interface IssueAttachmentRecord {
  asset_id: string;
  byte_size: number;
  company_id: string;
  content_type: string;
  created_at: string;
  created_by_agent_id?: string | null;
  created_by_user_id?: string | null;
  id: string;
  issue_comment_id?: string | null;
  issue_id: string;
  local_path: string;
  object_key: string;
  original_filename?: string | null;
  provider: string;
  sha256: string;
  updated_at: string;
  [key: string]: unknown;
}

export interface ApprovalRecord {
  approval_type?: string | null;
  company_id?: string | null;
  created_at?: string | null;
  decided_at?: string | null;
  decided_by_user_id?: string | null;
  decision_note?: string | null;
  id: string;
  payload?: Record<string, unknown> | null;
  requested_by_agent_id?: string | null;
  requested_by_user_id?: string | null;
  status?: string | null;
  updated_at?: string | null;
  [key: string]: unknown;
}

export interface WorkspaceRecord {
  agent_id?: string | null;
  agent_name?: string | null;
  company_id?: string | null;
  created_at?: string | null;
  id: string;
  issue_id?: string | null;
  issue_identifier?: string | null;
  issue_title?: string | null;
  last_accessed_at?: string | null;
  project_id?: string | null;
  project_name?: string | null;
  repository_id: string;
  session_id: string;
  status?: string | null;
  title: string;
  updated_at?: string | null;
  workspace_branch?: string | null;
  workspace_metadata?: Record<string, unknown> | null;
  workspace_repo_path?: string | null;
  workspace_status?: string | null;
  workspace_type?: string | null;
  [key: string]: unknown;
}

export interface CompanySnapshot {
  agents: AgentRecord[];
  approvals: ApprovalRecord[];
  company: Company;
  goals: GoalRecord[];
  issues: IssueRecord[];
  projects: ProjectRecord[];
  workspaces: WorkspaceRecord[];
}

export interface DashboardOverviewChatRecord {
  assignee_adapter_overrides?: Record<string, unknown> | null;
  assignee_agent_id?: string | null;
  child_issue_count: number;
  created_at: string;
  execution_workspace_settings?: Record<string, unknown> | null;
  id: string;
  identifier?: string | null;
  priority: string;
  project_id: string;
  run_update?: IssueRunCardUpdateRecord | null;
  status: string;
  title: string;
  updated_at: string;
}

export interface DashboardOverviewRecord {
  agents: AgentRecord[];
  chats: DashboardOverviewChatRecord[];
  projects: ProjectRecord[];
  workspaces: WorkspaceRecord[];
}

export interface RepositoryRecord {
  default_branch?: string | null;
  id: string;
  is_git_repository?: boolean;
  name: string;
  path: string;
  [key: string]: unknown;
}

export interface SessionRecord {
  claude_session_id?: string | null;
  id: string;
  is_worktree?: boolean;
  provider?: string | null;
  provider_session_id?: string | null;
  repository_id: string;
  status?: string;
  title: string;
  worktree_path?: string | null;
  [key: string]: unknown;
}

export interface SessionMessage {
  content: unknown;
  id: string;
  sequence_number: number | string;
  session_id: string;
}

export interface FileEntry {
  has_children: boolean;
  is_dir: boolean;
  name: string;
  path: string;
}

export interface FileReadResult {
  content: string;
  is_truncated: boolean;
  read_only_reason?: string | null;
  revision?: unknown;
  total_lines?: number;
}

export interface GitStatusFile {
  additions?: number;
  deletions?: number;
  path: string;
  staged?: boolean;
  status?: string | null;
  [key: string]: unknown;
}

export interface GitStatusResult {
  branch?: string | null;
  files: GitStatusFile[];
  is_clean?: boolean;
}

export interface GitDiffResult {
  additions: number;
  deletions: number;
  diff: string;
  file_path: string;
  is_binary: boolean;
  is_truncated: boolean;
}

export interface GitCommit {
  author_email: string;
  author_name: string;
  author_time: number;
  committer_name: string;
  committer_time: number;
  message: string;
  oid: string;
  parent_oids: string[];
  short_oid: string;
  summary: string;
}

export interface GitLogResult {
  commits: GitCommit[];
  has_more: boolean;
  total_count?: number | null;
}

export interface GitBranch {
  ahead: number;
  behind: number;
  head_oid: string;
  is_current: boolean;
  is_remote: boolean;
  name: string;
  upstream?: string | null;
}

export interface GitBranchesResult {
  current?: string | null;
  local: GitBranch[];
  remote: GitBranch[];
}

export interface GitWorktreeRecord {
  branch?: string | null;
  head_oid?: string | null;
  name: string;
  path: string;
}

export interface SessionStreamPayload {
  event: {
    event_type?: string;
    session_id?: string;
    data?: Record<string, unknown>;
    sequence?: number;
    [key: string]: unknown;
  };
  session_id: string;
}
