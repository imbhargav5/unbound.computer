import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type {
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
  RepositoryRecord,
  SessionMessage,
  SessionRecord,
  SessionStreamPayload,
} from "./types";

async function invokeCommand<T>(command: string, args?: Record<string, unknown>) {
  return invoke<T>(command, args);
}

export const desktopBootstrap = () =>
  invokeCommand<DesktopBootstrapStatus>("desktop_bootstrap");

export const systemVersion = () => invokeCommand<DaemonVersionInfo>("system_version");

export const systemCheckDependencies = () =>
  invokeCommand<Record<string, unknown>>("system_check_dependencies");

export const boardListCompanies = () =>
  invokeCommand<Company[]>("board_list_companies");

export const boardCreateCompany = (params: Record<string, unknown>) =>
  invokeCommand<Company>("board_create_company", { params });

export const boardCompanySnapshot = (companyId: string) =>
  invokeCommand<CompanySnapshot>("board_company_snapshot", {
    company_id: companyId,
  });

export const boardCreateProject = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("board_create_project", { params });

export const boardCreateIssue = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("board_create_issue", { params });

export const boardUpdateIssue = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("board_update_issue", { params });

export const boardApproveApproval = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("board_approve_approval", { params });

export const repositoryList = () =>
  invokeCommand<RepositoryRecord[]>("repository_list");

export const repositoryAdd = (path: string, name?: string) =>
  invokeCommand<RepositoryRecord>("repository_add", {
    path,
    name,
    is_git_repository: true,
  });

export const repositoryRemove = (id: string) =>
  invokeCommand<Record<string, unknown>>("repository_remove", { id });

export const repositoryGetSettings = (repositoryId: string) =>
  invokeCommand<Record<string, unknown>>("repository_get_settings", {
    repository_id: repositoryId,
  });

export const repositoryUpdateSettings = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("repository_update_settings", { params });

export const repositoryListFiles = (
  sessionId: string,
  relativePath = "",
  includeHidden = false
) =>
  invokeCommand<FileEntry[]>("repository_list_files", {
    session_id: sessionId,
    relative_path: relativePath,
    include_hidden: includeHidden,
  });

export const repositoryReadFile = (
  sessionId: string,
  relativePath: string,
  maxBytes?: number
) =>
  invokeCommand<FileReadResult>("repository_read_file", {
    session_id: sessionId,
    relative_path: relativePath,
    max_bytes: maxBytes,
  });

export const repositoryWriteFile = (
  sessionId: string,
  relativePath: string,
  content: string,
  expectedRevision?: unknown,
  force?: boolean
) =>
  invokeCommand<Record<string, unknown>>("repository_write_file", {
    session_id: sessionId,
    relative_path: relativePath,
    content,
    expected_revision: expectedRevision,
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
    session_id: sessionId,
    relative_path: relativePath,
    start_line: startLine,
    end_line_exclusive: endLineExclusive,
    replacement,
    expected_revision: expectedRevision,
    force,
  });

export const sessionList = (repositoryId: string) =>
  invokeCommand<SessionRecord[]>("session_list", {
    repository_id: repositoryId,
  });

export const sessionCreate = (params: Record<string, unknown>) =>
  invokeCommand<SessionRecord>("session_create", { params });

export const sessionGet = (id: string) =>
  invokeCommand<SessionRecord>("session_get", { id });

export const sessionUpdate = (params: Record<string, unknown>) =>
  invokeCommand<Record<string, unknown>>("session_update", { params });

export const messageList = (sessionId: string) =>
  invokeCommand<SessionMessage[]>("message_list", {
    session_id: sessionId,
  });

export const claudeSend = (
  sessionId: string,
  content: string,
  permissionMode?: string
) =>
  invokeCommand<Record<string, unknown>>("claude_send", {
    session_id: sessionId,
    content,
    permission_mode: permissionMode,
  });

export const claudeStatus = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("claude_status", {
    session_id: sessionId,
  });

export const claudeStop = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("claude_stop", {
    session_id: sessionId,
  });

export const terminalRun = (
  sessionId: string,
  command: string,
  workingDir?: string
) =>
  invokeCommand<Record<string, unknown>>("terminal_run", {
    session_id: sessionId,
    command,
    working_dir: workingDir,
  });

export const terminalStatus = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("terminal_status", {
    session_id: sessionId,
  });

export const terminalStop = (sessionId: string) =>
  invokeCommand<Record<string, unknown>>("terminal_stop", {
    session_id: sessionId,
  });

export const gitStatus = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitStatusResult>("git_status", {
    session_id: sessionId,
    repository_id: repositoryId,
  });

export const gitLog = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitLogResult>("git_log", {
    session_id: sessionId,
    repository_id: repositoryId,
  });

export const gitBranches = (sessionId?: string, repositoryId?: string) =>
  invokeCommand<GitBranchesResult>("git_branches", {
    session_id: sessionId,
    repository_id: repositoryId,
  });

export const gitDiffFile = (
  filePath: string,
  sessionId?: string,
  repositoryId?: string,
  path?: string,
  maxLines?: number
) =>
  invokeCommand<GitDiffResult>("git_diff_file", {
    file_path: filePath,
    session_id: sessionId,
    repository_id: repositoryId,
    path,
    max_lines: maxLines,
  });

export const gitStage = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_stage", {
    paths,
    session_id: sessionId,
  });

export const gitUnstage = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_unstage", {
    paths,
    session_id: sessionId,
  });

export const gitDiscard = (paths: string[], sessionId?: string) =>
  invokeCommand<Record<string, unknown>>("git_discard", {
    paths,
    session_id: sessionId,
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

export const desktopRevealInFinder = (path: string) =>
  invokeCommand<void>("desktop_reveal_in_finder", { path });

export const desktopOpenExternal = (url: string) =>
  invokeCommand<void>("desktop_open_external", { url });

export const sessionSubscribe = (sessionId: string) =>
  invokeCommand<void>("session_subscribe", { session_id: sessionId });

export const sessionUnsubscribe = (sessionId: string) =>
  invokeCommand<void>("session_unsubscribe", { session_id: sessionId });

export const listenToSessionEvents = (
  handler: (payload: SessionStreamPayload) => void
) => listen<SessionStreamPayload>("daemon-session-event", (event) => handler(event.payload));

export const listenToSessionStreamErrors = (
  handler: (payload: { session_id: string; message: string }) => void
) =>
  listen<{ session_id: string; message: string }>(
    "daemon-session-stream-error",
    (event) => handler(event.payload)
  );
