import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type {
  AgentRecord,
  AgentRunEventRecord,
  AgentRunLogChunk,
  AgentRunRecord,
  Company,
  CompanySnapshot,
  DaemonVersionInfo,
  DesktopBootstrapStatus,
  DesktopSettings,
  FileEntry,
  FileReadResult,
  GitBranchesResult,
  GitDiffResult,
  GitLogResult,
  GitStatusResult,
  GitWorktreeRecord,
  IssueAttachmentRecord,
  IssueCommentRecord,
  IssueRunCardUpdateRecord,
  IssueRecord,
  ProjectRecord,
  RepositoryRecord,
  RuntimeCapabilities,
  SessionMessage,
  SessionRecord,
  SessionStreamPayload,
  WorkspaceRecord,
} from "./types";

async function invokeCommand<T>(
  command: string,
  args?: Record<string, unknown>
) {
  return invoke<T>(command, args);
}

export const desktopBootstrap = () =>
  invokeCommand<DesktopBootstrapStatus>("desktop_bootstrap");

export const systemVersion = () =>
  invokeCommand<DaemonVersionInfo>("system_version");

export const systemCheckDependencies = () =>
  invokeCommand<RuntimeCapabilities>("system_check_dependencies");

export const boardListCompanies = () =>
  invokeCommand<Company[]>("board_list_companies");

export const boardCreateCompany = (params: Record<string, unknown>) =>
  invokeCommand<Company>("board_create_company", { params });

export const boardUpdateCompany = (params: Record<string, unknown>) =>
  invokeCommand<Company>("board_update_company", { params });

export const boardUpdateAgent = (params: Record<string, unknown>) =>
  invokeCommand<AgentRecord>("board_update_agent", { params });

export const boardCompanySnapshot = (companyId: string) =>
  invokeCommand<CompanySnapshot>("board_company_snapshot", {
    companyId,
  });

export const boardCreateProject = (params: Record<string, unknown>) =>
  invokeCommand<ProjectRecord>("board_create_project", { params });

export const boardDeleteProject = (projectId: string) =>
  invokeCommand<ProjectRecord>("board_delete_project", {
    projectId,
  });

export const boardCreateIssue = (params: Record<string, unknown>) =>
  invokeCommand<IssueRecord>("board_create_issue", { params });

export const boardGetIssue = (issueId: string) =>
  invokeCommand<IssueRecord>("board_get_issue", {
    issueId,
  });

export const boardUpdateIssue = (params: Record<string, unknown>) =>
  invokeCommand<IssueRecord>("board_update_issue", { params });

export const boardListIssueComments = (issueId: string) =>
  invokeCommand<IssueCommentRecord[]>("board_list_issue_comments", {
    issueId,
  });

export const boardListIssueAttachments = (issueId: string) =>
  invokeCommand<IssueAttachmentRecord[]>("board_list_issue_attachments", {
    issueId,
  });

export const boardAddIssueAttachment = (params: Record<string, unknown>) =>
  invokeCommand<IssueAttachmentRecord>("board_add_issue_attachment", {
    params,
  });

export const boardListIssueRuns = (issueId: string, limit?: number) =>
  invokeCommand<AgentRunRecord[]>("board_list_issue_runs", {
    issueId,
    limit,
  });

export const boardListIssueRunCardUpdates = (companyId: string) =>
  invokeCommand<IssueRunCardUpdateRecord[]>(
    "board_list_issue_run_card_updates",
    {
      companyId,
    }
  );

export const boardAddIssueComment = (params: Record<string, unknown>) =>
  invokeCommand<IssueCommentRecord>("board_add_issue_comment", { params });

export const boardCheckoutIssue = (issueId: string) =>
  invokeCommand<WorkspaceRecord>("board_checkout_issue", {
    issueId,
  });

export const boardApproveApproval = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("board_approve_approval", { params });

export const boardListAgentRuns = (agentId: string, limit?: number) =>
  invokeCommand<AgentRunRecord[]>("board_list_agent_runs", {
    agentId,
    limit,
  });

export const boardGetAgentRun = (runId: string) =>
  invokeCommand<AgentRunRecord>("board_get_agent_run", {
    runId,
  });

export const boardListAgentRunEvents = (
  runId: string,
  afterSeq?: number,
  limit?: number
) =>
  invokeCommand<AgentRunEventRecord[]>("board_list_agent_run_events", {
    runId,
    afterSeq,
    limit,
  });

export const boardReadAgentRunLog = (
  runId: string,
  offset = 0,
  limitBytes = 16_384
) =>
  invokeCommand<AgentRunLogChunk>("board_read_agent_run_log", {
    runId,
    offset,
    limitBytes,
  });

export const boardInvokeAgentRun = (
  agentId: string,
  issueId?: string,
  prompt?: string
) =>
  invokeCommand<AgentRunRecord>("board_invoke_agent_run", {
    agentId,
    issueId,
    prompt,
  });

export const boardCancelAgentRun = (runId: string) =>
  invokeCommand<AgentRunRecord>("board_cancel_agent_run", {
    runId,
  });

export const boardRetryAgentRun = (runId: string) =>
  invokeCommand<AgentRunRecord>("board_retry_agent_run", {
    runId,
  });

export const boardResumeAgentRun = (runId: string) =>
  invokeCommand<AgentRunRecord>("board_resume_agent_run", {
    runId,
  });

export const repositoryList = () =>
  invokeCommand<RepositoryRecord[]>("repository_list");

export const repositoryAdd = (path: string, name?: string) =>
  invokeCommand<RepositoryRecord>("repository_add", {
    path,
    name,
    isGitRepository: true,
  });

export const repositoryRemove = (id: string) =>
  invokeCommand<Record<string, unknown>>("repository_remove", { id });

export const repositoryGetSettings = (repositoryId: string) =>
  invokeCommand<Record<string, unknown>>("repository_get_settings", {
    repositoryId,
  });

export const repositoryUpdateSettings = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("repository_update_settings", {
    params,
  });

export const repositoryListFiles = (
  sessionId: string,
  relativePath = "",
  includeHidden = false
) =>
  invokeCommand<FileEntry[]>("repository_list_files", {
    sessionId,
    relativePath,
    includeHidden,
  });

export const repositoryReadFile = (
  sessionId: string,
  relativePath: string,
  maxBytes?: number
) =>
  invokeCommand<FileReadResult>("repository_read_file", {
    sessionId,
    relativePath,
    maxBytes,
  });

export const repositoryWriteFile = (
  sessionId: string,
  relativePath: string,
  content: string,
  expectedRevision?: unknown,
  force?: boolean
) =>
  invokeCommand<Record<string, unknown>>("repository_write_file", {
    sessionId,
    relativePath,
    content,
    expectedRevision,
    force,
  });

export const repositoryReplaceFileRange = (
  sessionId: string,
  relativePath: string,
  startLine: number,
  endLineExclusive: number,
  replacement: string,
  expectedRevision?: unknown,
  force?: boolean
) =>
  invokeCommand<Record<string, unknown>>("repository_replace_file_range", {
    sessionId,
    relativePath,
    startLine,
    endLineExclusive,
    replacement,
    expectedRevision,
    force,
  });

export const sessionList = (repositoryId: string) =>
  invokeCommand<SessionRecord[]>("session_list", {
    repositoryId,
  });

export const sessionCreate = (params: Record<string, unknown>) =>
  invokeCommand<SessionRecord>("session_create", { params });

export const sessionGet = (id: string) =>
  invokeCommand<SessionRecord>("session_get", { id });

export const sessionUpdate = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("session_update", { params });

export const messageList = (sessionId: string) =>
  invokeCommand<SessionMessage[]>("message_list", {
    sessionId,
  });

export const agentSend = (
  sessionId: string,
  content: string,
  provider?: string,
  permissionMode?: string
) =>
  invokeCommand<Record<string, unknown>>("agent_send", {
    sessionId,
    content,
    provider,
    permissionMode,
  });

export const agentStatus = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("agent_status", {
    sessionId,
  });

export const agentStop = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("agent_stop", {
    sessionId,
  });

export const claudeSend = (
  sessionId: string,
  content: string,
  permissionMode?: string
) =>
  invokeCommand<Record<string, unknown>>("claude_send", {
    sessionId,
    content,
    permissionMode,
  });

export const claudeStatus = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("claude_status", {
    sessionId,
  });

export const claudeStop = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("claude_stop", {
    sessionId,
  });

export const terminalRun = (
  sessionId: string,
  command: string,
  workingDir?: string
) =>
  invokeCommand<Record<string, unknown>>("terminal_run", {
    sessionId,
    command,
    workingDir,
  });

export const terminalStatus = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("terminal_status", {
    sessionId,
  });

export const terminalStop = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("terminal_stop", {
    sessionId,
  });

export const gitStatus = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitStatusResult>("git_status", {
    sessionId,
    repositoryId,
  });

export const gitLog = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitLogResult>("git_log", {
    sessionId,
    repositoryId,
  });

export const gitBranches = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitBranchesResult>("git_branches", {
    sessionId,
    repositoryId,
  });

export const gitWorktrees = (
  sessionId?: string,
  repositoryId?: string,
  path?: string
) =>
  invokeCommand<GitWorktreeRecord[]>("git_worktrees", {
    sessionId,
    repositoryId,
    path,
  });

export const gitDiffFile = (
  filePath: string,
  sessionId?: string,
  repositoryId?: string,
  path?: string,
  maxLines?: number
) =>
  invokeCommand<GitDiffResult>("git_diff_file", {
    filePath,
    sessionId,
    repositoryId,
    path,
    maxLines,
  });

export const gitStage = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_stage", {
    paths,
    sessionId,
  });

export const gitUnstage = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_unstage", {
    paths,
    sessionId,
  });

export const gitDiscard = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_discard", {
    paths,
    sessionId,
  });

export const gitCommit = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("git_commit", { params });

export const gitPush = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("git_push", { params });

export const settingsGet = () => invokeCommand<DesktopSettings>("settings_get");

export const settingsUpdate = (settings: DesktopSettings) =>
  invokeCommand<DesktopSettings>("settings_update", { settings });

export const desktopPickRepositoryDirectory = () =>
  invokeCommand<string | null>("desktop_pick_repository_directory");

export const desktopPickFile = () =>
  invokeCommand<string | null>("desktop_pick_file");

export const desktopRevealInFinder = (path: string) =>
  invokeCommand<void>("desktop_reveal_in_finder", { path });

export const desktopOpenExternal = (url: string) =>
  invokeCommand<void>("desktop_open_external", { url });

export const sessionSubscribe = (sessionId: string) =>
  invokeCommand<void>("session_subscribe", { sessionId });

export const sessionUnsubscribe = (sessionId: string) =>
  invokeCommand<void>("session_unsubscribe", { sessionId });

export const listenToSessionEvents = (
  handler: (payload: SessionStreamPayload) => void
) =>
  listen<SessionStreamPayload>("daemon-session-event", (event) =>
    handler(event.payload)
  );

export const listenToSessionStreamErrors = (
  handler: (payload: { session_id: string; message: string }) => void
) =>
  listen<{ session_id: string; message: string }>(
    "daemon-session-stream-error",
    (event) => handler(event.payload)
  );
