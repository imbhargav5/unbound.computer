import { Terminal } from "@xterm/xterm";
import {
  type FormEvent,
  type MouseEvent,
  type PointerEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
  type RefObject,
  startTransition,
  useDeferredValue,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type WheelEvent,
} from "react";
import { ActivityRouteView } from "../features/activity/activityRouteView";
import { IssuesListView } from "../features/issues/issuesListView";
import { ProjectsRouteView } from "../features/projects/projectsRouteView";
import {
  DashboardBreadcrumbs,
  DetailRow,
  MetricCard,
  RoutePlaceholder,
  SummaryPill,
} from "../features/shared/routePrimitives";
import { StatsRouteView } from "../features/stats/statsRouteView";
import {
  agentSend,
  agentStop,
  boardAddIssueAttachment,
  boardApproveApproval,
  boardCancelAgentRun,
  boardCompanySnapshot,
  boardCreateAgent,
  boardCreateCompany,
  boardCreateIssue,
  boardCreateProject,
  boardDashboardOverview,
  boardDeleteProject,
  boardGetAgentRun,
  boardGetIssue,
  boardListAgentLiveRunCounts,
  boardListAgentRunEvents,
  boardListAgentRuns,
  boardListCompanies,
  boardListIssueAttachments,
  boardListIssueComments,
  boardListIssueRunCardUpdates,
  boardListIssueRuns,
  boardReadAgentRunLog,
  boardResumeAgentRun,
  boardRetryAgentRun,
  boardUpdateAgent,
  boardUpdateCompany,
  boardUpdateIssue,
  boardUpdateProject,
  desktopBootstrap,
  desktopOpenExternal,
  desktopPickFile,
  desktopPickRepositoryDirectory,
  desktopRevealInFinder,
  gitBranches,
  gitCommit,
  gitDiffFile,
  gitDiscard,
  gitLog,
  gitPush,
  gitStage,
  gitStatus,
  gitUnstage,
  gitWorktrees,
  listenToSessionEvents,
  listenToSessionStreamErrors,
  repositoryList,
  repositoryListFiles,
  repositoryReadFile,
  sessionList,
  settingsGet,
  settingsUpdate,
  spaceGetCurrent,
  systemCheckDependencies,
  terminalRun,
  terminalStop,
} from "../lib/api";
import {
  type BirdsEyeFocusChangeCause,
  playBirdsEyeFocusSound,
  shouldPlayBirdsEyeFocusSound,
} from "../lib/birdsEyeFocusSound";
import {
  buildConversationTimeline,
  type ConversationQuestion,
  type ConversationRow,
  type ConversationSubAgent,
  type ConversationTodoItem,
  type ConversationTool,
} from "../lib/conversationTimeline";
import type {
  SessionCompletionSummary,
  SessionConversationCommandBlock,
  SessionConversationNoteBlock,
  SessionConversationRow,
} from "../lib/sessionConversation";
import {
  DesktopSessionStateManager,
  useDesktopSessionLiveState,
} from "../lib/sessionLiveState";
import type {
  AgentLiveRunCountRecord,
  AgentRecord,
  AgentRunEventRecord,
  AgentRunRecord,
  ApprovalRecord,
  BirdsEyeCanvasCompanyState,
  Company,
  CompanySnapshot,
  CurrentSpaceScope,
  DashboardOverviewChatRecord,
  DashboardOverviewRecord,
  DesktopBootstrapStatus,
  DesktopSettings,
  FileEntry,
  FileReadResult,
  GitBranchesResult,
  GitDiffResult,
  GitLogResult,
  GitStatusFile,
  GitStatusResult,
  GitWorktreeRecord,
  GoalRecord,
  IssueAttachmentRecord,
  IssueCommentRecord,
  IssueRecord,
  IssueRunCardUpdateRecord,
  ProjectRecord,
  RepositoryRecord,
  RuntimeCapabilities,
  SessionMessage,
  SessionRecord,
  SessionStreamPayload,
  WorkspaceRecord,
} from "../lib/types";

type AppScreen =
  | "dashboard"
  | "agents"
  | "issues"
  | "approvals"
  | "projects"
  | "stats"
  | "activity"
  | "costs"
  | "companySettings"
  | "appSettings";

const emptyAgentRecords: AgentRecord[] = [];
const emptyApprovalRecords: ApprovalRecord[] = [];
const emptyGoalRecords: GoalRecord[] = [];
const emptyIssueRecords: IssueRecord[] = [];
const emptyProjectRecords: ProjectRecord[] = [];
const emptyWorkspaceRecords: WorkspaceRecord[] = [];
const emptyDashboardOverviewChats: DashboardOverviewChatRecord[] = [];

type SettingsSection = "general" | "appearance" | "notifications" | "privacy";

type ThemeMode = "system" | "light" | "dark";
type FontSizePreset = "small" | "medium" | "large";
type DesktopPreferredViewValue =
  | "dashboard"
  | "stats"
  | "activity"
  | "costs"
  | "settings";
type IssuesListTab = "new" | "all";
type IssuesRouteMode = "list" | "detail";
type IssueDetailTab = "conversation" | "runs" | "queued";
type AgentsRouteMode = "dashboard" | "configuration" | "runs";
type IssueDialogMode = "conversation" | "queuedMessage";

interface IssueLinkedRun {
  label: string | null;
  run: AgentRunRecord;
}

type BoardRootLayout = "companyDashboard" | "settings";
type WorkspaceCenterTab = "conversation" | "runs" | "terminal" | "preview";
type WorkspaceSidebarTab = "changes" | "files" | "commits" | "issue";
type CompanyContextMenuScreen = "dashboard" | "issues" | "companySettings";
type CompanyContextMenuIconKey =
  | CompanyContextMenuScreen
  | "activity"
  | "agents"
  | "approvals"
  | "costs"
  | "stats";

interface CompanyContextMenuState {
  agents: AgentRecord[];
  companyId: string;
  companyName: string;
  isLoadingAgents: boolean;
  x: number;
  y: number;
}

interface DashboardCanvasOffset {
  x: number;
  y: number;
}

type DashboardProjectGrouping = "status" | "priority" | "assignee";
type IssueWorkspaceTargetMode = "main" | "new_worktree" | "existing_worktree";
type ProjectDefaultNewChatArea = "repo_root" | "new_worktree";

interface IssueRuntimeDraft {
  command: string;
  enableChrome: boolean;
  model: string;
  planMode: boolean;
  skipPermissions: boolean;
  thinkingEffort: string;
}

interface DashboardProjectColumn {
  createDefaults: CreateIssueDialogDefaults;
  id: string;
  issues: IssueRecord[];
  label: string;
}

interface DashboardProjectBoardLayout {
  boardId: string;
  columns: DashboardProjectColumn[];
  grouping: DashboardProjectGrouping;
  isDefaultView: boolean;
  issueCount: number;
  project: ProjectRecord;
  viewId: string;
  viewName: string;
  width: number;
}

interface DashboardProjectColumnLayout {
  boards: DashboardProjectBoardLayout[];
  height: number;
  left: number;
  project: ProjectRecord;
  top: number;
  width: number;
}

interface SelectOption<T extends string> {
  label: string;
  value: T;
}

const projectDefaultNewChatAreaOptions: Array<
  SelectOption<ProjectDefaultNewChatArea>
> = [
  { label: "Repo root", value: "repo_root" },
  { label: "New worktree", value: "new_worktree" },
];

interface CreateIssueDialogDefaults {
  command?: string;
  dialogMode?: IssueDialogMode;
  enableChrome?: boolean;
  model?: string;
  parentId?: string;
  planMode?: boolean;
  priority?: string;
  projectId?: string;
  skipPermissions?: boolean;
  status?: string;
  thinkingEffort?: string;
  workspaceTargetMode?: IssueWorkspaceTargetMode;
  workspaceWorktreeBranch?: string;
  workspaceWorktreeName?: string;
  workspaceWorktreePath?: string;
}

interface DashboardProjectViewDraft {
  grouping: DashboardProjectGrouping;
  name: string;
}

interface IssueEditDraft extends IssueRuntimeDraft {
  assigneeAgentId: string;
  description: string;
  parentId: string;
  priority: string;
  projectId: string;
  status: string;
  title: string;
  workspaceTargetMode: IssueWorkspaceTargetMode;
  workspaceWorktreeBranch: string;
  workspaceWorktreeName: string;
  workspaceWorktreePath: string;
}

interface ProjectWorktreeState {
  errorMessage: string | null;
  hasLoaded?: boolean;
  isLoading: boolean;
  repoPath?: string | null;
  worktrees: GitWorktreeRecord[];
}

interface IssueAttachmentDraft {
  name: string;
  path: string;
}

interface AgentConfigEnvVarDraft {
  id: string;
  key: string;
  mode: "plain" | "secret";
  value: string;
}

interface AgentConfigDraft {
  adapterType: string;
  bootstrapPrompt: string;
  canCreateAgents: boolean;
  capabilities: string;
  command: string;
  enableChrome: boolean;
  envVars: AgentConfigEnvVarDraft[];
  extraArgs: string;
  instructionsPath: string;
  interruptGraceSec: string;
  maxTurns: string;
  model: string;
  monthlyBudget: string;
  name: string;
  promptTemplate: string;
  skipPermissions: boolean;
  thinkingEffort: string;
  timeoutSec: string;
  title: string;
  workingDirectory: string;
}

type ActivityFeedTarget = { kind: "issue"; issueId: string };

interface ActivityFeedItem {
  id: string;
  subtitle: string;
  target: ActivityFeedTarget;
  timestamp: Date;
  title: string;
  trailingLabel: string;
}

interface DashboardBreadcrumbItem {
  label: string;
  onClick?: () => void;
}

interface BirdsEyeCodeImpactSummary {
  additions: number;
  deletions: number;
  filesChanged: number;
  state: "loading" | "ready" | "error";
}

interface BirdsEyeChatNode {
  agentLabel: string;
  chat: DashboardOverviewChatRecord;
  createDefaults: CreateIssueDialogDefaults;
  folderRowId: string;
  kind: "chat";
  lastActivityAt: string | null;
  projectId: string;
  rowId: string;
  runStatus: string | null;
  runSummary: string | null;
  sessionId: string | null;
  title: string;
}

interface BirdsEyeFolderNode {
  chatCount: number;
  chats: BirdsEyeChatNode[];
  createDefaults: CreateIssueDialogDefaults;
  folderKey: string;
  folderType: "repo_root" | "worktree" | "pending_worktree";
  kind: "folder";
  label: string;
  lastActivityAt: string | null;
  liveRunCount: number;
  path: string | null;
  projectId: string;
  rowId: string;
  secondaryLabel: string | null;
}

interface BirdsEyeProjectNode {
  chatCount: number;
  createDefaults: CreateIssueDialogDefaults;
  folderCount: number;
  folders: BirdsEyeFolderNode[];
  kind: "project";
  label: string;
  lastActivityAt: string | null;
  liveRunCount: number;
  project: ProjectRecord;
  repoPath: string | null;
  rowId: string;
}

type BirdsEyeTreeNode =
  | BirdsEyeProjectNode
  | BirdsEyeFolderNode
  | BirdsEyeChatNode;

interface BirdsEyeVisibleRow {
  depth: number;
  hasChildren: boolean;
  isExpanded: boolean;
  node: BirdsEyeTreeNode;
  parentRowId: string | null;
  rowId: string;
}

interface BirdsEyeTreeModel {
  chatByIssueId: Map<string, BirdsEyeChatNode>;
  projects: BirdsEyeProjectNode[];
  rowById: Map<string, BirdsEyeTreeNode>;
  rowIds: Set<string>;
}

interface BirdsEyeQuickCreateDraft {
  command: string;
  enableChrome: boolean;
  model: string;
  planMode: boolean;
  priority: string;
  projectId: string;
  skipPermissions: boolean;
  status: string;
  thinkingEffort: string;
  workspaceTargetMode: IssueWorkspaceTargetMode;
  workspaceWorktreeBranch: string;
  workspaceWorktreeName: string;
  workspaceWorktreePath: string;
}

interface BirdsEyeQuickCreateState {
  draft: BirdsEyeQuickCreateDraft;
  errorMessage: string | null;
  folderRowId: string | null;
  isOpen: boolean;
  isSaving: boolean;
  sourceRowId: string | null;
  title: string;
}

type BirdsEyeIssueLike = Pick<
  IssueRecord,
  | "id"
  | "project_id"
  | "title"
  | "status"
  | "priority"
  | "assignee_agent_id"
  | "assignee_adapter_overrides"
  | "execution_workspace_settings"
  | "identifier"
  | "created_at"
  | "updated_at"
>;

interface BirdsEyeCanvasFocusTarget {
  issueId: string | null;
  kind: "repo" | "worktree" | "chat" | "tile";
  projectId: string;
  worktreeKey: string | null;
}

interface BirdsEyeWorktreeTileState {
  activeIssueId: string | null;
  issueIds: string[];
  lruIssueIds: string[];
}

interface BirdsEyeCanvasState {
  focusedTarget: BirdsEyeCanvasFocusTarget | null;
  repoRegions: Record<
    string,
    {
      page: number;
      x: number;
      y: number;
    }
  >;
  viewport: {
    x: number;
    y: number;
    zoomIndex: number;
  };
  worktreeTiles: Record<string, BirdsEyeWorktreeTileState>;
}

interface BirdsEyeCanvasWorktreeBoardModel {
  chats: BirdsEyeChatNode[];
  folder: BirdsEyeFolderNode;
  height: number;
  key: string;
  pageIndex: number;
  tileState: BirdsEyeWorktreeTileState;
  width: number;
  x: number;
  y: number;
}

interface BirdsEyeCanvasRepoRegionModel {
  height: number;
  page: number;
  project: BirdsEyeProjectNode;
  totalPages: number;
  visibleWorktrees: BirdsEyeCanvasWorktreeBoardModel[];
  width: number;
  x: number;
  y: number;
}

function createDefaultBirdsEyeCanvasState(): BirdsEyeCanvasState {
  return {
    focusedTarget: null,
    repoRegions: {},
    viewport: {
      x: defaultBirdsEyeCanvasOffset.x,
      y: defaultBirdsEyeCanvasOffset.y,
      zoomIndex: defaultBirdsEyeCanvasZoomIndex,
    },
    worktreeTiles: {},
  };
}

function createEmptyBirdsEyeWorktreeTileState(): BirdsEyeWorktreeTileState {
  return {
    activeIssueId: null,
    issueIds: [],
    lruIssueIds: [],
  };
}

function parseBirdsEyeCanvasState(
  state: BirdsEyeCanvasCompanyState | null | undefined,
): BirdsEyeCanvasState {
  const fallback = createDefaultBirdsEyeCanvasState();
  if (!state) {
    return fallback;
  }

  return {
    focusedTarget: state.focused_target
      ? {
          kind: state.focused_target.kind,
          issueId: state.focused_target.issue_id ?? null,
          projectId: state.focused_target.project_id,
          worktreeKey: state.focused_target.worktree_key ?? null,
        }
      : null,
    repoRegions: Object.fromEntries(
      Object.entries(state.repo_regions ?? {}).map(([projectId, region]) => [
        projectId,
        {
          page: Math.max(0, Math.floor(region?.page ?? 0)),
          x: typeof region?.x === "number" ? region.x : 0,
          y: typeof region?.y === "number" ? region.y : 0,
        },
      ]),
    ),
    viewport: {
      x:
        typeof state.viewport?.x === "number"
          ? state.viewport.x
          : fallback.viewport.x,
      y:
        typeof state.viewport?.y === "number"
          ? state.viewport.y
          : fallback.viewport.y,
      zoomIndex:
        typeof state.viewport?.zoom_index === "number"
          ? Math.max(0, Math.floor(state.viewport.zoom_index))
          : fallback.viewport.zoomIndex,
    },
    worktreeTiles: Object.fromEntries(
      Object.entries(state.worktree_tiles ?? {}).map(
        ([worktreeKey, tileState]) => [
          worktreeKey,
          {
            activeIssueId: tileState?.active_issue_id ?? null,
            issueIds: Array.isArray(tileState?.issue_ids)
              ? tileState.issue_ids.filter(
                  (issueId): issueId is string => typeof issueId === "string",
                )
              : [],
            lruIssueIds: Array.isArray(tileState?.lru_issue_ids)
              ? tileState.lru_issue_ids.filter(
                  (issueId): issueId is string => typeof issueId === "string",
                )
              : [],
          },
        ],
      ),
    ),
  };
}

function serializeBirdsEyeCanvasState(
  state: BirdsEyeCanvasState,
): BirdsEyeCanvasCompanyState {
  return {
    focused_target: state.focusedTarget
      ? {
          kind: state.focusedTarget.kind,
          issue_id: state.focusedTarget.issueId,
          project_id: state.focusedTarget.projectId,
          worktree_key: state.focusedTarget.worktreeKey,
        }
      : null,
    repo_regions: Object.fromEntries(
      Object.entries(state.repoRegions).map(([projectId, region]) => [
        projectId,
        {
          page: region.page,
          x: region.x,
          y: region.y,
        },
      ]),
    ),
    viewport: {
      x: state.viewport.x,
      y: state.viewport.y,
      zoom_index: state.viewport.zoomIndex,
    },
    worktree_tiles: Object.fromEntries(
      Object.entries(state.worktreeTiles).map(([worktreeKey, tileState]) => [
        worktreeKey,
        {
          active_issue_id: tileState.activeIssueId,
          issue_ids: tileState.issueIds,
          lru_issue_ids: tileState.lruIssueIds,
        },
      ]),
    ),
  };
}

function birdsEyeFocusTargetKey(target: BirdsEyeCanvasFocusTarget | null) {
  if (!target) {
    return null;
  }

  switch (target.kind) {
    case "repo":
      return `repo:${target.projectId}`;
    case "worktree":
      return `worktree:${target.projectId}:${target.worktreeKey ?? ""}`;
    case "chat":
      return `chat:${target.issueId ?? ""}`;
    case "tile":
      return `tile:${target.worktreeKey ?? ""}:${target.issueId ?? ""}`;
  }
}

function normalizeGitWorktreeRecords(value: unknown): GitWorktreeRecord[] {
  if (Array.isArray(value)) {
    return value.filter(
      (entry): entry is GitWorktreeRecord =>
        Boolean(entry) &&
        typeof entry === "object" &&
        typeof (entry as GitWorktreeRecord).path === "string" &&
        typeof (entry as GitWorktreeRecord).name === "string",
    );
  }

  if (
    value &&
    typeof value === "object" &&
    Array.isArray((value as { worktrees?: unknown }).worktrees)
  ) {
    return normalizeGitWorktreeRecords(
      (value as { worktrees: unknown }).worktrees,
    );
  }

  return [];
}

function useProjectWorktrees(repoPath: string | null): ProjectWorktreeState {
  const [worktrees, setWorktrees] = useState<GitWorktreeRecord[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!repoPath) {
      setWorktrees([]);
      setIsLoading(false);
      setErrorMessage(null);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setErrorMessage(null);

    void gitWorktrees(undefined, undefined, repoPath)
      .then((nextWorktrees) => {
        if (cancelled) {
          return;
        }
        setWorktrees(normalizeGitWorktreeRecords(nextWorktrees));
      })
      .catch((error) => {
        if (cancelled) {
          return;
        }
        setWorktrees([]);
        setErrorMessage(error instanceof Error ? error.message : String(error));
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [repoPath]);

  return {
    worktrees,
    isLoading,
    errorMessage,
  };
}

function emptyProjectWorktreeState(): ProjectWorktreeState {
  return {
    errorMessage: null,
    hasLoaded: false,
    isLoading: false,
    repoPath: null,
    worktrees: [],
  };
}

function useDashboardProjectWorktrees(
  projects: ProjectRecord[],
  requestedProjectIds: string[],
) {
  const [stateByProjectId, setStateByProjectId] = useState<
    Record<string, ProjectWorktreeState>
  >({});
  const requestedProjectIdSet = useMemo(
    () => new Set(requestedProjectIds),
    [requestedProjectIds],
  );
  const requestedRepoEntries = useMemo(
    () =>
      projects
        .map((project) => ({
          projectId: project.id,
          repoPath: project.primary_workspace?.cwd?.trim() ?? "",
        }))
        .filter(
          (entry) =>
            entry.repoPath.length > 0 &&
            requestedProjectIdSet.has(entry.projectId),
        ),
    [projects, requestedProjectIdSet],
  );
  const requestedRepoKey = requestedRepoEntries
    .map((entry) => `${entry.projectId}:${entry.repoPath}`)
    .join("|");

  useEffect(() => {
    setStateByProjectId((current) => {
      const next: Record<string, ProjectWorktreeState> = {};

      for (const project of projects) {
        next[project.id] = current[project.id] ?? emptyProjectWorktreeState();
      }

      return next;
    });
  }, [projects]);

  const pendingRepoEntries = useMemo(
    () =>
      requestedRepoEntries.filter((entry) => {
        const current = stateByProjectId[entry.projectId];
        return (
          !current ||
          current.repoPath !== entry.repoPath ||
          !(current.hasLoaded || current.isLoading)
        );
      }),
    [requestedRepoEntries, stateByProjectId],
  );
  const pendingRepoKey = pendingRepoEntries
    .map((entry) => `${entry.projectId}:${entry.repoPath}`)
    .join("|");

  useEffect(() => {
    if (pendingRepoEntries.length === 0) {
      return;
    }

    let cancelled = false;
    setStateByProjectId((current) => {
      const next = { ...current };

      for (const entry of pendingRepoEntries) {
        const previous = next[entry.projectId] ?? emptyProjectWorktreeState();
        next[entry.projectId] = {
          ...previous,
          errorMessage: null,
          hasLoaded: false,
          isLoading: true,
          repoPath: entry.repoPath,
          worktrees:
            previous.repoPath === entry.repoPath ? previous.worktrees : [],
        };
      }

      return next;
    });

    void Promise.allSettled(
      pendingRepoEntries.map(async (entry) => ({
        projectId: entry.projectId,
        worktrees: normalizeGitWorktreeRecords(
          await gitWorktrees(undefined, undefined, entry.repoPath),
        ),
      })),
    ).then((results) => {
      if (cancelled) {
        return;
      }

      setStateByProjectId((current) => {
        const next = { ...current };

        results.forEach((result, index) => {
          const entry = pendingRepoEntries[index];
          if (!entry) {
            return;
          }

          if (result.status === "fulfilled") {
            next[entry.projectId] = {
              errorMessage: null,
              hasLoaded: true,
              isLoading: false,
              repoPath: entry.repoPath,
              worktrees: result.value.worktrees,
            };
            return;
          }

          next[entry.projectId] = {
            errorMessage:
              result.reason instanceof Error
                ? result.reason.message
                : String(result.reason),
            hasLoaded: true,
            isLoading: false,
            repoPath: entry.repoPath,
            worktrees: [],
          };
        });

        return next;
      });
    });

    return () => {
      cancelled = true;
    };
  }, [
    pendingRepoEntries,
    pendingRepoKey,
    requestedRepoEntries,
    requestedRepoKey,
  ]);

  return stateByProjectId;
}

function parseIssueExecutionWorkspaceSettings(value: unknown) {
  const record =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : undefined;
  const modeValue = record?.mode;
  const mode =
    modeValue === "new_worktree" || modeValue === "existing_worktree"
      ? modeValue
      : "main";

  return {
    workspaceTargetMode: mode as IssueWorkspaceTargetMode,
    workspaceWorktreePath:
      typeof record?.worktree_path === "string" ? record.worktree_path : "",
    workspaceWorktreeBranch:
      typeof record?.worktree_branch === "string" ? record.worktree_branch : "",
    workspaceWorktreeName:
      typeof record?.worktree_name === "string" ? record.worktree_name : "",
  };
}

function defaultIssueRuntimeCommandForProvider(
  provider: AgentCliProvider,
  dependencyCheck: RuntimeCapabilities | null,
) {
  if (provider === "codex") {
    return dependencyCheck?.cli.codex.path?.trim() || "codex";
  }

  return dependencyCheck?.cli.claude.path?.trim() || "claude";
}

function createDefaultIssueRuntimeDraft(
  dependencyCheck: RuntimeCapabilities | null,
): IssueRuntimeDraft {
  const defaultProvider =
    dependencyCheck?.cli.claude.installed ||
    !dependencyCheck?.cli.codex.installed
      ? "claude"
      : "codex";

  return {
    command: defaultIssueRuntimeCommandForProvider(
      defaultProvider,
      dependencyCheck,
    ),
    model: "default",
    thinkingEffort: "auto",
    planMode: false,
    enableChrome: false,
    skipPermissions: false,
  };
}

function issueDialogDefaultsFromRuntimeDraft(
  runtimeDraft: Pick<
    IssueRuntimeDraft,
    | "command"
    | "enableChrome"
    | "model"
    | "planMode"
    | "skipPermissions"
    | "thinkingEffort"
  >,
): IssueRuntimeDraft {
  return {
    command: runtimeDraft.command,
    enableChrome: runtimeDraft.enableChrome,
    model: runtimeDraft.model,
    planMode: runtimeDraft.planMode,
    skipPermissions: runtimeDraft.skipPermissions,
    thinkingEffort: runtimeDraft.thinkingEffort,
  };
}

function createBirdsEyeQuickCreateState(
  dependencyCheck: RuntimeCapabilities | null,
): BirdsEyeQuickCreateState {
  const runtimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);
  return {
    draft: {
      ...issueDialogDefaultsFromRuntimeDraft(runtimeDraft),
      priority: "medium",
      projectId: "",
      status: "backlog",
      workspaceTargetMode: "main",
      workspaceWorktreeBranch: "",
      workspaceWorktreeName: "",
      workspaceWorktreePath: "",
    },
    errorMessage: null,
    folderRowId: null,
    isOpen: false,
    isSaving: false,
    sourceRowId: null,
    title: "",
  };
}

function createDefaultExecutorParams(
  companyId: string,
  dependencyCheck: RuntimeCapabilities | null,
) {
  const runtimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);

  return {
    company_id: companyId,
    name: "Default Executor",
    role: "ceo",
    title: "Default Executor",
    icon: "sparkles",
    adapter_type: "process",
    adapter_config: {
      command: runtimeDraft.command,
      model: runtimeDraft.model,
      thinkingEffort: runtimeDraft.thinkingEffort,
      reasoningEffort: runtimeDraft.thinkingEffort,
      permissionMode: "default",
      enableChrome: runtimeDraft.enableChrome,
      skipPermissions: runtimeDraft.skipPermissions,
    },
    runtime_config: {
      heartbeat: {
        enabled: true,
        intervalSec: 3600,
        wakeOnDemand: true,
        cooldownSec: 10,
        maxConcurrentRuns: 1,
      },
    },
  };
}

function parseIssueAdapterOverrides(value: unknown): IssueRuntimeDraft {
  const record =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : undefined;
  const command = stringFromUnknown(record?.command, "claude");
  const model = stringFromUnknown(record?.model, "default");
  const provider = detectAgentCliProvider(command, model);

  return {
    command,
    model,
    thinkingEffort: stringFromUnknown(
      record?.thinkingEffort ?? record?.reasoningEffort,
      "auto",
    ),
    planMode:
      stringFromUnknown(record?.permissionMode) === "plan" ||
      booleanFromUnknown(record?.planMode),
    enableChrome: booleanFromUnknown(record?.enableChrome),
    skipPermissions: booleanFromUnknown(record?.skipPermissions),
  };
}

function issueAdapterOverridesFromDraft(
  draft: Pick<
    IssueRuntimeDraft,
    | "command"
    | "enableChrome"
    | "model"
    | "planMode"
    | "skipPermissions"
    | "thinkingEffort"
  >,
) {
  const command = normalizeOptionalDraftString(draft.command) ?? "claude";
  const model = normalizeOptionalDraftString(draft.model) ?? "default";
  const thinkingEffort =
    normalizeOptionalDraftString(draft.thinkingEffort) ?? "auto";
  const provider = detectAgentCliProvider(command, model);

  return {
    command,
    model,
    thinkingEffort,
    reasoningEffort: thinkingEffort,
    enableChrome: draft.enableChrome,
    skipPermissions: draft.skipPermissions,
    permissionMode:
      provider === "claude" && draft.planMode ? "plan" : "default",
  };
}

function issueExecutionWorkspaceSettingsFromDraft(
  draft: Pick<
    IssueEditDraft,
    | "workspaceTargetMode"
    | "workspaceWorktreePath"
    | "workspaceWorktreeBranch"
    | "workspaceWorktreeName"
  >,
  projectId?: string | null,
) {
  if (!projectId?.trim()) {
    return null;
  }

  switch (draft.workspaceTargetMode) {
    case "new_worktree":
      return {
        mode: "new_worktree",
      };
    case "existing_worktree":
      return draft.workspaceWorktreePath
        ? {
            mode: "existing_worktree",
            worktree_path: draft.workspaceWorktreePath,
            worktree_branch: draft.workspaceWorktreeBranch || null,
            worktree_name: draft.workspaceWorktreeName || null,
          }
        : null;
    case "main":
      return {
        mode: "main",
      };
    default:
      return {
        mode: "main",
      };
  }
}

function existingWorktreeTargetValue(path: string) {
  return `existing:${path}`;
}

function issueWorkspaceTargetSelectValue(
  mode: IssueWorkspaceTargetMode,
  worktreePath: string,
) {
  if (mode === "new_worktree") {
    return "new_worktree";
  }

  if (mode === "existing_worktree" && worktreePath) {
    return existingWorktreeTargetValue(worktreePath);
  }

  return "main";
}

function issueWorkspaceDraftPatchFromSelection(
  value: string,
  worktrees: GitWorktreeRecord[],
  current: Pick<
    IssueEditDraft,
    | "workspaceWorktreeBranch"
    | "workspaceWorktreeName"
    | "workspaceWorktreePath"
  >,
): Partial<IssueEditDraft> {
  if (value === "new_worktree") {
    return {
      workspaceTargetMode: "new_worktree",
      workspaceWorktreePath: "",
      workspaceWorktreeBranch: "",
      workspaceWorktreeName: "",
    };
  }

  if (value.startsWith("existing:")) {
    const selectedPath = value.slice("existing:".length);
    const selectedWorktree = worktrees.find(
      (worktree) => worktree.path === selectedPath,
    );
    return {
      workspaceTargetMode: "existing_worktree",
      workspaceWorktreePath: selectedPath,
      workspaceWorktreeBranch:
        selectedWorktree?.branch ?? current.workspaceWorktreeBranch,
      workspaceWorktreeName:
        selectedWorktree?.name ??
        current.workspaceWorktreeName ??
        fileName(selectedPath),
    };
  }

  return {
    workspaceTargetMode: "main",
    workspaceWorktreePath: "",
    workspaceWorktreeBranch: "",
    workspaceWorktreeName: "",
  };
}

function issueWorkspaceTargetHint({
  errorMessage,
  hasProject,
  hasRepoPath,
  isLoading,
  worktreeCount,
}: {
  errorMessage: string | null;
  hasProject: boolean;
  hasRepoPath: boolean;
  isLoading: boolean;
  worktreeCount: number;
}) {
  if (!hasProject) {
    return "Link the conversation to a project first.";
  }

  if (!hasRepoPath) {
    return "The selected project does not have a repository folder yet.";
  }

  if (errorMessage) {
    return errorMessage;
  }

  if (isLoading) {
    return "Loading existing worktrees...";
  }

  if (worktreeCount > 0) {
    return `${worktreeCount} existing ${worktreeCount === 1 ? "worktree is" : "worktrees are"} available to reuse.`;
  }

  return "Run in the repo root or create a fresh git worktree for this conversation.";
}

const primaryBoardSections: Array<{ title: string; screens: AppScreen[] }> = [
  { title: "Work", screens: ["issues"] },
];

const companyBoardSection: { title: string; screens: AppScreen[] } = {
  title: "Spaces",
  screens: ["stats", "activity", "costs", "companySettings"],
};

const settingsSections: Array<{ id: SettingsSection; label: string }> = [
  { id: "general", label: "General" },
  { id: "appearance", label: "Appearance" },
  { id: "notifications", label: "Notifications" },
  { id: "privacy", label: "Privacy" },
];

const themeModes: ThemeMode[] = ["system", "light", "dark"];
const fontSizePresets: FontSizePreset[] = ["small", "medium", "large"];
const dashboardProjectGroupingOptions: DashboardProjectGrouping[] = ["status"];
const dashboardProjectGroupingSelectOptions: Array<
  SelectOption<DashboardProjectGrouping>
> = dashboardProjectGroupingOptions.map((value) => ({
  label: humanizeIssueValue(value),
  value,
}));
const desktopPreferredViewOptions: Array<
  SelectOption<DesktopPreferredViewValue>
> = [
  { label: "Dashboard", value: "dashboard" },
  { label: "Stats", value: "stats" },
  { label: "Activity", value: "activity" },
  { label: "Costs", value: "costs" },
  { label: "Settings", value: "settings" },
];

const defaultSettings: DesktopSettings = {
  preferred_company_id: null,
  preferred_repository_id: null,
  preferred_space_id: null,
  preferred_view: "dashboard",
  show_raw_message_json: false,
  last_repository_path: null,
  theme_mode: "dark",
  font_size_preset: "medium",
  dashboard_project_views: {},
  birds_eye_canvas: {},
};

const companyContextMenuItems: Array<{
  icon: CompanyContextMenuIconKey;
  label: string;
  screen: CompanyContextMenuScreen;
}> = [
  { icon: "dashboard", label: "Dashboard", screen: "dashboard" },
  { icon: "issues", label: "Conversations", screen: "issues" },
  { icon: "companySettings", label: "Settings", screen: "companySettings" },
];

const defaultDashboardCanvasOffset: DashboardCanvasOffset = {
  x: 96,
  y: 88,
};
const defaultBirdsEyeCanvasOffset: DashboardCanvasOffset = {
  x: 48,
  y: 40,
};
const birdsEyeCanvasZoomLevels = [0.45, 0.65, 0.85, 1, 1.15] as const;
const defaultBirdsEyeCanvasZoomIndex = 3;
const birdsEyeRepoRegionGapX = 420;
const birdsEyeRepoRegionDefaultY = 80;
const birdsEyeRepoRegionPadding = 28;
const birdsEyeRepoRegionLabelOffsetY = 28;
const birdsEyeRepoRegionMinWidth = 920;
const birdsEyeRepoRegionBackgroundAlpha = 0.12;
const birdsEyeWorktreeBoardGap = 24;
const birdsEyeWorktreePageSize = 8;
const birdsEyeWorktreeBoardHeight = 700;
const birdsEyeWorktreeBoardWidthCompact = 860;
const birdsEyeWorktreeBoardWidthWide = 1040;
const dashboardCanvasZoomLevels = [0.7, 0.85, 1, 1.15, 1.3] as const;
const defaultDashboardCanvasZoomIndex = 2;

const dashboardProjectBoardMinWidth = 920;
const dashboardProjectBoardHeight = 1280;
const dashboardProjectBoardGapX = 440;
const dashboardProjectBoardGapY = 440;
const dashboardProjectBoardStackGap = 80;
const dashboardProjectBoardPadding = 18;
const dashboardProjectBoardBorderWidth = 1;
const dashboardProjectBoardColumnWidth = 680;
const dashboardProjectBoardColumnGap = 14;
const dashboardProjectAddViewSlotHeight = 126;
const dashboardDefaultProjectViewId = "default";

const defaultCompanyBrandColor = "#0F766E";

export function App() {
  const [bootstrap, setBootstrap] = useState<DesktopBootstrapStatus | null>(
    null,
  );
  const [settings, setSettings] = useState<DesktopSettings>(defaultSettings);
  const [currentSpaceScope, setCurrentSpaceScope] =
    useState<CurrentSpaceScope | null>(null);
  const [selectedScreen, setSelectedScreen] = useState<AppScreen>("dashboard");
  const [selectedSettingsSection, setSelectedSettingsSection] =
    useState<SettingsSection>("appearance");
  const [companies, setCompanies] = useState<Company[]>([]);
  const [repositories, setRepositories] = useState<RepositoryRecord[]>([]);
  const [selectedCompanyId, setSelectedCompanyId] = useState<string | null>(
    null,
  );
  const [selectedRepositoryId, setSelectedRepositoryId] = useState<
    string | null
  >(null);
  const [selectedBoardWorkspaceId, setSelectedBoardWorkspaceId] = useState<
    string | null
  >(null);
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [selectedApprovalId, setSelectedApprovalId] = useState<string | null>(
    null,
  );
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(
    null,
  );
  const [selectedIssueId, setSelectedIssueId] = useState<string | null>(null);
  const [selectedIssuesListTab, setSelectedIssuesListTab] =
    useState<IssuesListTab>("new");
  const [issuesRouteMode, setIssuesRouteMode] =
    useState<IssuesRouteMode>("list");
  const [agentsRouteMode, setAgentsRouteMode] =
    useState<AgentsRouteMode>("dashboard");
  const [companySnapshot, setCompanySnapshot] =
    useState<CompanySnapshot | null>(null);
  const [dashboardOverview, setDashboardOverview] =
    useState<DashboardOverviewRecord | null>(null);
  const [isDashboardOverviewLoading, setIsDashboardOverviewLoading] =
    useState(false);
  const [agentRuns, setAgentRuns] = useState<AgentRunRecord[]>([]);
  const [selectedAgentRunId, setSelectedAgentRunId] = useState<string | null>(
    null,
  );
  const [selectedAgentRun, setSelectedAgentRun] =
    useState<AgentRunRecord | null>(null);
  const [agentRunEvents, setAgentRunEvents] = useState<AgentRunEventRecord[]>(
    [],
  );
  const [agentRunLogContent, setAgentRunLogContent] = useState("");
  const [agentRunLogOffset, setAgentRunLogOffset] = useState(0);
  const [isLoadingAgentRuns, setIsLoadingAgentRuns] = useState(false);
  const [isLoadingAgentRunDetail, setIsLoadingAgentRunDetail] = useState(false);
  const [isPerformingAgentRunAction, setIsPerformingAgentRunAction] =
    useState(false);
  const [agentRunError, setAgentRunError] = useState<string | null>(null);
  const [issueCommentsByIssueId, setIssueCommentsByIssueId] = useState<
    Record<string, IssueCommentRecord[]>
  >({});
  const [issueRunCardUpdatesByIssueId, setIssueRunCardUpdatesByIssueId] =
    useState<Record<string, IssueRunCardUpdateRecord>>({});
  const [liveAgentRunCountsByAgentId, setLiveAgentRunCountsByAgentId] =
    useState<Record<string, number>>({});
  const [issueAttachmentsByIssueId, setIssueAttachmentsByIssueId] = useState<
    Record<string, IssueAttachmentRecord[]>
  >({});
  const [sessions, setSessions] = useState<SessionRecord[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(
    null,
  );
  const [gitState, setGitState] = useState<GitStatusResult | null>(null);
  const [gitHistory, setGitHistory] = useState<GitLogResult | null>(null);
  const [branchState, setBranchState] = useState<GitBranchesResult | null>(
    null,
  );
  const [fileEntries, setFileEntries] = useState<FileEntry[]>([]);
  const [currentDirectory, setCurrentDirectory] = useState("");
  const [selectedFilePath, setSelectedFilePath] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<FileReadResult | null>(null);
  const [selectedDiff, setSelectedDiff] = useState<GitDiffResult | null>(null);
  const [dependencyCheck, setDependencyCheck] =
    useState<RuntimeCapabilities | null>(null);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [workspaceCenterTab, setWorkspaceCenterTab] =
    useState<WorkspaceCenterTab>("conversation");
  const [workspaceSidebarTab, setWorkspaceSidebarTab] =
    useState<WorkspaceSidebarTab>("changes");
  const [gitCommitMessage, setGitCommitMessage] = useState("");
  const [prompt, setPrompt] = useState("");
  const [terminalCommand, setTerminalCommand] = useState("");
  const [isCreateCompanyDialogOpen, setIsCreateCompanyDialogOpen] =
    useState(false);
  const [companyDialogName, setCompanyDialogName] = useState("");
  const [companyDialogDescription, setCompanyDialogDescription] = useState("");
  const [companyDialogBrandColor, setCompanyDialogBrandColor] = useState(
    defaultCompanyBrandColor,
  );
  const [companyDialogError, setCompanyDialogError] = useState<string | null>(
    null,
  );
  const [isCompanyDialogSaving, setIsCompanyDialogSaving] = useState(false);
  const [isCreateIssueDialogOpen, setIsCreateIssueDialogOpen] = useState(false);
  const [issueDialogMode, setIssueDialogMode] =
    useState<IssueDialogMode>("conversation");
  const [issueDialogTitle, setIssueDialogTitle] = useState("");
  const [issueDialogDescription, setIssueDialogDescription] = useState("");
  const [issueDialogPriority, setIssueDialogPriority] = useState("medium");
  const [issueDialogStatus, setIssueDialogStatus] = useState("backlog");
  const [issueDialogProjectId, setIssueDialogProjectId] = useState("");
  const [issueDialogParentIssueId, setIssueDialogParentIssueId] = useState("");
  const [issueDialogCommand, setIssueDialogCommand] = useState("claude");
  const [issueDialogModel, setIssueDialogModel] = useState("default");
  const [issueDialogThinkingEffort, setIssueDialogThinkingEffort] =
    useState("auto");
  const [issueDialogPlanMode, setIssueDialogPlanMode] = useState(false);
  const [issueDialogEnableChrome, setIssueDialogEnableChrome] = useState(false);
  const [issueDialogSkipPermissions, setIssueDialogSkipPermissions] =
    useState(false);
  const [issueDialogWorkspaceTargetMode, setIssueDialogWorkspaceTargetMode] =
    useState<IssueWorkspaceTargetMode>("main");
  const [
    issueDialogWorkspaceWorktreePath,
    setIssueDialogWorkspaceWorktreePath,
  ] = useState("");
  const [
    issueDialogWorkspaceWorktreeBranch,
    setIssueDialogWorkspaceWorktreeBranch,
  ] = useState("");
  const [
    issueDialogWorkspaceWorktreeName,
    setIssueDialogWorkspaceWorktreeName,
  ] = useState("");
  const [issueDialogError, setIssueDialogError] = useState<string | null>(null);
  const [isIssueDialogSaving, setIsIssueDialogSaving] = useState(false);
  const [issueDialogAttachments, setIssueDialogAttachments] = useState<
    IssueAttachmentDraft[]
  >([]);
  const [dashboardIssuePreviewId, setDashboardIssuePreviewId] = useState<
    string | null
  >(null);
  const [dashboardPreviewIssueDetail, setDashboardPreviewIssueDetail] =
    useState<IssueRecord | null>(null);
  const [isDashboardIssuePreviewLoading, setIsDashboardIssuePreviewLoading] =
    useState(false);
  const [dashboardIssuePreviewError, setDashboardIssuePreviewError] = useState<
    string | null
  >(null);
  const [issueDraft, setIssueDraft] = useState<IssueEditDraft>(
    createEmptyIssueDraft(),
  );
  const [isSavingIssue, setIsSavingIssue] = useState(false);
  const [issueEditorError, setIssueEditorError] = useState<string | null>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [companyContextMenu, setCompanyContextMenu] =
    useState<CompanyContextMenuState | null>(null);
  const [companyBrandColorDraft, setCompanyBrandColorDraft] = useState(
    defaultCompanyBrandColor,
  );
  const [isSavingCompanyBrandColor, setIsSavingCompanyBrandColor] =
    useState(false);
  const [companyBrandColorError, setCompanyBrandColorError] = useState<
    string | null
  >(null);
  const [agentConfigDraft, setAgentConfigDraft] = useState<AgentConfigDraft>(
    createEmptyAgentConfigDraft(),
  );
  const [isSavingAgentConfig, setIsSavingAgentConfig] = useState(false);
  const [agentConfigError, setAgentConfigError] = useState<string | null>(null);
  const [dashboardCanvasOffset, setDashboardCanvasOffset] =
    useState<DashboardCanvasOffset>(defaultDashboardCanvasOffset);
  const [dashboardCanvasZoomIndex, setDashboardCanvasZoomIndex] = useState(
    defaultDashboardCanvasZoomIndex,
  );
  const [isDashboardCanvasDragging, setIsDashboardCanvasDragging] =
    useState(false);

  const terminalContainerRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const refreshTimeoutRef = useRef<number | null>(null);
  const sessionStateManager = useMemo(
    () => new DesktopSessionStateManager(),
    [],
  );
  const dashboardCanvasViewportRef = useRef<HTMLDivElement | null>(null);
  const selectedAgentIdRef = useRef<string | null>(null);
  const selectedAgentRunIdRef = useRef<string | null>(null);
  const issueUpdateQueueRef = useRef(Promise.resolve<void>(undefined));
  const dashboardCanvasPanRef = useRef<{
    pointerId: number;
    originX: number;
    originY: number;
    startX: number;
    startY: number;
  } | null>(null);
  const dashboardCanvasWheelZoomRef = useRef<{
    accumulatedDeltaY: number;
    lastEventTime: number;
  }>({
    accumulatedDeltaY: 0,
    lastEventTime: 0,
  });
  const selectedRepository = repositories.find(
    (repository) => repository.id === selectedRepositoryId,
  );
  const selectedCompany =
    companySnapshot?.company ??
    companies.find((company) => company.id === selectedCompanyId) ??
    null;
  const dashboardOverviewAgents =
    dashboardOverview?.agents ?? emptyAgentRecords;
  const dashboardOverviewProjects =
    dashboardOverview?.projects ?? emptyProjectRecords;
  const dashboardOverviewWorkspaces =
    dashboardOverview?.workspaces ?? emptyWorkspaceRecords;
  const dashboardOverviewChats =
    dashboardOverview?.chats ?? emptyDashboardOverviewChats;
  const boardIssues = companySnapshot?.issues ?? emptyIssueRecords;
  const selectedIssue =
    boardIssues.find((issue) => issue.id === selectedIssueId) ?? null;
  const visibleIssues = useMemo(
    () => issuesVisible(boardIssues, selectedIssuesListTab),
    [boardIssues, selectedIssuesListTab],
  );
  const dashboardPreviewChatSummary =
    dashboardOverviewChats.find(
      (chat) => chat.id === dashboardIssuePreviewId,
    ) ?? null;
  const activityVisibleIssues = useMemo(
    () => boardIssues.filter((issue) => !issue.hidden_at),
    [boardIssues],
  );
  const activityVisibleIssueIdsKey = useMemo(
    () =>
      activityVisibleIssues
        .map((issue) => issue.id)
        .sort()
        .join("|"),
    [activityVisibleIssues],
  );
  const activityMissingCommentIssueIds = useMemo(
    () =>
      activityVisibleIssues
        .filter((issue) => issueCommentsByIssueId[issue.id] === undefined)
        .map((issue) => issue.id),
    [activityVisibleIssues, issueCommentsByIssueId],
  );
  const issueSummaryText = useMemo(() => {
    const suffix =
      visibleIssues.length === 1 ? "conversation" : "conversations";
    return `${issuesListTabTitle(selectedIssuesListTab)} · ${visibleIssues.length} ${suffix}`;
  }, [selectedIssuesListTab, visibleIssues.length]);
  const issueSubissues = useMemo(
    () =>
      selectedIssue
        ? boardIssues.filter(
            (issue) =>
              issue.parent_id === selectedIssue.id && issue.hidden_at == null,
          )
        : [],
    [boardIssues, selectedIssue],
  );
  const selectedIssueAttachments = selectedIssue
    ? (issueAttachmentsByIssueId[selectedIssue.id] ?? [])
    : [];
  const dashboardPreviewIssue =
    dashboardPreviewIssueDetail ??
    (dashboardPreviewChatSummary
      ? dashboardOverviewChatToIssueRecord(
          dashboardPreviewChatSummary,
          selectedCompanyId,
        )
      : null);
  const dashboardPreviewComments = dashboardPreviewIssue
    ? (issueCommentsByIssueId[dashboardPreviewIssue.id] ?? [])
    : [];
  const dashboardPreviewAttachments = dashboardPreviewIssue
    ? (issueAttachmentsByIssueId[dashboardPreviewIssue.id] ?? [])
    : [];
  const dashboardPreviewRunCardUpdate =
    dashboardPreviewChatSummary?.run_update ?? null;
  const boardGoals = companySnapshot?.goals ?? emptyGoalRecords;
  const boardProjects = companySnapshot?.projects ?? emptyProjectRecords;
  const currentProjectsForCreation =
    boardProjects.length > 0 ? boardProjects : dashboardOverviewProjects;
  const issueDialogProjectRepoPath =
    currentProjectsForCreation.find(
      (project) => project.id === issueDialogProjectId,
    )?.primary_workspace?.cwd ?? null;
  const issueDialogWorktreeState = useProjectWorktrees(
    issueDialogProjectRepoPath,
  );
  const issueDetailProjectRepoPath =
    boardProjects.find((project) => project.id === issueDraft.projectId)
      ?.primary_workspace?.cwd ?? null;
  const issueDetailWorktreeState = useProjectWorktrees(
    issueDetailProjectRepoPath,
  );
  const boardAgents = companySnapshot?.agents ?? emptyAgentRecords;
  const currentCompanyAgents =
    boardAgents.length > 0 ? boardAgents : dashboardOverviewAgents;
  const dashboardProjectViews = settings.dashboard_project_views ?? {};
  const selectedBirdsEyeCanvasSettings =
    (selectedCompanyId
      ? settings.birds_eye_canvas?.[selectedCompanyId]
      : null) ?? null;
  const dashboardProjectColumns = useMemo(
    () =>
      buildDashboardProjectColumns(
        boardProjects,
        boardIssues.filter(
          (issue) => !issue.hidden_at && isRootConversationIssue(issue),
        ),
        boardAgents,
        dashboardProjectViews,
      ),
    [boardAgents, boardIssues, boardProjects, dashboardProjectViews],
  );
  const dashboardCanvasBounds = useMemo(
    () => buildDashboardCanvasBounds(dashboardProjectColumns),
    [dashboardProjectColumns],
  );
  const dashboardCanvasZoomScale =
    dashboardCanvasZoomLevels[dashboardCanvasZoomIndex] ?? 1;
  const selectedProject =
    boardProjects.find((project) => project.id === selectedProjectId) ??
    boardProjects[0] ??
    null;
  const boardApprovals = companySnapshot?.approvals ?? emptyApprovalRecords;
  const selectedApproval =
    boardApprovals.find((approval) => approval.id === selectedApprovalId) ??
    boardApprovals[0] ??
    null;
  const companyWorkspaces =
    companySnapshot?.workspaces ?? emptyWorkspaceRecords;
  const selectedBoardWorkspace =
    companyWorkspaces.find(
      (workspace) => workspace.id === selectedBoardWorkspaceId,
    ) ??
    companyWorkspaces[0] ??
    null;
  const selectedIssueWorkspace = selectedIssue
    ? (companyWorkspaces.find((workspace) => {
        if (workspace.issue_id === selectedIssue.id) {
          return true;
        }

        if (!selectedIssue.workspace_session_id) {
          return false;
        }

        return (
          workspace.id === selectedIssue.workspace_session_id ||
          workspace.session_id === selectedIssue.workspace_session_id
        );
      }) ?? null)
    : null;
  const selectedAgent =
    boardAgents.find((agent) => agent.id === selectedAgentId) ??
    boardAgents[0] ??
    null;
  const selectedAgentRunIsLive =
    selectedAgentRun?.status === "queued" ||
    selectedAgentRun?.status === "running";
  const selectedCompanyCeo = findCompanyCeo(
    currentCompanyAgents,
    selectedCompany?.ceo_agent_id ?? null,
  );
  const hiddenExecutionAgentId =
    selectedCompany?.ceo_agent_id?.trim() ||
    selectedCompanyCeo?.id ||
    currentCompanyAgents[0]?.id ||
    null;
  const orderedSidebarAgents = useMemo(
    () =>
      orderSidebarAgents(
        currentCompanyAgents,
        typeof selectedCompany?.ceo_agent_id === "string"
          ? selectedCompany.ceo_agent_id
          : null,
      ),
    [currentCompanyAgents, selectedCompany?.ceo_agent_id],
  );
  const orderedSidebarProjects = useMemo(
    () =>
      [
        ...(boardProjects.length > 0
          ? boardProjects
          : dashboardOverviewProjects),
      ].sort((left, right) =>
        (left.name ?? left.title ?? left.id).localeCompare(
          right.name ?? right.title ?? right.id,
        ),
      ),
    [boardProjects, dashboardOverviewProjects],
  );
  const totalLiveAgentRuns = useMemo(
    () =>
      Object.values(liveAgentRunCountsByAgentId).reduce(
        (sum, count) => sum + count,
        0,
      ),
    [liveAgentRunCountsByAgentId],
  );
  const activeSession =
    sessions.find((session) => session.id === selectedSessionId) ?? null;
  const selectedIssueWorkspaceSession =
    sessions.find(
      (session) => session.id === (selectedIssueWorkspace?.session_id ?? ""),
    ) ?? null;
  const activeWorkspaceAgent =
    boardAgents.find(
      (agent) => agent.id === selectedBoardWorkspace?.agent_id,
    ) ?? null;
  const selectedIssueWorkspaceAgent =
    boardAgents.find(
      (agent) => agent.id === selectedIssueWorkspace?.agent_id,
    ) ?? null;
  const activeWorkspaceProvider = detectWorkspaceAgentProvider(
    activeSession,
    activeWorkspaceAgent,
  );
  const selectedIssueWorkspaceProvider = detectWorkspaceAgentProvider(
    selectedIssueWorkspaceSession,
    selectedIssueWorkspaceAgent,
  );
  const activeSessionLiveState = useDesktopSessionLiveState(
    sessionStateManager,
    activeSession?.id ?? null,
    activeWorkspaceProvider,
  );
  const selectedIssueWorkspaceLiveState = useDesktopSessionLiveState(
    sessionStateManager,
    selectedIssueWorkspace?.session_id ?? null,
    selectedIssueWorkspaceProvider,
  );
  const deferredMessages = useDeferredValue(activeSessionLiveState.messages);
  const activeSessionConversationRows = activeSessionLiveState.conversationRows;
  const activeRuntimeStatusState = activeSessionLiveState.runtimeStatus;
  const activeTerminalStatusState = activeSessionLiveState.terminalStatus;
  const previewTabLabel = selectedFilePath
    ? (selectedFilePath.split("/").filter(Boolean).at(-1) ?? "Preview")
    : "Preview";
  const currentBranchName = branchState?.current ?? gitState?.branch ?? "main";
  const currentBranch =
    branchState?.local.find((branch) => branch.name === currentBranchName) ??
    null;
  const hasUncommittedChanges = (gitState?.files.length ?? 0) > 0;
  const hasUnpushedCommits = (currentBranch?.ahead ?? 0) > 0;
  const issueStatusOptions = useMemo(
    () => mergeIssueOptions(canonicalIssueStatuses, issueDraft.status),
    [issueDraft.status],
  );
  const selectableParentIssues = useMemo(
    () => boardIssues.filter((issue) => issue.id !== selectedIssue?.id),
    [boardIssues, selectedIssue?.id],
  );
  const layout = boardRootLayout(selectedScreen);
  const clampDashboardOffset = (next: DashboardCanvasOffset) => {
    const viewport = dashboardCanvasViewportRef.current;
    if (!viewport) {
      return next;
    }

    return clampDashboardCanvasOffset(
      next,
      viewport.clientWidth,
      viewport.clientHeight,
      dashboardCanvasBounds,
      dashboardCanvasZoomScale,
    );
  };

  const resetAgentRunsState = () => {
    selectedAgentRunIdRef.current = null;
    setAgentRuns([]);
    setSelectedAgentRunId(null);
    setSelectedAgentRun(null);
    setAgentRunEvents([]);
    setAgentRunLogContent("");
    setAgentRunLogOffset(0);
    setIsLoadingAgentRuns(false);
    setIsLoadingAgentRunDetail(false);
    setIsPerformingAgentRunAction(false);
    setAgentRunError(null);
  };

  const loadAgentRuns = async (resetSelection: boolean) => {
    const agentId = selectedAgentIdRef.current;
    if (!agentId) {
      resetAgentRunsState();
      return;
    }

    setIsLoadingAgentRuns(true);

    try {
      const runs = await boardListAgentRuns(agentId, 200);
      if (selectedAgentIdRef.current !== agentId) {
        return;
      }

      const currentSelectedRunId = selectedAgentRunIdRef.current;
      const nextSelectedRunId =
        resetSelection ||
        !currentSelectedRunId ||
        !runs.some((run) => run.id === currentSelectedRunId)
          ? (runs[0]?.id ?? null)
          : currentSelectedRunId;

      selectedAgentRunIdRef.current = nextSelectedRunId;
      startTransition(() => {
        setAgentRuns(runs);
        setSelectedAgentRunId(nextSelectedRunId);
        setSelectedAgentRun(
          nextSelectedRunId
            ? (runs.find((run) => run.id === nextSelectedRunId) ?? null)
            : null,
        );
        setAgentRunError(null);
      });
    } catch (error) {
      setAgentRunError(error instanceof Error ? error.message : String(error));
    } finally {
      if (selectedAgentIdRef.current === agentId) {
        setIsLoadingAgentRuns(false);
      }
    }
  };

  const refreshSelectedAgentRun = async (resetStreams: boolean) => {
    const agentId = selectedAgentIdRef.current;
    const runId = selectedAgentRunIdRef.current;
    if (!(agentId && runId)) {
      return;
    }

    setIsLoadingAgentRunDetail(true);

    try {
      const [run, events, logChunk] = await Promise.all([
        boardGetAgentRun(runId),
        boardListAgentRunEvents(
          runId,
          resetStreams ? undefined : agentRunEvents.at(-1)?.seq,
          400,
        ),
        boardReadAgentRunLog(runId, resetStreams ? 0 : agentRunLogOffset),
      ]);

      if (
        selectedAgentIdRef.current !== agentId ||
        selectedAgentRunIdRef.current !== runId
      ) {
        return;
      }

      startTransition(() => {
        setSelectedAgentRun(run);
        setAgentRuns((current) =>
          current.map((existingRun) =>
            existingRun.id === run.id ? run : existingRun,
          ),
        );
        if (resetStreams) {
          setAgentRunEvents(events);
          setAgentRunLogContent(logChunk.content);
        } else {
          setAgentRunEvents((current) => current.concat(events));
          if (logChunk.content) {
            setAgentRunLogContent((current) => current + logChunk.content);
          }
        }
        setAgentRunLogOffset(logChunk.next_offset);
        setAgentRunError(null);
      });
    } catch (error) {
      setAgentRunError(error instanceof Error ? error.message : String(error));
    } finally {
      if (
        selectedAgentIdRef.current === agentId &&
        selectedAgentRunIdRef.current === runId
      ) {
        setIsLoadingAgentRunDetail(false);
      }
    }
  };

  const performAgentRunAction = async (
    operation: () => Promise<AgentRunRecord>,
  ) => {
    setIsPerformingAgentRunAction(true);

    try {
      const updatedRun = await operation();
      setAgentRunError(null);
      await loadAgentRuns(false);
      selectedAgentRunIdRef.current = updatedRun.id;
      setSelectedAgentRunId(updatedRun.id);
      await refreshSelectedAgentRun(true);
    } catch (error) {
      setAgentRunError(error instanceof Error ? error.message : String(error));
    } finally {
      setIsPerformingAgentRunAction(false);
    }
  };

  useEffect(() => {
    const terminal = new Terminal({
      convertEol: true,
      cursorBlink: false,
      disableStdin: true,
      fontSize: 12,
      fontFamily:
        '"Geist Mono", "SFMono-Regular", ui-monospace, "Cascadia Code", monospace',
      theme: {
        background: "#08111f",
        foreground: "#dbe9ff",
        cursor: "#8fb6ff",
        black: "#08111f",
        red: "#f7768e",
        green: "#9ece6a",
        yellow: "#e0af68",
        blue: "#7aa2f7",
        magenta: "#bb9af7",
        cyan: "#7dcfff",
        white: "#c0caf5",
      },
    });
    terminalRef.current = terminal;

    if (terminalContainerRef.current) {
      terminal.open(terminalContainerRef.current);
      terminal.writeln("Waiting for terminal output...");
    }

    return () => {
      terminal.dispose();
      terminalRef.current = null;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;

    const initialize = async () => {
      try {
        const status = await desktopBootstrap();
        if (cancelled) {
          return;
        }

        setBootstrap(status);

        if (status.state !== "ready") {
          return;
        }

        const [
          loadedSettings,
          loadedCompanies,
          loadedRepositories,
          loadedSpaceScope,
        ] = await Promise.all([
          settingsGet(),
          boardListCompanies(),
          repositoryList(),
          spaceGetCurrent().catch(() => null),
        ]);

        if (cancelled) {
          return;
        }

        const companiesValue = loadedCompanies as Company[];
        const repositoriesValue = loadedRepositories as RepositoryRecord[];
        const nextSettings = mergeDesktopSettings(loadedSettings);
        const nextScreen = normalizeScreen(nextSettings.preferred_view);
        const nextCompanyId =
          nextSettings.preferred_company_id ?? companiesValue[0]?.id ?? null;
        const nextRepositoryId =
          nextSettings.preferred_repository_id ??
          repositoriesValue[0]?.id ??
          null;

        startTransition(() => {
          setSettings(nextSettings);
          setCompanies(companiesValue);
          setRepositories(repositoriesValue);
          setCurrentSpaceScope(loadedSpaceScope);
          setSelectedScreen(nextScreen);
          setSelectedCompanyId(nextCompanyId);
          setSelectedRepositoryId(nextRepositoryId);
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
    };

    void initialize();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    document.documentElement.dataset.themeMode = settings.theme_mode ?? "dark";
    document.documentElement.dataset.fontSizePreset =
      settings.font_size_preset ?? "medium";
  }, [settings.font_size_preset, settings.theme_mode]);

  useEffect(() => {
    setCompanyBrandColorDraft(normalizeHexColor(selectedCompany?.brand_color));
    setCompanyBrandColorError(null);
    setIsSavingCompanyBrandColor(false);
  }, [selectedCompany?.brand_color, selectedCompanyId]);

  useEffect(() => {
    setDashboardCanvasOffset(defaultDashboardCanvasOffset);
    setIsDashboardCanvasDragging(false);
    dashboardCanvasPanRef.current = null;
  }, [selectedCompanyId]);

  useEffect(() => {
    setDashboardCanvasOffset((current) => clampDashboardOffset(current));
  }, [
    dashboardCanvasBounds.height,
    dashboardCanvasBounds.width,
    dashboardCanvasZoomScale,
  ]);

  useEffect(() => {
    if (!companyContextMenu) {
      return;
    }

    const closeMenu = () => setCompanyContextMenu(null);
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        closeMenu();
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [companyContextMenu]);

  useEffect(() => {
    if (!companyContextMenu) {
      return;
    }

    if (companyContextMenu.companyId === selectedCompanyId && companySnapshot) {
      const nextAgents = orderSidebarAgents(
        companySnapshot.agents ?? [],
        typeof companySnapshot.company?.ceo_agent_id === "string"
          ? companySnapshot.company.ceo_agent_id
          : null,
      );
      if (
        !companyContextMenu.isLoadingAgents &&
        sameAgentIdList(companyContextMenu.agents, nextAgents)
      ) {
        return;
      }
      setCompanyContextMenu((current) => {
        if (!current || current.companyId !== companyContextMenu.companyId) {
          return current;
        }

        return {
          ...current,
          agents: nextAgents,
          isLoadingAgents: false,
        };
      });
      return;
    }

    if (bootstrap?.state !== "ready" || !companyContextMenu.isLoadingAgents) {
      return;
    }

    let cancelled = false;

    const loadMenuAgents = async () => {
      try {
        const snapshot = await boardCompanySnapshot(
          companyContextMenu.companyId,
        );
        if (cancelled) {
          return;
        }

        const nextAgents = orderSidebarAgents(
          snapshot.agents ?? [],
          typeof snapshot.company?.ceo_agent_id === "string"
            ? snapshot.company.ceo_agent_id
            : null,
        );
        setCompanyContextMenu((current) => {
          if (!current || current.companyId !== companyContextMenu.companyId) {
            return current;
          }

          return {
            ...current,
            agents: nextAgents,
            isLoadingAgents: false,
          };
        });
      } catch (error) {
        if (cancelled) {
          return;
        }

        setCompanyContextMenu((current) => {
          if (!current || current.companyId !== companyContextMenu.companyId) {
            return current;
          }

          return {
            ...current,
            agents: [],
            isLoadingAgents: false,
          };
        });
        setStatusMessage(
          error instanceof Error ? error.message : String(error),
        );
      }
    };

    void loadMenuAgents();

    return () => {
      cancelled = true;
    };
  }, [
    bootstrap?.state,
    companyContextMenu,
    companySnapshot,
    selectedCompanyId,
  ]);

  useEffect(() => {
    if (
      !selectedCompanyId ||
      bootstrap?.state !== "ready" ||
      selectedScreen === "dashboard"
    ) {
      return;
    }

    let cancelled = false;
    const loadSnapshot = async () => {
      try {
        const snapshot = await boardCompanySnapshot(selectedCompanyId);
        if (!cancelled) {
          setCompanySnapshot(snapshot);
        }
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
    };

    void loadSnapshot();

    return () => {
      cancelled = true;
    };
  }, [bootstrap?.state, selectedCompanyId, selectedScreen]);

  useEffect(() => {
    if (!selectedCompanyId || bootstrap?.state !== "ready") {
      setDashboardOverview(null);
      setIsDashboardOverviewLoading(false);
      return;
    }

    if (selectedScreen !== "dashboard") {
      setIsDashboardOverviewLoading(false);
      return;
    }

    let cancelled = false;
    setIsDashboardOverviewLoading(true);

    const loadOverview = async () => {
      try {
        const overview = await boardDashboardOverview(selectedCompanyId);
        if (!cancelled) {
          setDashboardOverview(overview);
        }
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      } finally {
        if (!cancelled) {
          setIsDashboardOverviewLoading(false);
        }
      }
    };

    void loadOverview();

    return () => {
      cancelled = true;
    };
  }, [bootstrap?.state, selectedCompanyId, selectedScreen]);

  useEffect(() => {
    const nextWorkspaces = companySnapshot?.workspaces ?? [];
    const nextAgents = companySnapshot?.agents ?? [];
    const nextIssues = companySnapshot?.issues ?? [];
    const nextApprovals = companySnapshot?.approvals ?? [];
    const nextProjects = companySnapshot?.projects ?? [];

    setSelectedBoardWorkspaceId((current) => {
      if (
        current &&
        nextWorkspaces.some((workspace) => workspace.id === current)
      ) {
        return current;
      }
      return nextWorkspaces[0]?.id ?? null;
    });

    setSelectedAgentId((current) => {
      if (current && nextAgents.some((agent) => agent.id === current)) {
        return current;
      }
      return nextAgents[0]?.id ?? null;
    });

    setSelectedIssueId((current) => {
      if (current && nextIssues.some((issue) => issue.id === current)) {
        return current;
      }
      return null;
    });

    setSelectedApprovalId((current) => {
      if (
        current &&
        nextApprovals.some((approval) => approval.id === current)
      ) {
        return current;
      }
      return null;
    });

    setSelectedProjectId((current) => {
      if (current && nextProjects.some((project) => project.id === current)) {
        return current;
      }
      return nextProjects[0]?.id ?? null;
    });

    setIssueCommentsByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId),
        ),
      ),
    );
    setIssueAttachmentsByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId),
        ),
      ),
    );
    setIssueRunCardUpdatesByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId),
        ),
      ),
    );
  }, [companySnapshot]);

  useEffect(() => {
    if (bootstrap?.state !== "ready" || !selectedCompanyId) {
      setLiveAgentRunCountsByAgentId((current) =>
        Object.keys(current).length === 0 ? current : {},
      );
      return;
    }

    let cancelled = false;
    let timeoutId: number | null = null;

    const scheduleRefresh = (delayMs: number) => {
      if (cancelled) {
        return;
      }

      timeoutId = window.setTimeout(() => {
        void loadLiveAgentRunCounts();
      }, delayMs);
    };

    const loadLiveAgentRunCounts = async () => {
      try {
        const counts = (await boardListAgentLiveRunCounts(
          selectedCompanyId,
        )) as AgentLiveRunCountRecord[];
        if (cancelled) {
          return;
        }

        const nextCounts = Object.fromEntries(
          counts.map((entry) => [entry.agent_id, entry.live_count]),
        );
        const hasLiveRuns = Object.values(nextCounts).some(
          (count) => count > 0,
        );

        startTransition(() => {
          setLiveAgentRunCountsByAgentId(nextCounts);
        });

        scheduleRefresh(hasLiveRuns ? 2000 : 10_000);
      } catch (error) {
        if (cancelled) {
          return;
        }

        setStatusMessage(
          error instanceof Error ? error.message : String(error),
        );
        scheduleRefresh(5000);
      }
    };

    void loadLiveAgentRunCounts();

    return () => {
      cancelled = true;
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
      }
    };
  }, [bootstrap?.state, selectedCompanyId]);

  useEffect(() => {
    if (bootstrap?.state !== "ready" || !selectedCompanyId) {
      setIssueRunCardUpdatesByIssueId((current) =>
        Object.keys(current).length === 0 ? current : {},
      );
      return;
    }

    if (activityVisibleIssues.length === 0) {
      setIssueRunCardUpdatesByIssueId((current) =>
        Object.keys(current).length === 0 ? current : {},
      );
      return;
    }

    let cancelled = false;
    let timeoutId: number | null = null;

    const scheduleRefresh = (delayMs: number) => {
      if (cancelled) {
        return;
      }

      timeoutId = window.setTimeout(() => {
        void loadIssueRunCardUpdates();
      }, delayMs);
    };

    const loadIssueRunCardUpdates = async () => {
      try {
        const updates = (await boardListIssueRunCardUpdates(
          selectedCompanyId,
        )) as IssueRunCardUpdateRecord[];
        if (cancelled) {
          return;
        }

        const nextUpdates = Object.fromEntries(
          updates.map((update) => [update.issue_id, update]),
        );
        const hasLiveUpdates = Object.values(nextUpdates).some(
          (update) =>
            update.run_status === "queued" || update.run_status === "running",
        );

        startTransition(() => {
          setIssueRunCardUpdatesByIssueId(nextUpdates);
          setCompanySnapshot((current) => {
            if (!current) {
              return current;
            }

            let hasChanges = false;
            const nextIssues = current.issues.map((issue) => {
              const update = nextUpdates[issue.id];
              if (!update || issue.status === update.issue_status) {
                return issue;
              }

              hasChanges = true;
              return { ...issue, status: update.issue_status };
            });

            return hasChanges ? { ...current, issues: nextIssues } : current;
          });
        });

        scheduleRefresh(hasLiveUpdates ? 2000 : 10_000);
      } catch (error) {
        if (cancelled) {
          return;
        }

        setStatusMessage(
          error instanceof Error ? error.message : String(error),
        );
        scheduleRefresh(5000);
      }
    };

    void loadIssueRunCardUpdates();

    return () => {
      cancelled = true;
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
      }
    };
  }, [bootstrap?.state, activityVisibleIssueIdsKey, selectedCompanyId]);

  useEffect(() => {
    if (issuesRouteMode === "detail" && !selectedIssueId) {
      setIssuesRouteMode("list");
    }
  }, [issuesRouteMode, selectedIssueId]);

  useEffect(() => {
    if (!dashboardIssuePreviewId) {
      setDashboardPreviewIssueDetail(null);
      setIsDashboardIssuePreviewLoading(false);
      setDashboardIssuePreviewError(null);
      return;
    }

    if (selectedScreen !== "dashboard" || !selectedCompanyId) {
      setDashboardIssuePreviewId(null);
      setDashboardPreviewIssueDetail(null);
      setIsDashboardIssuePreviewLoading(false);
      setDashboardIssuePreviewError(null);
      return;
    }

    let cancelled = false;
    setDashboardPreviewIssueDetail((current) =>
      current?.id === dashboardIssuePreviewId ? current : null,
    );
    setIsDashboardIssuePreviewLoading(true);
    setDashboardIssuePreviewError(null);

    const loadDashboardIssuePreview = async () => {
      try {
        const [freshIssue, comments, attachments] = await Promise.all([
          boardGetIssue(dashboardIssuePreviewId),
          boardListIssueComments(dashboardIssuePreviewId),
          boardListIssueAttachments(dashboardIssuePreviewId),
        ]);

        if (cancelled) {
          return;
        }

        const detailIssue = freshIssue as IssueRecord;
        setDashboardPreviewIssueDetail(detailIssue);
        setIssueCommentsByIssueId((current) => ({
          ...current,
          [dashboardIssuePreviewId]: comments as IssueCommentRecord[],
        }));
        setIssueAttachmentsByIssueId((current) => ({
          ...current,
          [dashboardIssuePreviewId]: attachments as IssueAttachmentRecord[],
        }));
        setDashboardIssuePreviewError(null);
      } catch (error) {
        if (!cancelled) {
          setDashboardIssuePreviewError(
            error instanceof Error ? error.message : String(error),
          );
        }
      } finally {
        if (!cancelled) {
          setIsDashboardIssuePreviewLoading(false);
        }
      }
    };

    void loadDashboardIssuePreview();

    return () => {
      cancelled = true;
    };
  }, [dashboardIssuePreviewId, selectedCompanyId, selectedScreen]);

  useEffect(() => {
    if (isDashboardOverviewLoading) {
      return;
    }

    if (
      dashboardIssuePreviewId &&
      !dashboardOverviewChats.some(
        (chat) => chat.id === dashboardIssuePreviewId,
      )
    ) {
      setDashboardIssuePreviewId(null);
      setDashboardPreviewIssueDetail(null);
      setDashboardIssuePreviewError(null);
      setIsDashboardIssuePreviewLoading(false);
    }
  }, [
    dashboardIssuePreviewId,
    dashboardOverviewChats,
    isDashboardOverviewLoading,
  ]);

  useEffect(() => {
    if (!selectedIssue || issuesRouteMode !== "detail") {
      setIssueEditorError(null);
      return;
    }

    let cancelled = false;

    const loadIssueDetailState = async () => {
      try {
        const [freshIssue, comments, attachments] = await Promise.all([
          boardGetIssue(selectedIssue.id),
          boardListIssueComments(selectedIssue.id),
          boardListIssueAttachments(selectedIssue.id),
        ]);

        if (cancelled) {
          return;
        }

        const detailIssue = freshIssue as IssueRecord;
        setCompanySnapshot((current) => {
          if (!current) {
            return current;
          }

          return {
            ...current,
            issues: current.issues.map((issue) =>
              issue.id === detailIssue.id ? detailIssue : issue,
            ),
          };
        });
        setIssueDraft(createIssueDraft(detailIssue));
        setIssueCommentsByIssueId((current) => ({
          ...current,
          [selectedIssue.id]: comments as IssueCommentRecord[],
        }));
        setIssueAttachmentsByIssueId((current) => ({
          ...current,
          [selectedIssue.id]: attachments as IssueAttachmentRecord[],
        }));
        setIssueEditorError(null);
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
    };

    void loadIssueDetailState();

    return () => {
      cancelled = true;
    };
  }, [issuesRouteMode, selectedIssue?.id]);

  useEffect(() => {
    if (selectedAgent) {
      setAgentConfigDraft(createAgentConfigDraft(selectedAgent));
    } else {
      setAgentConfigDraft(createEmptyAgentConfigDraft());
    }
    setAgentConfigError(null);
    setIsSavingAgentConfig(false);
  }, [selectedAgent?.id, selectedAgent?.updated_at]);

  useEffect(() => {
    selectedAgentIdRef.current = selectedAgent?.id ?? null;
  }, [selectedAgent?.id]);

  useEffect(() => {
    if (selectedScreen === "agents" || selectedScreen === "approvals") {
      setSelectedScreen("issues");
    }
  }, [selectedScreen]);

  useEffect(() => {
    selectedAgentRunIdRef.current = selectedAgentRunId;
  }, [selectedAgentRunId]);

  useEffect(() => {
    if (selectedScreen === "agents") {
      return;
    }

    setAgentsRouteMode("dashboard");
    resetAgentRunsState();
  }, [selectedScreen]);

  useEffect(() => {
    if (
      selectedScreen === "agents" &&
      agentsRouteMode === "runs" &&
      selectedAgent
    ) {
      return;
    }

    resetAgentRunsState();
  }, [agentsRouteMode, selectedAgent?.id, selectedScreen]);

  useEffect(() => {
    if (selectedScreen !== "agents" || agentsRouteMode !== "runs") {
      return;
    }

    resetAgentRunsState();
  }, [agentsRouteMode, selectedAgent?.id, selectedScreen]);

  useEffect(() => {
    if (
      selectedScreen !== "agents" ||
      agentsRouteMode !== "runs" ||
      !selectedAgent
    ) {
      return;
    }

    void loadAgentRuns(true);
  }, [agentsRouteMode, selectedAgent?.id, selectedScreen]);

  useEffect(() => {
    if (
      selectedScreen !== "agents" ||
      agentsRouteMode !== "runs" ||
      !selectedAgentRunId
    ) {
      return;
    }

    void refreshSelectedAgentRun(true);
  }, [agentsRouteMode, selectedAgentRunId, selectedScreen]);

  useEffect(() => {
    if (
      selectedScreen !== "agents" ||
      agentsRouteMode !== "runs" ||
      !selectedAgentRunIsLive
    ) {
      return;
    }

    let cancelled = false;

    const pollAgentRun = async () => {
      while (!cancelled) {
        await new Promise((resolve) => window.setTimeout(resolve, 2000));
        if (cancelled) {
          return;
        }

        await loadAgentRuns(false);
        await refreshSelectedAgentRun(false);
      }
    };

    void pollAgentRun();

    return () => {
      cancelled = true;
    };
  }, [
    agentsRouteMode,
    selectedAgent?.id,
    selectedAgentRun?.id,
    selectedAgentRunIsLive,
    selectedScreen,
  ]);

  useEffect(() => {
    if (selectedScreen !== "activity") {
      return;
    }

    if (activityMissingCommentIssueIds.length === 0) {
      return;
    }

    let cancelled = false;

    const loadActivityComments = async () => {
      const results = await Promise.allSettled(
        activityMissingCommentIssueIds.map(
          async (issueId) =>
            [issueId, await boardListIssueComments(issueId)] as const,
        ),
      );

      if (cancelled) {
        return;
      }

      const nextComments: Array<[string, IssueCommentRecord[]]> = [];
      let nextError: string | null = null;

      for (const result of results) {
        if (result.status === "fulfilled") {
          nextComments.push([
            result.value[0],
            result.value[1] as IssueCommentRecord[],
          ]);
          continue;
        }

        if (!nextError) {
          nextError =
            result.reason instanceof Error
              ? result.reason.message
              : String(result.reason);
        }
      }

      if (nextComments.length > 0) {
        startTransition(() => {
          setIssueCommentsByIssueId((current) => {
            const merged = { ...current };
            for (const [issueId, comments] of nextComments) {
              merged[issueId] = comments;
            }
            return merged;
          });
        });
      }

      if (nextError) {
        setStatusMessage(nextError);
      }
    };

    void loadActivityComments();

    return () => {
      cancelled = true;
    };
  }, [activityMissingCommentIssueIds, selectedScreen]);

  useEffect(() => {
    if (!selectedBoardWorkspace) {
      return;
    }

    startTransition(() => {
      if (
        selectedBoardWorkspace.repository_id &&
        selectedBoardWorkspace.repository_id !== selectedRepositoryId
      ) {
        setSelectedRepositoryId(selectedBoardWorkspace.repository_id);
      }

      if (
        selectedBoardWorkspace.session_id &&
        selectedBoardWorkspace.session_id !== selectedSessionId
      ) {
        setSelectedSessionId(selectedBoardWorkspace.session_id);
      }

      setWorkspaceCenterTab("conversation");
    });
  }, [
    selectedBoardWorkspace?.id,
    selectedBoardWorkspace?.repository_id,
    selectedBoardWorkspace?.session_id,
  ]);

  useEffect(() => {
    if (
      selectedScreen !== "issues" ||
      issuesRouteMode !== "detail" ||
      !selectedIssueWorkspace ||
      selectedIssueWorkspace.id === selectedBoardWorkspaceId
    ) {
      return;
    }

    startTransition(() => {
      setSelectedBoardWorkspaceId(selectedIssueWorkspace.id);
    });
  }, [
    issuesRouteMode,
    selectedBoardWorkspaceId,
    selectedIssueWorkspace?.id,
    selectedScreen,
  ]);

  useEffect(() => {
    if (!selectedRepositoryId || bootstrap?.state !== "ready") {
      return;
    }

    let cancelled = false;
    const loadRepositorySessions = async () => {
      try {
        const nextSessions = (await sessionList(
          selectedRepositoryId,
        )) as SessionRecord[];
        if (cancelled) {
          return;
        }

        startTransition(() => {
          setSessions(nextSessions);
          setSelectedSessionId((current) => {
            const boardWorkspaceSessionId =
              selectedBoardWorkspace?.repository_id === selectedRepositoryId
                ? selectedBoardWorkspace.session_id
                : null;
            if (
              boardWorkspaceSessionId &&
              nextSessions.some(
                (session) => session.id === boardWorkspaceSessionId,
              )
            ) {
              return boardWorkspaceSessionId;
            }
            if (
              current &&
              nextSessions.some((session) => session.id === current)
            ) {
              return current;
            }
            return nextSessions[0]?.id ?? null;
          });
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
    };

    void loadRepositorySessions();

    void persistSettings({
      ...settings,
      preferred_repository_id: selectedRepositoryId,
    });

    return () => {
      cancelled = true;
    };
  }, [
    bootstrap?.state,
    selectedBoardWorkspace?.repository_id,
    selectedBoardWorkspace?.session_id,
    selectedRepositoryId,
  ]);

  useEffect(() => {
    if (!selectedSessionId || bootstrap?.state !== "ready") {
      setFileEntries([]);
      setSelectedFilePath(null);
      setSelectedFile(null);
      setSelectedDiff(null);
      setGitState(null);
      setGitHistory(null);
      setBranchState(null);
      return;
    }

    let cancelled = false;

    const loadWorkspace = async () => {
      try {
        const [nextFiles, nextGit, nextHistory, nextBranches] =
          await Promise.all([
            repositoryListFiles(selectedSessionId, ""),
            gitStatus(selectedSessionId),
            gitLog(selectedSessionId),
            gitBranches(selectedSessionId),
          ]);

        if (cancelled) {
          return;
        }

        startTransition(() => {
          setFileEntries(nextFiles as FileEntry[]);
          setCurrentDirectory("");
          setSelectedDiff(null);
          setGitState(nextGit as GitStatusResult);
          setGitHistory(nextHistory as GitLogResult);
          setBranchState(nextBranches as GitBranchesResult);
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      }
    };

    void loadWorkspace();

    return () => {
      cancelled = true;
    };
  }, [bootstrap?.state, selectedSessionId]);

  useEffect(() => {
    let unlistenEvents: (() => void) | undefined;
    let unlistenErrors: (() => void) | undefined;

    void listenToSessionEvents((payload) => {
      handleSessionEvent(payload);
    }).then((cleanup) => {
      unlistenEvents = cleanup;
    });

    void listenToSessionStreamErrors((payload) => {
      sessionStateManager.handleStreamError(payload);
      setStatusMessage(payload.message);
    }).then((cleanup) => {
      unlistenErrors = cleanup;
    });

    return () => {
      unlistenEvents?.();
      unlistenErrors?.();
    };
  }, [selectedSessionId, sessionStateManager]);

  useEffect(() => {
    if (bootstrap?.state !== "ready" || dependencyCheck) {
      return;
    }

    let cancelled = false;

    void systemCheckDependencies()
      .then((result) => {
        if (!cancelled) {
          setDependencyCheck(result);
        }
      })
      .catch((error) => {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error),
          );
        }
      });

    return () => {
      cancelled = true;
    };
  }, [bootstrap?.state, dependencyCheck]);

  useEffect(() => {
    const terminal = terminalRef.current;
    if (!terminal) {
      return;
    }

    terminal.clear();
    const transcript = buildTerminalTranscript(deferredMessages);
    if (!transcript) {
      terminal.writeln("No terminal output yet.");
      return;
    }

    terminal.write(transcript.replaceAll("\n", "\r\n"));
  }, [deferredMessages]);

  const retryBootstrap = async () => {
    setStatusMessage(null);
    setBootstrap(null);

    try {
      const status = await desktopBootstrap();
      setBootstrap(status);
      if (status.state === "ready") {
        const [
          loadedSettings,
          loadedCompanies,
          loadedRepositories,
          loadedSpaceScope,
        ] = await Promise.all([
          settingsGet(),
          boardListCompanies(),
          repositoryList(),
          spaceGetCurrent().catch(() => null),
        ]);
        const companiesValue = loadedCompanies as Company[];
        const repositoriesValue = loadedRepositories as RepositoryRecord[];
        const nextSettings = mergeDesktopSettings(loadedSettings);
        const nextCompanyId =
          nextSettings.preferred_company_id ?? companiesValue[0]?.id ?? null;
        const nextRepositoryId =
          nextSettings.preferred_repository_id ??
          repositoriesValue[0]?.id ??
          null;

        setSettings(nextSettings);
        setCompanies(companiesValue);
        setRepositories(repositoriesValue);
        setCurrentSpaceScope(loadedSpaceScope);
        setSelectedScreen(normalizeScreen(nextSettings.preferred_view));
        setSelectedCompanyId(nextCompanyId);
        setSelectedRepositoryId(nextRepositoryId);
      }
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleSessionEvent = (payload: SessionStreamPayload) => {
    sessionStateManager.handleSessionEvent(payload);
    if (payload.session_id !== selectedSessionId) {
      return;
    }

    if (refreshTimeoutRef.current !== null) {
      window.clearTimeout(refreshTimeoutRef.current);
    }

    refreshTimeoutRef.current = window.setTimeout(() => {
      void refreshActiveWorkspaceArtifacts(payload.session_id);
    }, 120);
  };

  const refreshActiveWorkspaceArtifacts = async (sessionId: string) => {
    try {
      const [nextFiles, nextGit, nextHistory, nextBranches] = await Promise.all(
        [
          repositoryListFiles(sessionId, currentDirectory),
          gitStatus(sessionId),
          gitLog(sessionId),
          gitBranches(sessionId),
        ],
      );
      setFileEntries(nextFiles as FileEntry[]);
      setGitState(nextGit as GitStatusResult);
      setGitHistory(nextHistory as GitLogResult);
      setBranchState(nextBranches as GitBranchesResult);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const refreshBoardData = async () => {
    if (!selectedCompanyId) {
      return;
    }

    try {
      const [loadedCompanies, boardData] = await Promise.all([
        boardListCompanies(),
        selectedScreen === "dashboard"
          ? boardDashboardOverview(selectedCompanyId)
          : boardCompanySnapshot(selectedCompanyId),
      ]);
      setCompanies(loadedCompanies as Company[]);
      if (selectedScreen === "dashboard") {
        setDashboardOverview(boardData as DashboardOverviewRecord);
      } else {
        setCompanySnapshot(boardData as CompanySnapshot);
      }
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleSelectScreen = (screen: AppScreen) => {
    if (screen === "issues") {
      setIssuesRouteMode("list");
    }
    setSelectedScreen(screen);
    void persistSettings({
      ...settings,
      preferred_view: preferredViewForScreen(screen),
    });
  };

  const handleSelectCompany = (companyId: string) => {
    setCompanyContextMenu(null);
    if (companyId !== selectedCompanyId) {
      setCompanySnapshot(null);
      setDashboardOverview(null);
    }
    startTransition(() => {
      setSelectedCompanyId(companyId);
      setSelectedScreen("dashboard");
      setSelectedIssueId(null);
      setIssuesRouteMode("list");
      setIssueCommentsByIssueId({});
      setSelectedApprovalId(null);
    });
    void persistSettings({
      ...settings,
      preferred_company_id: companyId,
      preferred_view: preferredViewForScreen("dashboard"),
    });
  };

  const handleSelectCompanyScreen = (
    companyId: string,
    screen: CompanyContextMenuScreen,
  ) => {
    if (screen === "dashboard") {
      handleSelectCompany(companyId);
      return;
    }

    setCompanyContextMenu(null);
    if (companyId !== selectedCompanyId) {
      setCompanySnapshot(null);
      setDashboardOverview(null);
    }
    startTransition(() => {
      setSelectedCompanyId(companyId);
      setSelectedScreen(screen);
      if (screen === "issues") {
        setIssuesRouteMode("list");
        setSelectedIssueId(null);
      }
    });

    void persistSettings({
      ...settings,
      preferred_company_id: companyId,
      preferred_view: preferredViewForScreen(screen),
    });
  };

  const handleSelectCompanyAgent = (companyId: string, agentId: string) => {
    setCompanyContextMenu(null);
    if (companyId !== selectedCompanyId) {
      setCompanySnapshot(null);
      setDashboardOverview(null);
    }
    startTransition(() => {
      setSelectedCompanyId(companyId);
      setSelectedAgentId(agentId);
      setSelectedScreen("agents");
      setAgentsRouteMode("dashboard");
      setSelectedIssueId(null);
      setSelectedApprovalId(null);
      setIssuesRouteMode("list");
      setIssueCommentsByIssueId({});
    });

    void persistSettings({
      ...settings,
      preferred_company_id: companyId,
      preferred_view: preferredViewForScreen("agents"),
    });
  };

  const handleOpenCompanyContextMenu = (
    event: MouseEvent<HTMLButtonElement>,
    company: Company,
  ) => {
    event.preventDefault();
    event.stopPropagation();

    const menuWidth = 264;
    const menuHeight = 520;
    const viewportPadding = 12;
    const initialAgents =
      company.id === selectedCompanyId && companySnapshot
        ? orderSidebarAgents(
            companySnapshot.agents ?? [],
            typeof companySnapshot.company?.ceo_agent_id === "string"
              ? companySnapshot.company.ceo_agent_id
              : null,
          )
        : [];
    const nextX = Math.min(
      Math.max(event.clientX + 12, viewportPadding),
      window.innerWidth - menuWidth - viewportPadding,
    );
    const nextY = Math.min(
      Math.max(event.clientY - 8, viewportPadding),
      window.innerHeight - menuHeight - viewportPadding,
    );

    setCompanyContextMenu({
      agents: initialAgents,
      companyId: company.id,
      companyName: company.name,
      isLoadingAgents:
        initialAgents.length === 0 && bootstrap?.state === "ready",
      x: nextX,
      y: nextY,
    });
  };

  const handleDashboardCanvasPointerDown = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    if (event.button !== 0) {
      return;
    }

    const target = event.target as HTMLElement | null;
    if (target?.closest("button, a, input, textarea, select, label")) {
      return;
    }

    dashboardCanvasPanRef.current = {
      pointerId: event.pointerId,
      originX: dashboardCanvasOffset.x,
      originY: dashboardCanvasOffset.y,
      startX: event.clientX,
      startY: event.clientY,
    };
    event.preventDefault();
    window.getSelection()?.removeAllRanges();
    setIsDashboardCanvasDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const handleDashboardCanvasPointerMove = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    const panState = dashboardCanvasPanRef.current;
    if (!panState || panState.pointerId !== event.pointerId) {
      return;
    }

    setDashboardCanvasOffset(
      clampDashboardOffset({
        x: panState.originX + event.clientX - panState.startX,
        y: panState.originY + event.clientY - panState.startY,
      }),
    );
  };

  const handleDashboardCanvasPointerEnd = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    if (dashboardCanvasPanRef.current?.pointerId !== event.pointerId) {
      return;
    }

    dashboardCanvasPanRef.current = null;
    setIsDashboardCanvasDragging(false);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const handleDashboardCanvasWheel = (event: WheelEvent<HTMLDivElement>) => {
    if (!dashboardProjectColumns.length) {
      return;
    }

    const target = event.target as HTMLElement | null;
    if (target?.closest("input, textarea, select, .shadcn-select-content")) {
      return;
    }

    event.preventDefault();
    const wheelZoomState = dashboardCanvasWheelZoomRef.current;
    const resetThresholdMs = 180;
    if (event.timeStamp - wheelZoomState.lastEventTime > resetThresholdMs) {
      wheelZoomState.accumulatedDeltaY = 0;
    }

    wheelZoomState.lastEventTime = event.timeStamp;
    wheelZoomState.accumulatedDeltaY += event.deltaY;

    const isTrackpadPinch = event.ctrlKey;
    const threshold = event.deltaMode === 1 ? 1 : isTrackpadPinch ? 6 : 16;
    if (Math.abs(wheelZoomState.accumulatedDeltaY) < threshold) {
      return;
    }

    const zoomDelta = wheelZoomState.accumulatedDeltaY < 0 ? 1 : -1;
    wheelZoomState.accumulatedDeltaY = 0;
    const viewportRect = event.currentTarget.getBoundingClientRect();

    nudgeDashboardCanvasZoom(zoomDelta, {
      x: event.clientX - viewportRect.left,
      y: event.clientY - viewportRect.top,
    });
  };

  const setDashboardCanvasZoom = (
    nextZoomIndex: number | ((currentZoomIndex: number) => number),
    anchor?: DashboardCanvasOffset,
  ) => {
    const viewport = dashboardCanvasViewportRef.current;
    if (!viewport) {
      setDashboardCanvasZoomIndex((currentZoomIndex) =>
        clampNumber(
          typeof nextZoomIndex === "function"
            ? nextZoomIndex(currentZoomIndex)
            : nextZoomIndex,
          0,
          dashboardCanvasZoomLevels.length - 1,
        ),
      );
      return;
    }

    setDashboardCanvasZoomIndex((currentZoomIndex) => {
      const safeZoomIndex = clampNumber(
        typeof nextZoomIndex === "function"
          ? nextZoomIndex(currentZoomIndex)
          : nextZoomIndex,
        0,
        dashboardCanvasZoomLevels.length - 1,
      );
      if (safeZoomIndex === currentZoomIndex) {
        return currentZoomIndex;
      }

      const currentZoomScale = dashboardCanvasZoomLevels[currentZoomIndex] ?? 1;
      const nextZoomScale = dashboardCanvasZoomLevels[safeZoomIndex] ?? 1;
      const anchorX = anchor?.x ?? viewport.clientWidth / 2;
      const anchorY = anchor?.y ?? viewport.clientHeight / 2;

      setDashboardCanvasOffset((currentOffset) => {
        const worldX = (anchorX - currentOffset.x) / currentZoomScale;
        const worldY = (anchorY - currentOffset.y) / currentZoomScale;

        return clampDashboardCanvasOffset(
          {
            x: anchorX - worldX * nextZoomScale,
            y: anchorY - worldY * nextZoomScale,
          },
          viewport.clientWidth,
          viewport.clientHeight,
          dashboardCanvasBounds,
          nextZoomScale,
        );
      });

      return safeZoomIndex;
    });
  };

  const nudgeDashboardCanvasZoom = (
    zoomDelta: number,
    anchor?: DashboardCanvasOffset,
  ) => {
    setDashboardCanvasZoom(
      (currentZoomIndex) => currentZoomIndex + zoomDelta,
      anchor,
    );
  };

  const handleDashboardCanvasZoomChange = (nextZoomIndex: number) => {
    setDashboardCanvasZoom(nextZoomIndex);
  };

  const handleSelectBoardWorkspace = (workspace: WorkspaceRecord) => {
    setSelectedBoardWorkspaceId(workspace.id);

    if (workspace.issue_id) {
      void handleSelectIssue(workspace.issue_id);
      return;
    }

    setStatusMessage("This worktree is not linked to a conversation.");
  };

  const handleSelectAgent = (agentId: string) => {
    setSelectedAgentId(agentId);
    handleSelectScreen("agents");
  };

  const handleSelectProjectSidebar = (projectId: string) => {
    setSelectedProjectId(projectId);
    handleSelectScreen("projects");
  };

  const handleSelectAgentTab = (tab: AgentsRouteMode) => {
    setAgentsRouteMode(tab);
  };

  const handleProjectBoardGroupingChange = (
    projectId: string,
    viewId: string,
    grouping: DashboardProjectGrouping,
  ) => {
    const currentProjectViews = dashboardProjectViews[projectId] ?? {};
    const currentSavedViews = dashboardProjectSavedViews(
      currentProjectViews.saved_views,
    );

    void applySettingsPatch({
      dashboard_project_views: {
        ...dashboardProjectViews,
        [projectId]: {
          ...currentProjectViews,
          ...(viewId === dashboardDefaultProjectViewId
            ? {
                group_by: grouping,
              }
            : {
                saved_views: currentSavedViews.map((savedView) =>
                  savedView.id === viewId
                    ? {
                        ...savedView,
                        group_by: grouping,
                      }
                    : savedView,
                ),
              }),
        },
      },
    });
  };

  const handleCreateProjectBoardView = async (
    projectId: string,
    draft: DashboardProjectViewDraft,
  ) => {
    const currentProjectViews = dashboardProjectViews[projectId] ?? {};
    const currentSavedViews = dashboardProjectSavedViews(
      currentProjectViews.saved_views,
    );

    await applySettingsPatch({
      dashboard_project_views: {
        ...dashboardProjectViews,
        [projectId]: {
          ...currentProjectViews,
          saved_views: [
            ...currentSavedViews,
            {
              group_by: draft.grouping,
              id: createDashboardProjectViewId(),
              name: normalizeOptionalDraftString(draft.name),
            },
          ],
        },
      },
    });
  };

  const handleDeleteProject = async (projectId: string) => {
    if (!selectedCompanyId) {
      return;
    }

    const deletedProject = await boardDeleteProject(projectId);
    const snapshot = await boardCompanySnapshot(selectedCompanyId);
    setCompanySnapshot(snapshot);
    setStatusMessage(`Deleted project ${deletedProject.name}.`);
  };

  const handleUpdateProjectDefaultNewChatArea = async (
    projectId: string,
    defaultNewChatArea: ProjectDefaultNewChatArea,
  ) => {
    if (!selectedCompanyId) {
      return;
    }

    const currentProjectRecord =
      boardProjects.find((project) => project.id === projectId) ?? null;
    const updatedProject = await boardUpdateProject({
      project_id: projectId,
      execution_workspace_policy:
        projectExecutionWorkspacePolicyWithDefaultNewChatArea(
          currentProjectRecord,
          defaultNewChatArea,
        ),
    });
    const snapshot = await boardCompanySnapshot(selectedCompanyId);
    setCompanySnapshot(snapshot);
    setStatusMessage(
      `Updated ${updatedProject.name} default new chat area to ${projectDefaultNewChatAreaLabel(defaultNewChatArea)}.`,
    );
  };

  const handleRefreshAgentRuns = async () => {
    await loadAgentRuns(false);
    await refreshSelectedAgentRun(true);
  };

  const handleSelectAgentRun = (runId: string) => {
    setSelectedAgentRunId(runId);
  };

  const handleOpenIssueLinkedRun = (run: AgentRunRecord) => {
    startTransition(() => {
      setSelectedAgentId(run.agent_id);
      setSelectedAgentRunId(run.id);
      setAgentsRouteMode("runs");
      setSelectedScreen("agents");
    });
  };

  const handleCancelSelectedAgentRun = async () => {
    if (!selectedAgentRun) {
      return;
    }

    await performAgentRunAction(() => boardCancelAgentRun(selectedAgentRun.id));
  };

  const handleRetrySelectedAgentRun = async () => {
    if (!selectedAgentRun) {
      return;
    }

    await performAgentRunAction(() => boardRetryAgentRun(selectedAgentRun.id));
  };

  const handleResumeSelectedAgentRun = async () => {
    if (!selectedAgentRun) {
      return;
    }

    await performAgentRunAction(() => boardResumeAgentRun(selectedAgentRun.id));
  };

  const handleChooseAgentWorkingDirectory = async () => {
    setAgentConfigError(null);
    try {
      const path = await desktopPickRepositoryDirectory();
      if (path) {
        setAgentConfigDraft((current) => ({
          ...current,
          workingDirectory: path,
        }));
      }
    } catch (error) {
      setAgentConfigError(
        error instanceof Error ? error.message : String(error),
      );
    }
  };

  const handleChooseAgentInstructionsFile = async () => {
    setAgentConfigError(null);
    try {
      const path = await desktopPickFile();
      if (path) {
        setAgentConfigDraft((current) => ({
          ...current,
          instructionsPath: path,
        }));
      }
    } catch (error) {
      setAgentConfigError(
        error instanceof Error ? error.message : String(error),
      );
    }
  };

  const handleAgentConfigEnvVarChange = (
    envId: string,
    patch: Partial<AgentConfigEnvVarDraft>,
  ) => {
    setAgentConfigDraft((current) => ({
      ...current,
      envVars: current.envVars.map((envVar) =>
        envVar.id === envId ? { ...envVar, ...patch } : envVar,
      ),
    }));
  };

  const handleAddAgentConfigEnvVar = () => {
    setAgentConfigDraft((current) => ({
      ...current,
      envVars: [...current.envVars, createAgentConfigEnvVarDraft()],
    }));
  };

  const handleRemoveAgentConfigEnvVar = (envId: string) => {
    setAgentConfigDraft((current) => ({
      ...current,
      envVars: current.envVars.filter((envVar) => envVar.id !== envId),
    }));
  };

  const handleSaveAgentConfiguration = async () => {
    if (!selectedAgent) {
      return;
    }

    setIsSavingAgentConfig(true);
    setAgentConfigError(null);

    try {
      const updatedAgent = await boardUpdateAgent(
        buildAgentConfigUpdateParams(selectedAgent, agentConfigDraft),
      );
      setCompanySnapshot((current) =>
        current
          ? {
              ...current,
              agents: current.agents.map((agent) =>
                agent.id === updatedAgent.id ? updatedAgent : agent,
              ),
            }
          : current,
      );
      setAgentConfigDraft(createAgentConfigDraft(updatedAgent));
    } catch (error) {
      setAgentConfigError(
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setIsSavingAgentConfig(false);
    }
  };

  const handleCompanyBrandColorChange = async (nextColor: string) => {
    if (!selectedCompanyId) {
      return;
    }

    const normalizedColor = normalizeHexColor(nextColor);
    setCompanyBrandColorDraft(normalizedColor);
    setCompanyBrandColorError(null);
    setIsSavingCompanyBrandColor(true);

    try {
      const updatedCompany = await boardUpdateCompany({
        company_id: selectedCompanyId,
        brand_color: normalizedColor,
      });

      setCompanySnapshot((current) =>
        current
          ? {
              ...current,
              company: updatedCompany,
            }
          : current,
      );
      setCompanies((current) =>
        current.map((company) =>
          company.id === updatedCompany.id
            ? { ...company, ...updatedCompany }
            : company,
        ),
      );
    } catch (error) {
      setCompanyBrandColorDraft(
        normalizeHexColor(selectedCompany?.brand_color),
      );
      setCompanyBrandColorError(
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setIsSavingCompanyBrandColor(false);
    }
  };

  const handleAddRepository = async () => {
    if (!selectedCompanyId) {
      return;
    }

    try {
      const path = await desktopPickRepositoryDirectory();
      if (!path) {
        return;
      }

      const name = path.split("/").pop() || path;
      const params: Record<string, unknown> = {
        company_id: selectedCompanyId,
        name,
        repo_path: path.trim(),
      };

      const project = await boardCreateProject(params);
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setSelectedProjectId(project.id);
      setSelectedScreen("projects");
    } catch (error) {
      console.error("Failed to add repository:", error);
    }
  };

  const resetIssueDialog = () => {
    const runtimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);
    setIssueDialogMode("conversation");
    setIssueDialogTitle("");
    setIssueDialogDescription("");
    setIssueDialogPriority("medium");
    setIssueDialogStatus("backlog");
    setIssueDialogProjectId("");
    setIssueDialogParentIssueId("");
    setIssueDialogCommand(runtimeDraft.command);
    setIssueDialogModel(runtimeDraft.model);
    setIssueDialogThinkingEffort(runtimeDraft.thinkingEffort);
    setIssueDialogPlanMode(runtimeDraft.planMode);
    setIssueDialogEnableChrome(runtimeDraft.enableChrome);
    setIssueDialogSkipPermissions(runtimeDraft.skipPermissions);
    setIssueDialogWorkspaceTargetMode("main");
    setIssueDialogWorkspaceWorktreePath("");
    setIssueDialogWorkspaceWorktreeBranch("");
    setIssueDialogWorkspaceWorktreeName("");
    setIssueDialogAttachments([]);
    setIssueDialogError(null);
    setIsIssueDialogSaving(false);
  };

  const handleIssueDialogProjectChange = (projectId: string) => {
    const nextProject =
      currentProjectsForCreation.find((project) => project.id === projectId) ??
      null;
    const nextWorkspaceDefaults =
      projectDefaultNewChatWorkspaceDefaults(nextProject);
    setIssueDialogProjectId(projectId);
    setIssueDialogError(null);
    setIssueDialogWorkspaceTargetMode(
      nextWorkspaceDefaults.workspaceTargetMode ?? "main",
    );
    setIssueDialogWorkspaceWorktreePath(
      nextWorkspaceDefaults.workspaceWorktreePath ?? "",
    );
    setIssueDialogWorkspaceWorktreeBranch(
      nextWorkspaceDefaults.workspaceWorktreeBranch ?? "",
    );
    setIssueDialogWorkspaceWorktreeName(
      nextWorkspaceDefaults.workspaceWorktreeName ?? "",
    );
  };

  const handleIssueDialogWorkspaceTargetChange = (value: string) => {
    const patch = issueWorkspaceDraftPatchFromSelection(
      value,
      issueDialogWorktreeState.worktrees,
      {
        workspaceWorktreeBranch: issueDialogWorkspaceWorktreeBranch,
        workspaceWorktreeName: issueDialogWorkspaceWorktreeName,
        workspaceWorktreePath: issueDialogWorkspaceWorktreePath,
      },
    );

    setIssueDialogWorkspaceTargetMode(
      (patch.workspaceTargetMode ?? "main") as IssueWorkspaceTargetMode,
    );
    setIssueDialogWorkspaceWorktreePath(patch.workspaceWorktreePath ?? "");
    setIssueDialogWorkspaceWorktreeBranch(patch.workspaceWorktreeBranch ?? "");
    setIssueDialogWorkspaceWorktreeName(patch.workspaceWorktreeName ?? "");
  };

  const handleOpenCreateIssueDialog = (
    defaults?: CreateIssueDialogDefaults,
  ) => {
    const runtimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);
    resetIssueDialog();
    const nextProjectId =
      defaults?.projectId ?? currentProjectsForCreation[0]?.id ?? "";
    const nextProject =
      currentProjectsForCreation.find(
        (project) => project.id === nextProjectId,
      ) ?? null;
    const nextWorkspaceDefaults: Pick<
      IssueEditDraft,
      | "workspaceTargetMode"
      | "workspaceWorktreePath"
      | "workspaceWorktreeBranch"
      | "workspaceWorktreeName"
    > =
      defaults?.workspaceTargetMode != null
        ? {
            workspaceTargetMode: defaults.workspaceTargetMode ?? "main",
            workspaceWorktreePath: defaults.workspaceWorktreePath ?? "",
            workspaceWorktreeBranch: defaults.workspaceWorktreeBranch ?? "",
            workspaceWorktreeName: defaults.workspaceWorktreeName ?? "",
          }
        : projectDefaultNewChatWorkspaceDefaults(nextProject);
    setIssueDialogMode(defaults?.dialogMode ?? "conversation");
    setIssueDialogPriority(defaults?.priority ?? "medium");
    setIssueDialogStatus(
      normalizeBoardIssueValue(defaults?.status ?? "backlog"),
    );
    setIssueDialogProjectId(nextProjectId);
    setIssueDialogParentIssueId(defaults?.parentId ?? "");
    setIssueDialogCommand(defaults?.command ?? runtimeDraft.command);
    setIssueDialogModel(defaults?.model ?? runtimeDraft.model);
    setIssueDialogThinkingEffort(
      defaults?.thinkingEffort ?? runtimeDraft.thinkingEffort,
    );
    setIssueDialogPlanMode(defaults?.planMode ?? runtimeDraft.planMode);
    setIssueDialogEnableChrome(
      defaults?.enableChrome ?? runtimeDraft.enableChrome,
    );
    setIssueDialogSkipPermissions(
      defaults?.skipPermissions ?? runtimeDraft.skipPermissions,
    );
    setIssueDialogWorkspaceTargetMode(
      nextWorkspaceDefaults.workspaceTargetMode ?? "main",
    );
    setIssueDialogWorkspaceWorktreePath(
      nextWorkspaceDefaults.workspaceWorktreePath ?? "",
    );
    setIssueDialogWorkspaceWorktreeBranch(
      nextWorkspaceDefaults.workspaceWorktreeBranch ?? "",
    );
    setIssueDialogWorkspaceWorktreeName(
      nextWorkspaceDefaults.workspaceWorktreeName ?? "",
    );
    if (!nextProjectId && currentProjectsForCreation.length === 0) {
      setIssueDialogError(
        defaults?.dialogMode === "queuedMessage"
          ? "Create a project before queueing messages."
          : "Create a project before creating a conversation.",
      );
    }
    setIsCreateIssueDialogOpen(true);
  };

  const handleCloseCreateIssueDialog = () => {
    setIsCreateIssueDialogOpen(false);
    resetIssueDialog();
  };

  const handleAddIssueDialogAttachment = async () => {
    setIssueDialogError(null);
    try {
      const path = await desktopPickFile();
      if (!path) {
        return;
      }

      setIssueDialogAttachments((current) => {
        if (current.some((attachment) => attachment.path === path)) {
          return current;
        }

        return [...current, { path, name: fileName(path) }];
      });
    } catch (error) {
      setIssueDialogError(
        error instanceof Error ? error.message : String(error),
      );
    }
  };

  const handleRemoveIssueDialogAttachment = (path: string) => {
    setIssueDialogAttachments((current) =>
      current.filter((attachment) => attachment.path !== path),
    );
  };

  const createIssueWithDefaults = async ({
    attachments = [],
    description = "",
    navigateToDetail = false,
    title,
    ...defaults
  }: CreateIssueDialogDefaults & {
    attachments?: IssueAttachmentDraft[];
    description?: string;
    navigateToDetail?: boolean;
    title: string;
  }) => {
    if (!selectedCompanyId) {
      throw new Error("Select a space before creating a conversation.");
    }

    const availableProjectsForCreation =
      boardProjects.length > 0 ? boardProjects : dashboardOverviewProjects;

    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      throw new Error("Conversation title is required.");
    }

    const trimmedProjectId = defaults.projectId?.trim() ?? "";
    const selectedProjectForDefaults =
      availableProjectsForCreation.find(
        (project) => project.id === trimmedProjectId,
      ) ?? null;
    if (!trimmedProjectId) {
      throw new Error(
        availableProjectsForCreation.length === 0
          ? "Create a project before creating a conversation."
          : "Project is required.",
      );
    }

    const runtimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);
    const params: Record<string, unknown> = {
      company_id: selectedCompanyId,
      title: trimmedTitle,
      status: normalizeBoardIssueValue(defaults.status ?? "backlog"),
      priority: defaults.priority ?? "medium",
      project_id: trimmedProjectId,
    };

    if (description.trim()) {
      params.description = description.trim();
    }

    if (hiddenExecutionAgentId) {
      params.assignee_agent_id = hiddenExecutionAgentId;
    }

    if (defaults.parentId?.trim()) {
      params.parent_id = defaults.parentId.trim();
    }

    params.assignee_adapter_overrides = issueAdapterOverridesFromDraft({
      command: defaults.command ?? runtimeDraft.command,
      model: defaults.model ?? runtimeDraft.model,
      thinkingEffort: defaults.thinkingEffort ?? runtimeDraft.thinkingEffort,
      planMode: defaults.planMode ?? runtimeDraft.planMode,
      enableChrome: defaults.enableChrome ?? runtimeDraft.enableChrome,
      skipPermissions: defaults.skipPermissions ?? runtimeDraft.skipPermissions,
    });

    const workspaceDefaults: Pick<
      IssueEditDraft,
      | "workspaceTargetMode"
      | "workspaceWorktreePath"
      | "workspaceWorktreeBranch"
      | "workspaceWorktreeName"
    > =
      defaults.workspaceTargetMode != null
        ? {
            workspaceTargetMode: defaults.workspaceTargetMode ?? "main",
            workspaceWorktreePath: defaults.workspaceWorktreePath ?? "",
            workspaceWorktreeBranch: defaults.workspaceWorktreeBranch ?? "",
            workspaceWorktreeName: defaults.workspaceWorktreeName ?? "",
          }
        : projectDefaultNewChatWorkspaceDefaults(selectedProjectForDefaults);
    const executionWorkspaceSettings = issueExecutionWorkspaceSettingsFromDraft(
      workspaceDefaults,
      trimmedProjectId,
    );
    if (executionWorkspaceSettings) {
      params.execution_workspace_settings = executionWorkspaceSettings;
    }

    const createdIssue = await boardCreateIssue(params);
    let uploadedAttachments: IssueAttachmentRecord[] = [];
    let attachmentUploadMessage: string | null = null;

    if (attachments.length > 0) {
      const uploadResults = await Promise.allSettled(
        attachments.map((attachment) =>
          boardAddIssueAttachment({
            company_id: createdIssue.company_id,
            issue_id: createdIssue.id,
            local_file_path: attachment.path,
          }),
        ),
      );

      uploadedAttachments = uploadResults.flatMap((result) =>
        result.status === "fulfilled" ? [result.value] : [],
      );

      const failedUploads = uploadResults.filter(
        (result) => result.status === "rejected",
      );
      if (failedUploads.length > 0) {
        const firstFailure = failedUploads[0];
        attachmentUploadMessage =
          firstFailure.status === "rejected"
            ? firstFailure.reason instanceof Error
              ? firstFailure.reason.message
              : String(firstFailure.reason)
            : null;
      }
    }

    if (navigateToDetail || selectedScreen !== "dashboard") {
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
    } else {
      const overview = await boardDashboardOverview(selectedCompanyId);
      setDashboardOverview(overview);
    }
    if (uploadedAttachments.length > 0) {
      setIssueAttachmentsByIssueId((current) => ({
        ...current,
        [createdIssue.id]: uploadedAttachments,
      }));
    }

    if (navigateToDetail) {
      setSelectedIssueId(createdIssue.id);
      setIssueDraft(createIssueDraft(createdIssue));
      setIssuesRouteMode("detail");
      setSelectedScreen("issues");
      void persistSettings({
        ...settings,
        preferred_view: preferredViewForScreen("issues"),
      });
    } else {
      setSelectedScreen("dashboard");
    }

    if (!hiddenExecutionAgentId) {
      setStatusMessage(
        `${createdIssue.identifier ?? createdIssue.title} created, but this space does not have a default local executor yet.`,
      );
    } else if (attachmentUploadMessage) {
      setStatusMessage(
        `${createdIssue.identifier ?? createdIssue.title} saved, but one or more attachments failed to upload: ${attachmentUploadMessage}`,
      );
    } else if (!navigateToDetail) {
      setStatusMessage(
        `${createdIssue.identifier ?? createdIssue.title} created in ${issueProjectLabel(
          availableProjectsForCreation,
          createdIssue.project_id,
        )}.`,
      );
    }

    return createdIssue;
  };

  const handleCreateIssueFromDialog = async () => {
    if (
      !(selectedCompanyId && issueDialogTitle.trim()) ||
      isIssueDialogSaving
    ) {
      return;
    }

    const trimmedProjectId = issueDialogProjectId.trim();
    if (!trimmedProjectId) {
      setIssueDialogError(
        currentProjectsForCreation.length === 0
          ? issueDialogMode === "queuedMessage"
            ? "Create a project before queueing messages."
            : "Create a project before creating a conversation."
          : "Project is required.",
      );
      return;
    }

    setIsIssueDialogSaving(true);
    setIssueDialogError(null);

    try {
      await createIssueWithDefaults({
        attachments: issueDialogAttachments,
        command: issueDialogCommand,
        description: issueDialogDescription,
        enableChrome: issueDialogEnableChrome,
        model: issueDialogModel,
        navigateToDetail: true,
        parentId: issueDialogParentIssueId,
        planMode: issueDialogPlanMode,
        priority: issueDialogPriority,
        projectId: trimmedProjectId,
        skipPermissions: issueDialogSkipPermissions,
        status: issueDialogStatus,
        thinkingEffort: issueDialogThinkingEffort,
        title: issueDialogTitle,
        workspaceTargetMode: issueDialogWorkspaceTargetMode,
        workspaceWorktreeBranch: issueDialogWorkspaceWorktreeBranch,
        workspaceWorktreeName: issueDialogWorkspaceWorktreeName,
        workspaceWorktreePath: issueDialogWorkspaceWorktreePath,
      });
      handleCloseCreateIssueDialog();
    } catch (error) {
      setIssueDialogError(
        error instanceof Error ? error.message : String(error),
      );
      setIsIssueDialogSaving(false);
    }
  };

  const handleShowIssuesList = (tab?: IssuesListTab) => {
    if (tab) {
      setSelectedIssuesListTab(tab);
    }
    setIssuesRouteMode("list");
    setSelectedScreen("issues");
    void persistSettings({
      ...settings,
      preferred_view: preferredViewForScreen("issues"),
    });
  };

  const handleOpenDashboardIssuePreview = (issueId: string) => {
    setDashboardPreviewIssueDetail((current) =>
      current?.id === issueId ? current : null,
    );
    setDashboardIssuePreviewId(issueId);
    setDashboardIssuePreviewError(null);
  };

  const handleCloseDashboardIssuePreview = () => {
    setDashboardIssuePreviewId(null);
    setDashboardPreviewIssueDetail(null);
    setDashboardIssuePreviewError(null);
    setIsDashboardIssuePreviewLoading(false);
  };

  const handleCreateBirdsEyeChat = async (
    title: string,
    defaults: CreateIssueDialogDefaults,
  ) =>
    createIssueWithDefaults({
      ...defaults,
      navigateToDetail: false,
      title,
    });

  const ensureCurrentCompanySnapshot = async () => {
    if (!selectedCompanyId) {
      throw new Error("Select a space before opening a chat.");
    }

    if (companySnapshot?.company?.id === selectedCompanyId) {
      return companySnapshot;
    }

    const snapshot = await boardCompanySnapshot(selectedCompanyId);
    setCompanySnapshot(snapshot);
    return snapshot;
  };

  const handleOpenDashboardIssueTile = async (issueId: string) => {
    try {
      const snapshot = await ensureCurrentCompanySnapshot();
      const freshIssue = await boardGetIssue(issueId);
      const detailIssue = freshIssue as IssueRecord;
      const nextSnapshot = snapshot
        ? {
            ...snapshot,
            issues: snapshot.issues.some((issue) => issue.id === detailIssue.id)
              ? snapshot.issues.map((issue) =>
                  issue.id === detailIssue.id ? detailIssue : issue,
                )
              : snapshot.issues.concat(detailIssue),
          }
        : null;

      if (nextSnapshot) {
        setCompanySnapshot(nextSnapshot);
      }

      const issueWorkspace =
        nextSnapshot?.workspaces.find((workspace) => {
          if (workspace.issue_id === detailIssue.id) {
            return true;
          }

          if (!detailIssue.workspace_session_id) {
            return false;
          }

          return (
            workspace.id === detailIssue.workspace_session_id ||
            workspace.session_id === detailIssue.workspace_session_id
          );
        }) ?? null;

      startTransition(() => {
        setSelectedIssueId(detailIssue.id);
        setIssueDraft(createIssueDraft(detailIssue));
        setIssuesRouteMode("detail");
        setWorkspaceCenterTab("conversation");
        if (issueWorkspace?.id) {
          setSelectedBoardWorkspaceId(issueWorkspace.id);
        }
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const renderDashboardIssueTile = (
    issueId: string,
    onClose: () => void,
  ): ReactNode => {
    if (
      !selectedIssue ||
      selectedIssue.id !== issueId ||
      issuesRouteMode !== "detail"
    ) {
      return (
        <div className="birds-eye-tile-loading">
          <strong>Loading chat…</strong>
          <span>Hydrating the repo workspace, transcript, and tools.</span>
        </div>
      );
    }

    return (
      <IssueWorkspaceDetailView
        agents={companySnapshot?.agents ?? dashboardOverviewAgents}
        availableStatusOptions={issueStatusOptions}
        dependencyCheck={dependencyCheck}
        embedded
        isSavingIssue={isSavingIssue}
        issue={selectedIssue}
        issueDraft={issueDraft}
        issueEditorError={issueEditorError}
        issueWorkspaceSidebar={null}
        isWorking={isWorking}
        latestCompletionSummary={activeSessionLiveState.latestCompletionSummary}
        onAddAttachment={() => void handleAddIssueAttachment(selectedIssue)}
        onBack={onClose}
        onCommitIssuePatch={(patch) =>
          void handlePersistIssuePatch(selectedIssue, patch)
        }
        onIssueDraftChange={(patch) =>
          setIssueDraft((current) => ({
            ...current,
            ...patch,
          }))
        }
        onPromptChange={setPrompt}
        onRespondToQuestion={(response) =>
          void handleRespondToSessionQuestion(response)
        }
        onRevealRepo={() => {
          if (selectedIssueWorkspace?.workspace_repo_path) {
            void desktopRevealInFinder(
              selectedIssueWorkspace.workspace_repo_path,
            );
          }
        }}
        onRunTerminal={handleRunTerminal}
        onSelectWorkspaceCenterTab={setWorkspaceCenterTab}
        onSendPrompt={(content) => void handleSendConversationPrompt(content)}
        onStopSession={() => {
          if (selectedIssueWorkspace?.session_id) {
            void agentStop(selectedIssueWorkspace.session_id);
          }
        }}
        onStopTerminal={() => {
          if (selectedIssueWorkspace?.session_id) {
            void terminalStop(selectedIssueWorkspace.session_id);
          }
        }}
        onTerminalCommandChange={setTerminalCommand}
        previewTabLabel={previewTabLabel}
        projectLabel={(projectId) =>
          issueProjectLabel(
            boardProjects.length > 0
              ? boardProjects
              : dashboardOverviewProjects,
            projectId,
          )
        }
        projects={
          boardProjects.length > 0 ? boardProjects : dashboardOverviewProjects
        }
        prompt={prompt}
        runtimeStatusValue={
          selectedIssueWorkspace?.session_id
            ? stringifyStatus(selectedIssueWorkspaceLiveState.runtimeStatus)
            : "idle"
        }
        selectableParentIssues={selectableParentIssues}
        selectedDiff={
          selectedIssueWorkspace?.session_id === activeSession?.id
            ? selectedDiff
            : null
        }
        selectedFile={
          selectedIssueWorkspace?.session_id === activeSession?.id
            ? selectedFile
            : null
        }
        selectedFilePath={
          selectedIssueWorkspace?.session_id === activeSession?.id
            ? selectedFilePath
            : null
        }
        session={selectedIssueWorkspaceSession}
        sessionErrorMessage={
          selectedIssueWorkspace?.session_id
            ? selectedIssueWorkspaceLiveState.errorMessage
            : null
        }
        sessionLoading={
          selectedIssueWorkspace?.session_id
            ? selectedIssueWorkspaceLiveState.isLoadingMessages
            : false
        }
        sessionRows={
          selectedIssueWorkspace?.session_id
            ? selectedIssueWorkspaceLiveState.conversationRows
            : []
        }
        statusLabel={issueStatusLabel}
        terminalCommand={terminalCommand}
        terminalContainerRef={terminalContainerRef}
        terminalStatusValue={
          selectedIssueWorkspace?.session_id === activeSession?.id
            ? stringifyStatus(activeTerminalStatusState)
            : "waiting"
        }
        workspace={selectedIssueWorkspace}
        workspaceCenterTab={workspaceCenterTab}
        workspaceTargetErrorMessage={issueDetailWorktreeState.errorMessage}
        workspaceTargetLoading={issueDetailWorktreeState.isLoading}
        workspaceTargetWorktrees={issueDetailWorktreeState.worktrees}
      />
    );
  };

  const handleSelectIssue = async (issueId: string) => {
    setStatusMessage(null);
    try {
      const issue = await boardGetIssue(issueId);
      setSelectedIssueId((issue as IssueRecord).id);
      setIssueDraft(createIssueDraft(issue as IssueRecord));
      setWorkspaceCenterTab("conversation");
      setIssuesRouteMode("detail");
      setSelectedScreen("issues");
      void persistSettings({
        ...settings,
        preferred_view: preferredViewForScreen("issues"),
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleOpenDashboardIssueDetail = async (issueId: string) => {
    handleCloseDashboardIssuePreview();
    await handleSelectIssue(issueId);
  };

  function enqueueIssueUpdate<T>(task: () => Promise<T>) {
    const nextTask = issueUpdateQueueRef.current.then(task, task);
    issueUpdateQueueRef.current = nextTask.then(
      () => undefined,
      () => undefined,
    );
    return nextTask;
  }

  const applyIssueUpdateToSnapshot = (
    updatedIssue: IssueRecord,
    options?: { removeFromSnapshot?: boolean },
  ) => {
    setCompanySnapshot((current) => {
      if (!current) {
        return current;
      }

      const nextIssues = options?.removeFromSnapshot
        ? current.issues.filter((entry) => entry.id !== updatedIssue.id)
        : current.issues.map((entry) =>
            entry.id === updatedIssue.id ? updatedIssue : entry,
          );

      return {
        ...current,
        issues: nextIssues,
      };
    });
  };

  const syncIssueDraftFromUpdate = (
    updatedIssue: IssueRecord,
    patch: Partial<IssueEditDraft>,
  ) => {
    const nextDraftPatch: Partial<IssueEditDraft> = {};

    if (Object.hasOwn(patch, "title")) {
      nextDraftPatch.title = updatedIssue.title;
    }
    if (Object.hasOwn(patch, "description")) {
      nextDraftPatch.description = updatedIssue.description ?? "";
    }
    if (Object.hasOwn(patch, "status")) {
      nextDraftPatch.status = updatedIssue.status;
    }
    if (Object.hasOwn(patch, "priority")) {
      nextDraftPatch.priority = updatedIssue.priority;
    }
    if (Object.hasOwn(patch, "projectId")) {
      nextDraftPatch.projectId = updatedIssue.project_id ?? "";
    }
    if (Object.hasOwn(patch, "assigneeAgentId")) {
      nextDraftPatch.assigneeAgentId = updatedIssue.assignee_agent_id ?? "";
    }
    if (
      Object.hasOwn(patch, "command") ||
      Object.hasOwn(patch, "model") ||
      Object.hasOwn(patch, "thinkingEffort") ||
      Object.hasOwn(patch, "planMode") ||
      Object.hasOwn(patch, "enableChrome") ||
      Object.hasOwn(patch, "skipPermissions")
    ) {
      Object.assign(
        nextDraftPatch,
        parseIssueAdapterOverrides(updatedIssue.assignee_adapter_overrides),
      );
    }
    if (Object.hasOwn(patch, "parentId")) {
      nextDraftPatch.parentId = updatedIssue.parent_id ?? "";
    }
    if (
      Object.hasOwn(patch, "workspaceTargetMode") ||
      Object.hasOwn(patch, "workspaceWorktreePath") ||
      Object.hasOwn(patch, "workspaceWorktreeBranch") ||
      Object.hasOwn(patch, "workspaceWorktreeName")
    ) {
      Object.assign(
        nextDraftPatch,
        parseIssueExecutionWorkspaceSettings(
          updatedIssue.execution_workspace_settings,
        ),
      );
    }

    if (Object.keys(nextDraftPatch).length === 0) {
      return;
    }

    setIssueDraft((current) => ({
      ...current,
      ...nextDraftPatch,
    }));
  };

  const handlePersistIssuePatch = async (
    issue: IssueRecord,
    patch: Partial<IssueEditDraft>,
    options?: { hiddenAt?: string | null },
  ) =>
    enqueueIssueUpdate(async () => {
      const shouldValidateIssueStatus =
        Object.hasOwn(patch, "status") ||
        Object.hasOwn(patch, "assigneeAgentId");
      if (shouldValidateIssueStatus) {
        const validationMessage = issueStatusAssigneeValidationMessage(
          Object.hasOwn(patch, "status") ? patch.status : issueDraft.status,
          Object.hasOwn(patch, "assigneeAgentId")
            ? patch.assigneeAgentId
            : issueDraft.assigneeAgentId,
          boardAgents,
        );
        if (validationMessage) {
          return null;
        }
      }

      const params: Record<string, unknown> = {
        issue_id: issue.id,
      };

      if (Object.hasOwn(patch, "title")) {
        const trimmedTitle = (patch.title ?? "").trim();
        if (!trimmedTitle) {
          setIssueEditorError("Conversation title is required.");
          return null;
        }
        params.title = trimmedTitle;
      }

      if (Object.hasOwn(patch, "description")) {
        const trimmedDescription = (patch.description ?? "").trim();
        params.description = trimmedDescription ? trimmedDescription : null;
      }

      if (Object.hasOwn(patch, "status")) {
        params.status = patch.status;
      }

      if (Object.hasOwn(patch, "priority")) {
        params.priority = patch.priority;
      }

      if (Object.hasOwn(patch, "projectId")) {
        const trimmedProjectId = patch.projectId?.trim() ?? "";
        if (!trimmedProjectId) {
          setIssueEditorError("Project is required.");
          return null;
        }
        params.project_id = trimmedProjectId;
      }

      if (Object.hasOwn(patch, "assigneeAgentId")) {
        params.assignee_agent_id = patch.assigneeAgentId?.trim()
          ? patch.assigneeAgentId.trim()
          : null;
      }

      if (Object.hasOwn(patch, "parentId")) {
        params.parent_id = patch.parentId?.trim()
          ? patch.parentId.trim()
          : null;
      }

      const shouldPersistRuntimeSettings =
        Object.hasOwn(patch, "command") ||
        Object.hasOwn(patch, "model") ||
        Object.hasOwn(patch, "thinkingEffort") ||
        Object.hasOwn(patch, "planMode") ||
        Object.hasOwn(patch, "enableChrome") ||
        Object.hasOwn(patch, "skipPermissions");

      if (shouldPersistRuntimeSettings) {
        params.assignee_adapter_overrides = issueAdapterOverridesFromDraft({
          command: patch.command ?? issueDraft.command,
          model: patch.model ?? issueDraft.model,
          thinkingEffort: patch.thinkingEffort ?? issueDraft.thinkingEffort,
          planMode: patch.planMode ?? issueDraft.planMode,
          enableChrome: patch.enableChrome ?? issueDraft.enableChrome,
          skipPermissions: patch.skipPermissions ?? issueDraft.skipPermissions,
        });
        if (hiddenExecutionAgentId && !issue.assignee_agent_id?.trim()) {
          params.assignee_agent_id = hiddenExecutionAgentId;
        }
      }

      const shouldPersistWorkspaceSettings =
        Object.hasOwn(patch, "workspaceTargetMode") ||
        Object.hasOwn(patch, "workspaceWorktreePath") ||
        Object.hasOwn(patch, "workspaceWorktreeBranch") ||
        Object.hasOwn(patch, "workspaceWorktreeName");

      if (shouldPersistWorkspaceSettings) {
        params.execution_workspace_settings =
          issueExecutionWorkspaceSettingsFromDraft(
            {
              workspaceTargetMode:
                patch.workspaceTargetMode ?? issueDraft.workspaceTargetMode,
              workspaceWorktreePath:
                patch.workspaceWorktreePath ?? issueDraft.workspaceWorktreePath,
              workspaceWorktreeBranch:
                patch.workspaceWorktreeBranch ??
                issueDraft.workspaceWorktreeBranch,
              workspaceWorktreeName:
                patch.workspaceWorktreeName ?? issueDraft.workspaceWorktreeName,
            },
            patch.projectId ?? issueDraft.projectId,
          );
      }

      if (options && Object.hasOwn(options, "hiddenAt")) {
        params.hidden_at = options.hiddenAt;
      }

      setIsSavingIssue(true);
      setIssueEditorError(null);

      try {
        const updatedIssue = (await boardUpdateIssue(params)) as IssueRecord;
        const isHidden = Boolean(updatedIssue.hidden_at);

        applyIssueUpdateToSnapshot(updatedIssue, {
          removeFromSnapshot: isHidden,
        });
        syncIssueDraftFromUpdate(updatedIssue, patch);
        setSelectedIssueId(isHidden ? null : updatedIssue.id);
        setIssuesRouteMode(isHidden ? "list" : "detail");

        if (isHidden) {
          setStatusMessage(
            `${updatedIssue.identifier ?? updatedIssue.title} hidden.`,
          );
        }

        return updatedIssue;
      } catch (error) {
        setIssueEditorError(
          error instanceof Error ? error.message : String(error),
        );
        return null;
      } finally {
        setIsSavingIssue(false);
      }
    });

  const handleHideIssue = async (issue: IssueRecord) =>
    handlePersistIssuePatch(issue, {}, { hiddenAt: new Date().toISOString() });

  const handleQueueMessage = (issue: IssueRecord) => {
    handleOpenCreateIssueDialog({
      dialogMode: "queuedMessage",
      parentId: issue.id,
      projectId: issue.project_id ?? issueDraft.projectId,
      status: "backlog",
      workspaceTargetMode: issueDraft.workspaceTargetMode,
      workspaceWorktreeBranch: issueDraft.workspaceWorktreeBranch,
      workspaceWorktreeName: issueDraft.workspaceWorktreeName,
      workspaceWorktreePath: issueDraft.workspaceWorktreePath,
    });
  };

  const handleAddIssueAttachment = async (issue: IssueRecord) => {
    setStatusMessage(null);

    try {
      const path = await desktopPickFile();
      if (!path) {
        return;
      }

      setIsWorking(true);
      const attachment = await boardAddIssueAttachment({
        company_id: issue.company_id,
        issue_id: issue.id,
        local_file_path: path,
      });
      const attachments = await boardListIssueAttachments(issue.id);
      setIssueAttachmentsByIssueId((current) => ({
        ...current,
        [issue.id]: attachments as IssueAttachmentRecord[],
      }));
      setStatusMessage(
        `${attachment.original_filename ?? fileName(path)} attached to ${issue.identifier ?? issue.title}.`,
      );
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleRevealIssueAttachment = async (
    attachment: IssueAttachmentRecord,
  ) => {
    try {
      await desktopRevealInFinder(attachment.local_path);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleApproveApproval = async (
    approvalId: string,
    decisionNote?: string,
  ) => {
    if (!selectedCompanyId) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      const approval = await boardApproveApproval({
        approval_id: approvalId,
        decision_note: decisionNote,
      });
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setSelectedApprovalId((approval as ApprovalRecord).id);
      setSelectedScreen("approvals");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleOpenDirectory = async (relativePath: string) => {
    if (!selectedSessionId) {
      return;
    }

    try {
      const entries = await repositoryListFiles(
        selectedSessionId,
        relativePath,
      );
      setCurrentDirectory(relativePath);
      setFileEntries(entries as FileEntry[]);
      setSelectedFilePath(null);
      setSelectedFile(null);
      setSelectedDiff(null);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleOpenFile = async (relativePath: string) => {
    if (!selectedSessionId) {
      return;
    }

    try {
      const file = await repositoryReadFile(selectedSessionId, relativePath);
      setSelectedFilePath(relativePath);
      setSelectedFile(file);
      setSelectedDiff(null);
      setWorkspaceCenterTab("preview");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleOpenDiff = async (relativePath: string) => {
    if (!selectedSessionId) {
      return;
    }

    try {
      const diff = await gitDiffFile(relativePath, selectedSessionId);
      setSelectedFilePath(relativePath);
      setSelectedFile(null);
      setSelectedDiff(diff);
      setWorkspaceCenterTab("preview");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const sendSessionMessage = async (content: string) => {
    const trimmedContent = content.trim();
    if (!(selectedSessionId && trimmedContent)) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await agentSend(
        selectedSessionId,
        trimmedContent,
        activeWorkspaceProvider === "custom"
          ? undefined
          : activeWorkspaceProvider,
      );
      sessionStateManager.handleSessionEvent({
        event: {},
        session_id: selectedSessionId,
      });
      await refreshActiveWorkspaceArtifacts(selectedSessionId);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleRunAgent = async (event: FormEvent) => {
    event.preventDefault();
    const nextPrompt = prompt.trim();
    if (!nextPrompt) {
      return;
    }

    await sendSessionMessage(nextPrompt);
    setPrompt("");
  };

  const handleSendConversationPrompt = async (content: string) => {
    const trimmedContent = content.trim();
    if (!trimmedContent) {
      return;
    }

    await sendSessionMessage(trimmedContent);
    setPrompt("");
  };

  const handleRespondToSessionQuestion = async (response: string) => {
    await sendSessionMessage(response);
  };

  const handleRunTerminal = async (event: FormEvent) => {
    event.preventDefault();
    if (!(selectedSessionId && terminalCommand.trim())) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await terminalRun(selectedSessionId, terminalCommand.trim());
      setTerminalCommand("");
      sessionStateManager.handleSessionEvent({
        event: {},
        session_id: selectedSessionId,
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const createCompany = async ({
    name,
    description,
    brandColor,
  }: {
    name: string;
    description?: string;
    brandColor?: string;
  }) => {
    setIsWorking(true);
    try {
      const createdCompany = await boardCreateCompany({
        name,
        description,
        brand_color: brandColor,
        require_board_approval_for_new_agents: false,
      });
      if (!createdCompany.ceo_agent_id?.trim()) {
        try {
          await boardCreateAgent(
            createDefaultExecutorParams(createdCompany.id, dependencyCheck),
          );
        } catch (error) {
          setStatusMessage(
            `Space created, but the default executor could not be prepared: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        }
      }
      const nextCompanies = (await boardListCompanies()) as Company[];
      setCompanies(nextCompanies);
      handleSelectCompany(createdCompany.id);
      return createdCompany;
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
      throw error;
    } finally {
      setIsWorking(false);
    }
  };

  const resetCompanyDialog = () => {
    setCompanyDialogName("");
    setCompanyDialogDescription("");
    setCompanyDialogBrandColor(defaultCompanyBrandColor);
    setCompanyDialogError(null);
    setIsCompanyDialogSaving(false);
  };

  const handleOpenCreateCompanyDialog = () => {
    resetCompanyDialog();
    setIsCreateCompanyDialogOpen(true);
  };

  const handleCloseCreateCompanyDialog = () => {
    if (isCompanyDialogSaving) {
      return;
    }

    setIsCreateCompanyDialogOpen(false);
    resetCompanyDialog();
  };

  const handleCreateCompanyFromDialog = async () => {
    if (!companyDialogName.trim() || isCompanyDialogSaving) {
      return;
    }

    setIsCompanyDialogSaving(true);
    setCompanyDialogError(null);

    try {
      await createCompany({
        name: companyDialogName.trim(),
        description: companyDialogDescription.trim() || undefined,
        brandColor: companyDialogBrandColor.trim() || undefined,
      });
      setIsCreateCompanyDialogOpen(false);
      resetCompanyDialog();
    } catch (error) {
      setCompanyDialogError(
        error instanceof Error ? error.message : String(error),
      );
      setIsCompanyDialogSaving(false);
    }
  };

  const applySettingsPatch = async (patch: Partial<DesktopSettings>) => {
    const nextSettings = mergeDesktopSettings({
      ...settings,
      ...patch,
    });
    setSettings(nextSettings);
    await persistSettings(nextSettings);
  };

  const handleSettingsSubmit = async (event: FormEvent) => {
    event.preventDefault();
    await persistSettings(settings);
    setSelectedScreen(normalizeScreen(settings.preferred_view));
  };

  const persistSettings = async (nextSettings: DesktopSettings) => {
    try {
      const saved = await settingsUpdate(nextSettings);
      const merged = mergeDesktopSettings(saved);
      setSettings(merged);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const persistBirdsEyeCanvasState = async (
    companyId: string,
    canvasState: BirdsEyeCanvasState,
  ) => {
    const nextSettings = mergeDesktopSettings({
      ...settings,
      birds_eye_canvas: {
        ...(settings.birds_eye_canvas ?? {}),
        [companyId]: serializeBirdsEyeCanvasState(canvasState),
      },
    });
    setSettings(nextSettings);
    await persistSettings(nextSettings);
  };

  const loadDependencies = async () => {
    try {
      const result = await systemCheckDependencies();
      setDependencyCheck(result);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const runGitMutation = async (operation: () => Promise<unknown>) => {
    if (!selectedSessionId) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);

    try {
      await operation();
      await refreshActiveWorkspaceArtifacts(selectedSessionId);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleStageFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitStage([file.path], selectedSessionId ?? undefined),
    );
  };

  const handleUnstageFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitUnstage([file.path], selectedSessionId ?? undefined),
    );
  };

  const handleDiscardFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitDiscard([file.path], selectedSessionId ?? undefined),
    );
  };

  const handleGitCommit = async (pushAfterCommit = false) => {
    if (!(selectedSessionId && gitCommitMessage.trim())) {
      return;
    }

    await runGitMutation(async () => {
      await gitCommit({
        session_id: selectedSessionId,
        message: gitCommitMessage.trim(),
      });

      if (pushAfterCommit) {
        await gitPush({
          session_id: selectedSessionId,
          branch: currentBranchName,
        });
      }
    });

    setGitCommitMessage("");
  };

  const handleGitPush = async () => {
    if (!selectedSessionId) {
      return;
    }

    await runGitMutation(() =>
      gitPush({
        session_id: selectedSessionId,
        branch: currentBranchName,
      }),
    );
  };

  if (!bootstrap) {
    return (
      <div className="splash-shell">
        <div className="splash-card">
          <h1>Booting Unbound Desktop</h1>
          <p>
            Checking for a compatible daemon and loading your local worktree.
          </p>
        </div>
      </div>
    );
  }

  if (bootstrap.state !== "ready") {
    return (
      <div className="blocking-shell">
        <div className="blocking-card">
          <span className="blocking-eyebrow">Daemon Required</span>
          <h1>
            {bootstrap.state === "missing_daemon"
              ? "Install unbound-daemon"
              : bootstrap.state === "incompatible_daemon"
                ? "Update unbound-daemon"
                : "Restart unbound-daemon"}
          </h1>
          <p>{bootstrap.message}</p>
          <dl className="blocking-metadata">
            <div>
              <dt>Expected desktop version</dt>
              <dd>{bootstrap.expected_app_version}</dd>
            </div>
            <div>
              <dt>Runtime base dir</dt>
              <dd>{bootstrap.base_dir}</dd>
            </div>
            <div>
              <dt>Socket path</dt>
              <dd>{bootstrap.socket_path}</dd>
            </div>
            {bootstrap.daemon_info ? (
              <div>
                <dt>Detected daemon</dt>
                <dd>{bootstrap.daemon_info.daemon_version}</dd>
              </div>
            ) : null}
          </dl>
          <div className="blocking-actions">
            <button
              className="primary-button"
              onClick={() => void retryBootstrap()}
              type="button"
            >
              Retry
            </button>
            <button
              className="secondary-button"
              onClick={() =>
                void desktopOpenExternal(
                  "https://github.com/unbound-computer/unbound",
                )
              }
              type="button"
            >
              Open install docs
            </button>
          </div>
          <div className="search-paths">
            <h2>Searched daemon paths</h2>
            <ul>
              {bootstrap.searched_paths.map((path) => (
                <li key={path}>{path}</li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    );
  }

  const showBoardSidebar =
    layout === "companyDashboard" && selectedScreen !== "dashboard";

  return (
    <div className="swift-shell">
      <aside className="company-rail">
        <div className="company-rail-brand">
          <span>u</span>
        </div>
        <div className="company-rail-list">
          {companies.map((company) => {
            const companyRailColor = normalizeHexColor(company.brand_color);
            const isSelected = company.id === selectedCompanyId;

            return (
              <button
                aria-label={company.name}
                className={
                  isSelected
                    ? "company-rail-button company-rail-company active"
                    : "company-rail-button company-rail-company"
                }
                key={company.id}
                onClick={() => handleSelectCompany(company.id)}
                onContextMenu={(event) =>
                  handleOpenCompanyContextMenu(event, company)
                }
                style={{
                  backgroundColor: companyRailColor,
                  borderColor: isSelected ? "#FFFFFF" : "transparent",
                  color: companyRailForegroundColor(companyRailColor),
                  opacity: isSelected ? 1 : 0.5,
                }}
                title={company.name}
                type="button"
              >
                {company.name.slice(0, 1).toUpperCase()}
              </button>
            );
          })}
          <button
            aria-label="Create space"
            className="company-rail-button add"
            onClick={handleOpenCreateCompanyDialog}
            title="Create space"
            type="button"
          >
            <span>+</span>
          </button>
        </div>
        <button
          className={
            selectedScreen === "appSettings"
              ? "company-rail-button settings active"
              : "company-rail-button settings"
          }
          onClick={() => handleSelectScreen("appSettings")}
          type="button"
        >
          ⚙
        </button>
      </aside>

      {companyContextMenu ? (
        <div
          aria-label={`${companyContextMenu.companyName} menu`}
          className="company-context-menu"
          onContextMenu={(event) => event.preventDefault()}
          onPointerDown={(event) => event.stopPropagation()}
          role="menu"
          style={{ left: companyContextMenu.x, top: companyContextMenu.y }}
        >
          <div className="company-context-menu-header">
            <div aria-hidden="true" className="company-context-menu-monogram">
              {companyContextMenu.companyName.slice(0, 1).toUpperCase()}
            </div>
            <div className="company-context-menu-copy">
              <strong>{companyContextMenu.companyName}</strong>
              <span>Shortcuts and conversation views</span>
            </div>
          </div>
          <div className="company-context-menu-actions">
            {companyContextMenuItems.map((item) => {
              const isActive =
                companyContextMenu.companyId === selectedCompanyId &&
                selectedScreen === item.screen;

              return (
                <button
                  className={
                    isActive
                      ? "company-context-menu-item active"
                      : "company-context-menu-item"
                  }
                  key={item.screen}
                  onClick={() =>
                    handleSelectCompanyScreen(
                      companyContextMenu.companyId,
                      item.screen,
                    )
                  }
                  role="menuitem"
                  type="button"
                >
                  <CompanyContextMenuIcon icon={item.icon} />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </div>
        </div>
      ) : null}

      {layout === "companyDashboard" ? (
        <div
          className={
            showBoardSidebar
              ? "company-dashboard-shell"
              : "company-dashboard-shell company-dashboard-shell-canvas"
          }
        >
          {showBoardSidebar ? (
            <aside className="board-sidebar">
              <div className="board-sidebar-header">
                <div>
                  <strong>{selectedCompany?.name ?? "Space"}</strong>
                  <span>Local model workspace</span>
                </div>
                <button
                  className="icon-button"
                  onClick={() => void refreshBoardData()}
                  type="button"
                >
                  ↻
                </button>
              </div>

              <div className="board-sidebar-scroll">
                <div className="board-sidebar-section">
                  <SidebarLinkButton
                    label="New Conversation"
                    onClick={handleOpenCreateIssueDialog}
                  />
                  <BoardSidebarButton
                    active={false}
                    icon="dashboard"
                    label="Dashboard"
                    onClick={() => handleSelectScreen("dashboard")}
                    trailing={
                      totalLiveAgentRuns > 0
                        ? formatLiveRunCountLabel(totalLiveAgentRuns)
                        : null
                    }
                  />
                </div>

                {primaryBoardSections.map((section) => (
                  <div className="board-sidebar-section" key={section.title}>
                    <span className="sidebar-section-title">
                      {section.title}
                    </span>
                    {section.screens.map((screen) => (
                      <BoardSidebarButton
                        active={selectedScreen === screen}
                        icon={sidebarScreenIcon(screen)}
                        key={screen}
                        label={screenLabel(screen)}
                        onClick={() => handleSelectScreen(screen)}
                      />
                    ))}
                  </div>
                ))}

                <div className="board-sidebar-section">
                  <div className="sidebar-section-row">
                    <span className="sidebar-section-title">Projects</span>
                  </div>
                  <SidebarLinkButton
                    label="New Project"
                    onClick={() => void handleAddRepository()}
                  />
                  {orderedSidebarProjects.length ? (
                    orderedSidebarProjects.map((project) => (
                      <button
                        className={
                          selectedScreen === "projects" &&
                          selectedProjectId === project.id
                            ? "agent-sidebar-button active"
                            : "agent-sidebar-button"
                        }
                        key={project.id}
                        onClick={() => handleSelectProjectSidebar(project.id)}
                        type="button"
                      >
                        {project.name || project.title || project.id}
                      </button>
                    ))
                  ) : (
                    <div className="agent-sidebar-empty">No projects yet</div>
                  )}
                </div>

                <div className="board-sidebar-section">
                  <span className="sidebar-section-title">
                    {companyBoardSection.title}
                  </span>
                  {companyBoardSection.screens.map((screen) => (
                    <BoardSidebarButton
                      active={selectedScreen === screen}
                      icon={sidebarScreenIcon(screen)}
                      key={screen}
                      label={screenLabel(screen)}
                      onClick={() => handleSelectScreen(screen)}
                    />
                  ))}
                </div>
              </div>
            </aside>
          ) : null}

          <main
            className={
              showBoardSidebar
                ? "board-content"
                : "board-content board-content-dashboard"
            }
          >
            {statusMessage ? (
              <div className="status-banner">{statusMessage}</div>
            ) : null}

            {selectedScreen === "dashboard" ? (
              <GridDashboardBirdsEyeRouteView
                agents={dashboardOverviewAgents}
                chats={dashboardOverviewChats}
                dependencyCheck={dependencyCheck}
                isLoadingOverview={isDashboardOverviewLoading}
                onCreateProject={() => void handleAddRepository()}
                onCreateQuickChat={(title, defaults) =>
                  handleCreateBirdsEyeChat(title, defaults)
                }
                onOpenIssueDetail={(issueId) =>
                  void handleOpenDashboardIssueTile(issueId)
                }
                projects={dashboardOverviewProjects}
                renderIssueTile={renderDashboardIssueTile}
                selectedIssueTileId={selectedIssue?.id ?? null}
                workspaces={dashboardOverviewWorkspaces}
              />
            ) : null}

            {selectedScreen === "stats" ? (
              <StatsRouteView
                bootstrap={bootstrap}
                company={selectedCompany}
                dependencyCheck={dependencyCheck}
                issueRunCardUpdatesByIssueId={issueRunCardUpdatesByIssueId}
                onCheckDependencies={() => void loadDependencies()}
                onOpenWorkspace={handleSelectBoardWorkspace}
                repositoriesCount={repositories.length}
                snapshot={companySnapshot}
              />
            ) : null}

            {selectedScreen === "agents" ? (
              <RoutePlaceholder
                body="Conversations now run models directly. Configure Claude or Codex on each conversation instead of managing agent pages."
                title="Models"
              />
            ) : null}

            {selectedScreen === "issues" ? (
              issuesRouteMode === "detail" && selectedIssue ? (
                <IssueWorkspaceDetailView
                  agents={companySnapshot?.agents ?? []}
                  availableStatusOptions={issueStatusOptions}
                  dependencyCheck={dependencyCheck}
                  isSavingIssue={isSavingIssue}
                  issue={selectedIssue}
                  issueDraft={issueDraft}
                  issueEditorError={issueEditorError}
                  issueWorkspaceSidebar={
                    <WorkspaceInspectorSidebar
                      currentBranch={currentBranch}
                      currentBranchName={currentBranchName}
                      currentDirectory={currentDirectory}
                      fileEntries={fileEntries}
                      gitCommitMessage={gitCommitMessage}
                      gitHistory={gitHistory}
                      gitState={gitState}
                      hasUncommittedChanges={hasUncommittedChanges}
                      hasUnpushedCommits={hasUnpushedCommits}
                      issueMeta={
                        <IssueWorkspaceInspectorMeta
                          agents={companySnapshot?.agents ?? []}
                          availableStatusOptions={issueStatusOptions}
                          isSavingIssue={isSavingIssue}
                          issue={selectedIssue}
                          issueDraft={issueDraft}
                          issueEditorError={issueEditorError}
                          onCommitIssuePatch={(patch) =>
                            void handlePersistIssuePatch(selectedIssue, patch)
                          }
                          onIssueDraftChange={(patch) =>
                            setIssueDraft((current) => ({
                              ...current,
                              ...patch,
                            }))
                          }
                          projects={companySnapshot?.projects ?? []}
                          selectableParentIssues={selectableParentIssues}
                          statusLabel={issueStatusLabel}
                          workspaceTargetErrorMessage={
                            issueDetailWorktreeState.errorMessage
                          }
                          workspaceTargetLoading={
                            issueDetailWorktreeState.isLoading
                          }
                          workspaceTargetWorktrees={
                            issueDetailWorktreeState.worktrees
                          }
                        />
                      }
                      isWorking={isWorking}
                      onDiscardFile={(file) => void handleDiscardFile(file)}
                      onGitCommit={(push) => void handleGitCommit(push)}
                      onGitCommitMessageChange={setGitCommitMessage}
                      onGitPush={() => void handleGitPush()}
                      onOpenDiff={(path) => void handleOpenDiff(path)}
                      onOpenDirectory={(path) => void handleOpenDirectory(path)}
                      onOpenFile={(path) => void handleOpenFile(path)}
                      onSelectSidebarTab={setWorkspaceSidebarTab}
                      onStageFile={(file) => void handleStageFile(file)}
                      onUnstageFile={(file) => void handleUnstageFile(file)}
                      selectedDiff={selectedDiff}
                      selectedFilePath={selectedFilePath}
                      workspace={selectedIssueWorkspace}
                      workspaceSidebarTab={workspaceSidebarTab}
                    />
                  }
                  isWorking={isWorking}
                  latestCompletionSummary={
                    selectedIssueWorkspace?.session_id
                      ? selectedIssueWorkspaceLiveState.latestCompletionSummary
                      : null
                  }
                  onAddAttachment={() =>
                    void handleAddIssueAttachment(selectedIssue)
                  }
                  onBack={() => handleShowIssuesList()}
                  onCommitIssuePatch={(patch) =>
                    void handlePersistIssuePatch(selectedIssue, patch)
                  }
                  onIssueDraftChange={(patch) =>
                    setIssueDraft((current) => ({
                      ...current,
                      ...patch,
                    }))
                  }
                  onPromptChange={setPrompt}
                  onRespondToQuestion={(response) =>
                    void handleRespondToSessionQuestion(response)
                  }
                  onRevealRepo={() => {
                    if (selectedIssueWorkspace?.workspace_repo_path) {
                      void desktopRevealInFinder(
                        selectedIssueWorkspace.workspace_repo_path,
                      );
                    }
                  }}
                  onRunTerminal={handleRunTerminal}
                  onSelectWorkspaceCenterTab={setWorkspaceCenterTab}
                  onSendPrompt={(content) =>
                    void handleSendConversationPrompt(content)
                  }
                  onStopSession={() => {
                    if (selectedIssueWorkspace?.session_id) {
                      void agentStop(selectedIssueWorkspace.session_id);
                    }
                  }}
                  onStopTerminal={() => {
                    if (selectedIssueWorkspace?.session_id) {
                      void terminalStop(selectedIssueWorkspace.session_id);
                    }
                  }}
                  onTerminalCommandChange={setTerminalCommand}
                  previewTabLabel={previewTabLabel}
                  projectLabel={(projectId) =>
                    issueProjectLabel(
                      companySnapshot?.projects ?? [],
                      projectId,
                    )
                  }
                  projects={companySnapshot?.projects ?? []}
                  prompt={prompt}
                  runtimeStatusValue={
                    selectedIssueWorkspace?.session_id
                      ? stringifyStatus(
                          selectedIssueWorkspaceLiveState.runtimeStatus,
                        )
                      : "idle"
                  }
                  selectableParentIssues={selectableParentIssues}
                  selectedDiff={selectedDiff}
                  selectedFile={selectedFile}
                  selectedFilePath={selectedFilePath}
                  session={selectedIssueWorkspaceSession}
                  sessionErrorMessage={
                    selectedIssueWorkspace?.session_id
                      ? selectedIssueWorkspaceLiveState.errorMessage
                      : null
                  }
                  sessionLoading={
                    selectedIssueWorkspace?.session_id
                      ? selectedIssueWorkspaceLiveState.isLoadingMessages
                      : false
                  }
                  sessionRows={
                    selectedIssueWorkspace?.session_id
                      ? selectedIssueWorkspaceLiveState.conversationRows
                      : []
                  }
                  statusLabel={issueStatusLabel}
                  terminalCommand={terminalCommand}
                  terminalContainerRef={terminalContainerRef}
                  terminalStatusValue={stringifyStatus(
                    activeTerminalStatusState,
                  )}
                  workspace={selectedIssueWorkspace}
                  workspaceCenterTab={workspaceCenterTab}
                  workspaceTargetErrorMessage={
                    issueDetailWorktreeState.errorMessage
                  }
                  workspaceTargetLoading={issueDetailWorktreeState.isLoading}
                  workspaceTargetWorktrees={issueDetailWorktreeState.worktrees}
                />
              ) : (
                <IssuesListView
                  activeTab={selectedIssuesListTab}
                  emptyTitle={`No conversations in ${issuesListTabTitle(selectedIssuesListTab).toLowerCase()}`}
                  issues={visibleIssues}
                  onSelectIssue={(issueId) => void handleSelectIssue(issueId)}
                  onTabChange={setSelectedIssuesListTab}
                  selectedIssueId={selectedIssueId}
                  summaryText={issueSummaryText}
                />
              )
            ) : null}

            {selectedScreen === "approvals" ? (
              <RoutePlaceholder
                body="Board approvals are no longer part of the core project and conversation workflow."
                title="Approvals Removed"
              />
            ) : null}

            {selectedScreen === "projects" ? (
              <ProjectsRouteView
                currentProject={selectedProject}
                currentProjectIssueCount={
                  selectedProject
                    ? boardIssues.filter(
                        (issue) =>
                          issue.project_id === selectedProject.id &&
                          isRootConversationIssue(issue),
                      ).length
                    : 0
                }
                currentProjectWorkspaceCount={
                  selectedProject
                    ? companyWorkspaces.filter(
                        (workspace) =>
                          workspace.project_id === selectedProject.id,
                      ).length
                    : 0
                }
                goals={boardGoals}
                onDeleteProject={handleDeleteProject}
                onOpenCreateProject={() => void handleAddRepository()}
                onUpdateProjectDefaultNewChatArea={
                  handleUpdateProjectDefaultNewChatArea
                }
              />
            ) : null}

            {selectedScreen === "companySettings" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <DashboardBreadcrumbs items={[{ label: "Space settings" }]} />
                  <span className="route-kicker">Space settings</span>
                  <h1>{selectedCompany?.name ?? "Space settings"}</h1>
                  <p>
                    Space identity and runtime defaults live here. Device and
                    app settings stay behind the rail gear.
                  </p>
                </div>

                <div className="surface-grid single">
                  <section className="surface-panel wide">
                    <h3>Space profile</h3>
                    <p>
                      This route follows the board/space admin surface rather
                      than the desktop preferences shell.
                    </p>
                    <div className="surface-list">
                      <DetailRow
                        label="Space Name"
                        value={selectedCompany?.name ?? "n/a"}
                      />
                      <DetailRow
                        label="Description"
                        value={selectedCompany?.description ?? "No description"}
                      />
                      <CompanyBrandColorField
                        errorMessage={companyBrandColorError}
                        isSaving={isSavingCompanyBrandColor}
                        label="Brand Color"
                        onChange={(nextColor) =>
                          void handleCompanyBrandColorChange(nextColor)
                        }
                        value={companyBrandColorDraft}
                      />
                      <DetailRow
                        label="Conversation Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                    </div>
                  </section>

                  <section className="surface-panel wide">
                    <h3>Runtime summary</h3>
                    <div className="summary-grid">
                      <SummaryPill
                        label="Conversation Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                      <SummaryPill
                        label="Monthly Budget"
                        value={formatCents(
                          selectedCompany?.budget_monthly_cents,
                        )}
                      />
                      <SummaryPill
                        label="Monthly Spend"
                        value={formatCents(
                          selectedCompany?.spent_monthly_cents,
                        )}
                      />
                    </div>

                    <div className="surface-list">
                      <DetailRow
                        label="Status"
                        value={String(selectedCompany?.status ?? "active")}
                      />
                      <DetailRow
                        label="Default Executor"
                        value={
                          selectedCompanyCeo?.name ??
                          selectedCompany?.ceo_agent_id ??
                          "Missing"
                        }
                      />
                      <DetailRow
                        label="Conversation Counter"
                        value={String(selectedCompany?.issue_counter ?? 0)}
                      />
                      <DetailRow
                        label="Created"
                        value={formatTimestamp(selectedCompany?.created_at)}
                      />
                      <DetailRow
                        label="Updated"
                        value={formatTimestamp(selectedCompany?.updated_at)}
                      />
                    </div>
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "activity" ? (
              <ActivityRouteView
                agents={boardAgents}
                issueCommentsByIssueId={issueCommentsByIssueId}
                issueRunCardUpdatesByIssueId={issueRunCardUpdatesByIssueId}
                issues={activityVisibleIssues}
                onOpenIssue={(issueId) => void handleSelectIssue(issueId)}
              />
            ) : null}

            {selectedScreen === "costs" ? (
              <CostsRouteView
                agents={companySnapshot?.agents ?? []}
                company={selectedCompany}
              />
            ) : null}
          </main>
        </div>
      ) : null}

      {layout === "settings" ? (
        <div className="settings-shell">
          <aside className="settings-sidebar">
            <div className="settings-traffic-spacer" />
            <button
              className="settings-back-button"
              onClick={() => handleSelectScreen("dashboard")}
              type="button"
            >
              <span className="settings-back-chevron">‹</span>
              <span>Back</span>
            </button>
            <div className="settings-nav">
              <SettingsSidebarItem
                icon="house"
                isSelected={false}
                label="Home"
                onClick={() => handleSelectScreen("dashboard")}
              />
              {settingsSections.map((section) => (
                <SettingsSidebarItem
                  icon={settingsSectionIcon(section.id)}
                  isSelected={selectedSettingsSection === section.id}
                  key={section.id}
                  label={section.label}
                  onClick={() => setSelectedSettingsSection(section.id)}
                />
              ))}
            </div>
          </aside>

          <main className="settings-content">
            {statusMessage ? (
              <div className="status-banner">{statusMessage}</div>
            ) : null}

            {selectedSettingsSection === "appearance" ? (
              <SettingsPageShell
                subtitle="Customize how the app looks on your device."
                title="Appearance"
              >
                <SettingsSectionBlock
                  description="Select your preferred color scheme"
                  title="Theme"
                >
                  <div className="theme-card-row">
                    {themeModes.map((mode) => (
                      <ThemeModeCard
                        isAvailable={mode === "dark"}
                        isSelected={(settings.theme_mode ?? "dark") === mode}
                        key={mode}
                        mode={mode}
                        onSelect={() =>
                          void applySettingsPatch({ theme_mode: mode })
                        }
                      />
                    ))}
                  </div>
                </SettingsSectionBlock>
              </SettingsPageShell>
            ) : null}

            {selectedSettingsSection === "general" ? (
              <SettingsPageShell
                subtitle="Configure general app preferences."
                title="General"
              >
                <SettingsSectionBlock
                  description="Adjust the interface text size"
                  title="Text Size"
                >
                  <div className="settings-card-row">
                    {fontSizePresets.map((preset) => (
                      <FontSizePresetCard
                        isSelected={
                          (settings.font_size_preset ?? "medium") === preset
                        }
                        key={preset}
                        onSelect={() =>
                          void applySettingsPatch({ font_size_preset: preset })
                        }
                        preset={preset}
                      />
                    ))}
                  </div>
                </SettingsSectionBlock>

                <SettingsSectionBlock
                  description="Local desktop preferences that are not part of the native macOS settings surface."
                  title="Desktop"
                >
                  <section className="settings-desktop-panel">
                    <form
                      className="settings-shadcn-form"
                      onSubmit={handleSettingsSubmit}
                    >
                      <div className="settings-shadcn-stack">
                        <SettingsToggleField
                          checked={settings.show_raw_message_json}
                          description="Expose the raw payload beneath structured session messages."
                          label="Show structured message JSON"
                          onChange={(checked) =>
                            setSettings((current) => ({
                              ...current,
                              show_raw_message_json: checked,
                            }))
                          }
                        />
                        <SettingsSelectField
                          ariaLabel="Default opening view"
                          description="Choose the first screen shown when Unbound Desktop launches."
                          label="Default opening view"
                          onChange={(value) =>
                            setSettings((current) => ({
                              ...current,
                              preferred_view: value,
                            }))
                          }
                          options={desktopPreferredViewOptions}
                          value={preferredViewSelectValue(
                            settings.preferred_view,
                          )}
                        />
                        <section className="settings-inline-panel">
                          <p>
                            <strong>Current space</strong>:{" "}
                            {currentSpaceScope?.space?.name ?? "Personal Space"}
                          </p>
                          <p>
                            <strong>Machine</strong>:{" "}
                            {currentSpaceScope?.machine?.name ?? "This Device"}
                          </p>
                          <p>
                            Managed automatically by the daemon for this device.
                          </p>
                        </section>
                      </div>
                      <div className="settings-shadcn-actions">
                        <button
                          className="settings-shadcn-button"
                          type="submit"
                        >
                          Save device settings
                        </button>
                      </div>
                    </form>
                  </section>
                </SettingsSectionBlock>
              </SettingsPageShell>
            ) : null}
            {selectedSettingsSection === "notifications" ? (
              <SettingsPageShell
                subtitle="This feature is coming soon."
                title="Notifications"
              >
                <section className="settings-inline-panel">
                  <p>Settings for notifications will appear here.</p>
                </section>
              </SettingsPageShell>
            ) : null}
            {selectedSettingsSection === "privacy" ? (
              <SettingsPageShell
                subtitle="Your data is protected with end-to-end encryption."
                title="Privacy"
              >
                <SettingsSectionBlock
                  description="Runtime information and local storage boundaries."
                  title="Daemon Runtime"
                >
                  <section className="settings-inline-panel">
                    <dl className="blocking-metadata">
                      <div>
                        <dt>App version</dt>
                        <dd>{bootstrap.expected_app_version}</dd>
                      </div>
                      <div>
                        <dt>Daemon version</dt>
                        <dd>{bootstrap.daemon_info?.daemon_version}</dd>
                      </div>
                      <div>
                        <dt>Socket</dt>
                        <dd>{bootstrap.socket_path}</dd>
                      </div>
                      <div>
                        <dt>Base dir</dt>
                        <dd>{bootstrap.base_dir}</dd>
                      </div>
                    </dl>
                  </section>
                </SettingsSectionBlock>
              </SettingsPageShell>
            ) : null}
          </main>
        </div>
      ) : null}

      {isCreateCompanyDialogOpen ? (
        <CreateCompanyDialogView
          brandColor={companyDialogBrandColor}
          description={companyDialogDescription}
          errorMessage={companyDialogError}
          isSaving={isCompanyDialogSaving}
          name={companyDialogName}
          onBrandColorChange={setCompanyDialogBrandColor}
          onClose={handleCloseCreateCompanyDialog}
          onCreate={() => void handleCreateCompanyFromDialog()}
          onDescriptionChange={setCompanyDialogDescription}
          onNameChange={setCompanyDialogName}
        />
      ) : null}

      {isCreateIssueDialogOpen ? (
        <CreateIssueDialogView
          attachments={issueDialogAttachments}
          command={issueDialogCommand}
          companyPrefix={selectedCompany?.issue_prefix ?? "ISS"}
          dependencyCheck={dependencyCheck}
          description={issueDialogDescription}
          enableChrome={issueDialogEnableChrome}
          errorMessage={issueDialogError}
          isSaving={isIssueDialogSaving}
          mode={issueDialogMode}
          model={issueDialogModel}
          onAddAttachment={() => void handleAddIssueDialogAttachment()}
          onClose={handleCloseCreateIssueDialog}
          onCommandChange={setIssueDialogCommand}
          onCreate={() => void handleCreateIssueFromDialog()}
          onDescriptionChange={setIssueDialogDescription}
          onEnableChromeChange={setIssueDialogEnableChrome}
          onModelChange={setIssueDialogModel}
          onPlanModeChange={setIssueDialogPlanMode}
          onProjectChange={handleIssueDialogProjectChange}
          onRemoveAttachment={handleRemoveIssueDialogAttachment}
          onSkipPermissionsChange={setIssueDialogSkipPermissions}
          onThinkingEffortChange={setIssueDialogThinkingEffort}
          onTitleChange={setIssueDialogTitle}
          onWorkspaceTargetChange={handleIssueDialogWorkspaceTargetChange}
          parentConversationTitle={
            issueDialogParentIssueId
              ? issueParentLabel(boardIssues, issueDialogParentIssueId)
              : null
          }
          planMode={issueDialogPlanMode}
          projects={boardProjects}
          selectedProjectId={issueDialogProjectId}
          selectedWorkspaceTargetValue={issueWorkspaceTargetSelectValue(
            issueDialogWorkspaceTargetMode,
            issueDialogWorkspaceWorktreePath,
          )}
          skipPermissions={issueDialogSkipPermissions}
          thinkingEffort={issueDialogThinkingEffort}
          title={issueDialogTitle}
          workspaceTargetErrorMessage={issueDialogWorktreeState.errorMessage}
          workspaceTargetLoading={issueDialogWorktreeState.isLoading}
          workspaceTargetWorktrees={issueDialogWorktreeState.worktrees}
        />
      ) : null}
    </div>
  );
}

interface OrgHierarchyNode {
  agent: AgentRecord;
  leadProjects: ProjectRecord[];
  reports: OrgHierarchyNode[];
  totalReports: number;
}

function OrgRouteView({
  agents,
  company,
  projects,
  selectedAgentId,
  onSelectAgent,
}: {
  agents: AgentRecord[];
  company: Company | null;
  projects: ProjectRecord[];
  selectedAgentId: string | null;
  onSelectAgent: (agentId: string) => void;
}) {
  const ceoAgentId = company?.ceo_agent_id ?? null;
  const agentMap = useMemo(
    () => new Map(agents.map((agent) => [agent.id, agent])),
    [agents],
  );
  const hierarchy = useMemo(
    () => buildOrgHierarchy(agents, projects, ceoAgentId),
    [agents, projects, ceoAgentId],
  );
  const flattenedHierarchy = useMemo(
    () => flattenOrgHierarchy(hierarchy),
    [hierarchy],
  );
  const managersCount = flattenedHierarchy.filter(
    (node) => node.reports.length > 0,
  ).length;
  const ceo = useMemo(
    () => findCompanyCeo(agents, ceoAgentId),
    [agents, ceoAgentId],
  );

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: "Org" }]} />
        <span className="route-kicker">Agent org</span>
        <h1>{company?.name ? `${company.name} agent org` : "Agent org"}</h1>
        <p>
          See the reporting hierarchy for agents across the space and jump into
          any agent to inspect its configuration and runs.
        </p>
      </div>

      <div className="summary-grid">
        <SummaryPill label="CEO" value={ceo?.name ?? "Unassigned"} />
        <SummaryPill label="Agents" value={String(agents.length)} />
        <SummaryPill label="Managers" value={String(managersCount)} />
      </div>

      <div className="surface-grid single">
        <section className="surface-panel">
          <div className="surface-header">
            <div>
              <h3>Agent hierarchy</h3>
              <p>
                This chart shows how agents report across the space. Select any
                node to jump into that agent&apos;s configuration and runs.
              </p>
            </div>
          </div>

          {hierarchy.length ? (
            <div className="org-chart-scroll">
              <ul className="org-chart-list org-chart-list-root">
                {hierarchy.map((node) => (
                  <OrgChartTreeItem
                    agentMap={agentMap}
                    ceoAgentId={ceoAgentId}
                    key={node.agent.id}
                    node={node}
                    onSelectAgent={onSelectAgent}
                    selectedAgentId={selectedAgentId}
                  />
                ))}
              </ul>
            </div>
          ) : (
            <p className="surface-empty-copy">
              No agents yet. Create agents to build the org chart.
            </p>
          )}
        </section>
      </div>
    </section>
  );
}

function OrgChartTreeItem({
  agentMap,
  ceoAgentId,
  node,
  onSelectAgent,
  selectedAgentId,
}: {
  agentMap: Map<string, AgentRecord>;
  ceoAgentId: string | null;
  node: OrgHierarchyNode;
  onSelectAgent: (agentId: string) => void;
  selectedAgentId: string | null;
}) {
  const isRoot = isOrgRootAgent(node.agent, agentMap, ceoAgentId);
  const roleLabel = orgChartAgentRoleLabel(node.agent);
  const providerLabel = orgChartAgentProviderLabel(node.agent);

  return (
    <li className="org-chart-item">
      <button
        className={
          selectedAgentId === node.agent.id
            ? "org-chart-card active"
            : "org-chart-card"
        }
        onClick={() => onSelectAgent(node.agent.id)}
        type="button"
      >
        <span
          className={isRoot ? "org-chart-avatar accent" : "org-chart-avatar"}
        >
          <OrgChartAgentIcon agent={node.agent} isRoot={isRoot} />
        </span>
        <span className="org-chart-card-copy">
          <strong>{orgChartAgentName(node.agent)}</strong>
          <span>{roleLabel}</span>
          <span className="org-chart-provider">
            <span
              className={`org-status-dot ${normalizeAgentStatusTone(
                node.agent.status,
              )}`}
            />
            <small>{providerLabel}</small>
          </span>
        </span>
      </button>

      {node.reports.length ? (
        <ul className="org-chart-list">
          {node.reports.map((childNode) => (
            <OrgChartTreeItem
              agentMap={agentMap}
              ceoAgentId={ceoAgentId}
              key={childNode.agent.id}
              node={childNode}
              onSelectAgent={onSelectAgent}
              selectedAgentId={selectedAgentId}
            />
          ))}
        </ul>
      ) : null}
    </li>
  );
}

function OrgChartAgentIcon({
  agent,
  isRoot,
}: {
  agent: AgentRecord;
  isRoot: boolean;
}) {
  const iconKind = orgChartAgentIconKind(agent, isRoot);

  switch (iconKind) {
    case "finance":
      return (
        <svg
          aria-hidden="true"
          className="org-chart-icon"
          fill="none"
          viewBox="0 0 20 20"
        >
          <ellipse
            cx="10"
            cy="5"
            rx="5.5"
            ry="2.5"
            stroke="currentColor"
            strokeWidth="1.5"
          />
          <path
            d="M4.5 5v4.5C4.5 10.88 6.96 12 10 12s5.5-1.12 5.5-2.5V5"
            stroke="currentColor"
            strokeWidth="1.5"
          />
          <path
            d="M4.5 9.5V14c0 1.38 2.46 2.5 5.5 2.5s5.5-1.12 5.5-2.5V9.5"
            stroke="currentColor"
            strokeWidth="1.5"
          />
        </svg>
      );
    case "communication":
      return (
        <svg
          aria-hidden="true"
          className="org-chart-icon"
          fill="none"
          viewBox="0 0 20 20"
        >
          <path
            d="M5.75 5.25h8.5a2 2 0 0 1 2 2v5.25a2 2 0 0 1-2 2H9l-3.75 2v-2H5.75a2 2 0 0 1-2-2V7.25a2 2 0 0 1 2-2Z"
            stroke="currentColor"
            strokeLinejoin="round"
            strokeWidth="1.5"
          />
        </svg>
      );
    case "engineering":
      return (
        <svg
          aria-hidden="true"
          className="org-chart-icon"
          fill="none"
          viewBox="0 0 20 20"
        >
          <path
            d="m7.5 6.25-3.25 3.5 3.25 4"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.7"
          />
          <path
            d="m12.5 6.25 3.25 3.5-3.25 4"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.7"
          />
        </svg>
      );
    case "leadership":
      return (
        <svg
          aria-hidden="true"
          className="org-chart-icon"
          fill="none"
          viewBox="0 0 20 20"
        >
          <path
            d="M6 6.5V5.75A1.75 1.75 0 0 1 7.75 4h4.5A1.75 1.75 0 0 1 14 5.75v.75"
            stroke="currentColor"
            strokeWidth="1.5"
          />
          <rect
            height="8.5"
            rx="2"
            stroke="currentColor"
            strokeWidth="1.5"
            width="12"
            x="4"
            y="6.5"
          />
          <path
            d="M4.5 9.25h11"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.5"
          />
          <path
            d="M9 9.25v1.5h2v-1.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.5"
          />
        </svg>
      );
    default:
      return (
        <svg
          aria-hidden="true"
          className="org-chart-icon"
          fill="none"
          viewBox="0 0 20 20"
        >
          <rect
            height="9"
            rx="2.2"
            stroke="currentColor"
            strokeWidth="1.5"
            width="11"
            x="4.5"
            y="5"
          />
          <path
            d="M7.25 14.75h5.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.5"
          />
          <path
            d="M8 3.75h4"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.5"
          />
          <circle cx="10" cy="9.5" fill="currentColor" r="1" />
        </svg>
      );
  }
}

function AgentsRouteView({
  agentRunError,
  agentRunEvents,
  agentRunLogContent,
  agentRuns,
  companyName,
  configurationDraft,
  configurationError,
  dependencyCheck,
  isLoadingAgentRunDetail,
  isLoadingAgentRuns,
  isPerformingAgentRunAction,
  isSavingConfiguration,
  mode,
  onAddEnvVar,
  onCancelSelectedRun,
  onChooseInstructionsFile,
  onChooseWorkingDirectory,
  onConfigurationDraftChange,
  onConfigurationEnvVarChange,
  onRemoveEnvVar,
  onRefreshRuns,
  onResumeSelectedRun,
  onRetrySelectedRun,
  onSaveConfiguration,
  onSelectRun,
  onSelectTab,
  selectedAgent,
  selectedRun,
}: {
  agentRunError: string | null;
  agentRunEvents: AgentRunEventRecord[];
  agentRunLogContent: string;
  agentRuns: AgentRunRecord[];
  companyName: string;
  configurationDraft: AgentConfigDraft;
  configurationError: string | null;
  dependencyCheck: RuntimeCapabilities | null;
  isLoadingAgentRunDetail: boolean;
  isLoadingAgentRuns: boolean;
  isPerformingAgentRunAction: boolean;
  isSavingConfiguration: boolean;
  mode: AgentsRouteMode;
  onAddEnvVar: () => void;
  onCancelSelectedRun: () => void;
  onChooseInstructionsFile: () => void;
  onChooseWorkingDirectory: () => void;
  onConfigurationDraftChange: (patch: Partial<AgentConfigDraft>) => void;
  onConfigurationEnvVarChange: (
    envId: string,
    patch: Partial<AgentConfigEnvVarDraft>,
  ) => void;
  onRemoveEnvVar: (envId: string) => void;
  onRefreshRuns: () => void;
  onResumeSelectedRun: () => void;
  onRetrySelectedRun: () => void;
  onSaveConfiguration: () => void;
  onSelectRun: (runId: string) => void;
  onSelectTab: (tab: AgentsRouteMode) => void;
  selectedAgent: AgentRecord | null;
  selectedRun: AgentRunRecord | null;
}) {
  const agentHeaderSubtitle =
    selectedAgent?.title ??
    selectedAgent?.role ??
    selectedAgent?.name ??
    "Agent";
  const agentHeaderStatusLabel = humanizeIssueValue(
    selectedAgent?.status ?? "idle",
  ).toLowerCase();

  return (
    <section className="route-scroll agent-detail-route">
      <div className="agent-detail-layout">
        <DashboardBreadcrumbs
          items={
            selectedAgent
              ? [{ label: "Agents" }, { label: selectedAgent.name || "Agent" }]
              : [{ label: "Agents" }]
          }
        />

        {selectedAgent ? (
          <div className="agent-detail-content">
            <div className="agent-page-header">
              <div className="agent-page-header-main">
                <div className="agent-page-header-identity">
                  <div aria-hidden="true" className="agent-page-header-icon">
                    <AgentHeaderBotIcon />
                  </div>

                  <div className="agent-page-header-copy">
                    <h2>{selectedAgent.name}</h2>
                    <p>{agentHeaderSubtitle}</p>
                    <p>
                      Review the selected agent, adjust its configuration, and
                      inspect its run history from one shared worktree.
                    </p>
                  </div>
                </div>

                <div className="agent-page-header-actions">
                  <AgentHeaderActionChip
                    icon={<AgentHeaderPlusIcon />}
                    label="Assign Task"
                  />
                  <AgentHeaderActionChip
                    icon={<AgentHeaderPauseIcon />}
                    label="Pause"
                  />
                  <span
                    className={`agent-run-status-badge agent-page-header-status ${normalizeAgentStatusTone(
                      selectedAgent.status,
                    )}`}
                  >
                    {agentHeaderStatusLabel}
                  </span>
                  <span
                    aria-hidden="true"
                    className="agent-page-header-icon-chip"
                  >
                    <EllipsisHorizontalIcon />
                  </span>
                </div>
              </div>
            </div>

            <div
              aria-label="Agent views"
              className="agents-tab-strip"
              role="tablist"
            >
              {(
                [
                  ["dashboard", "Dashboard"],
                  ["configuration", "Configuration"],
                  ["runs", "Runs"],
                ] as const
              ).map(([tabId, label]) => (
                <button
                  aria-selected={mode === tabId}
                  className={
                    mode === tabId
                      ? "agents-tab-button active"
                      : "agents-tab-button"
                  }
                  key={tabId}
                  onClick={() => onSelectTab(tabId)}
                  role="tab"
                  type="button"
                >
                  {label}
                </button>
              ))}
            </div>

            {mode === "dashboard" ? (
              <AgentDashboardTab
                agent={selectedAgent}
                companyName={companyName}
              />
            ) : null}

            {mode === "configuration" ? (
              <AgentConfigurationTab
                dependencyCheck={dependencyCheck}
                draft={configurationDraft}
                errorMessage={configurationError}
                isSaving={isSavingConfiguration}
                onAddEnvVar={onAddEnvVar}
                onChooseInstructionsFile={onChooseInstructionsFile}
                onChooseWorkingDirectory={onChooseWorkingDirectory}
                onDraftChange={onConfigurationDraftChange}
                onEnvVarChange={onConfigurationEnvVarChange}
                onRemoveEnvVar={onRemoveEnvVar}
                onSave={onSaveConfiguration}
              />
            ) : null}

            {mode === "runs" ? (
              <AgentRunsTabPanel
                agentRunError={agentRunError}
                agentRunEvents={agentRunEvents}
                agentRunLogContent={agentRunLogContent}
                agentRuns={agentRuns}
                isLoadingAgentRunDetail={isLoadingAgentRunDetail}
                isLoadingAgentRuns={isLoadingAgentRuns}
                isPerformingAgentRunAction={isPerformingAgentRunAction}
                onCancelSelectedRun={onCancelSelectedRun}
                onRefreshRuns={onRefreshRuns}
                onResumeSelectedRun={onResumeSelectedRun}
                onRetrySelectedRun={onRetrySelectedRun}
                onSelectRun={onSelectRun}
                selectedAgent={selectedAgent}
                selectedRun={selectedRun}
              />
            ) : null}
          </div>
        ) : (
          <p className="agent-detail-empty-state">
            No agents are available for this space yet.
          </p>
        )}
      </div>
    </section>
  );
}

function AgentDashboardTab({
  agent,
  companyName,
}: {
  agent: AgentRecord;
  companyName: string;
}) {
  return (
    <div className="agents-tab-panel">
      <div className="summary-grid">
        <SummaryPill
          label="Role"
          value={agent.title ?? agent.role ?? "Agent"}
        />
        <SummaryPill
          label="Status"
          value={humanizeIssueValue(String(agent.status ?? "active"))}
        />
        <SummaryPill label="Space" value={companyName} />
      </div>

      <div className="surface-list">
        <DetailRow
          label="Adapter"
          value={agentAdapterTypeLabel(agent.adapter_type)}
        />
        <DetailRow label="Reports to" value={agent.reports_to ?? "CEO"} />
        <DetailRow label="Home" value={agent.home_path ?? "Missing"} />
        <DetailRow
          label="Instructions"
          value={agent.instructions_path ?? "Missing"}
        />
        <DetailRow
          label="Monthly budget"
          value={formatCents(agent.budget_monthly_cents)}
        />
        <DetailRow
          label="Monthly spend"
          value={formatCents(agent.spent_monthly_cents)}
        />
        <DetailRow label="Created" value={formatIssueDate(agent.created_at)} />
        <DetailRow label="Updated" value={formatIssueDate(agent.updated_at)} />
      </div>

      {agent.capabilities ? (
        <section className="agent-run-section">
          <h3>Capabilities</h3>
          <p>{agent.capabilities}</p>
        </section>
      ) : null}

      {agent.metadata ? (
        <section className="agent-run-section">
          <h3>Metadata</h3>
          <pre className="agent-run-json-block">
            {formatJsonBlock(agent.metadata)}
          </pre>
        </section>
      ) : null}
    </div>
  );
}

function AgentConfigurationTab({
  draft,
  errorMessage,
  dependencyCheck,
  isSaving,
  onAddEnvVar,
  onChooseInstructionsFile,
  onChooseWorkingDirectory,
  onDraftChange,
  onEnvVarChange,
  onRemoveEnvVar,
  onSave,
}: {
  draft: AgentConfigDraft;
  errorMessage: string | null;
  dependencyCheck: RuntimeCapabilities | null;
  isSaving: boolean;
  onAddEnvVar: () => void;
  onChooseInstructionsFile: () => void;
  onChooseWorkingDirectory: () => void;
  onDraftChange: (patch: Partial<AgentConfigDraft>) => void;
  onEnvVarChange: (
    envId: string,
    patch: Partial<AgentConfigEnvVarDraft>,
  ) => void;
  onRemoveEnvVar: (envId: string) => void;
  onSave: () => void;
}) {
  const canSave = !isSaving && draft.name.trim().length > 0;
  const provider = detectAgentCliProvider(draft.command, draft.model);
  const adapterTypeOptions = mergeIssueOptions(["process"], draft.adapterType);
  const commandOptions = buildAgentCommandOptions(
    dependencyCheck,
    draft.command,
  );
  const modelOptions = buildAgentModelOptions(draft, dependencyCheck);
  const thinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    draft.thinkingEffort,
  );
  const browserToggleLabel =
    provider === "codex" ? "Enable web search" : "Enable Chrome";
  const browserToggleDescription =
    provider === "codex"
      ? "Expose Codex web search during runs."
      : "Allow browser automation inside runs.";

  return (
    <form
      className="agents-config-form"
      onSubmit={(event) => {
        event.preventDefault();
        onSave();
      }}
    >
      <div className="agents-route-actions">
        <span className="agents-run-loading">
          {isSaving ? "Saving configuration…" : "Edit and save agent settings"}
        </span>
        <button className="primary-button" disabled={!canSave} type="submit">
          {isSaving ? "Saving…" : "Save changes"}
        </button>
      </div>

      {errorMessage ? (
        <div className="issue-dialog-alert">{errorMessage}</div>
      ) : null}

      <section className="agent-config-section">
        <div className="surface-header">
          <h3>Identity</h3>
        </div>
        <div className="agent-config-grid">
          <AgentConfigField htmlFor="agent-config-name" label="Name">
            <input
              className="issue-dialog-input"
              id="agent-config-name"
              onChange={(event) => onDraftChange({ name: event.target.value })}
              placeholder="CEO"
              value={draft.name}
            />
          </AgentConfigField>
          <AgentConfigField htmlFor="agent-config-title" label="Title">
            <input
              className="issue-dialog-input"
              id="agent-config-title"
              onChange={(event) => onDraftChange({ title: event.target.value })}
              placeholder="VP of Engineering"
              value={draft.title}
            />
          </AgentConfigField>
          <AgentConfigField
            fullWidth
            htmlFor="agent-config-capabilities"
            label="Capabilities"
          >
            <textarea
              className="issue-dialog-input issue-dialog-textarea"
              id="agent-config-capabilities"
              onChange={(event) =>
                onDraftChange({ capabilities: event.target.value })
              }
              placeholder="Describe what this agent can do…"
              value={draft.capabilities}
            />
          </AgentConfigField>
          <AgentConfigField
            fullWidth
            htmlFor="agent-config-prompt-template"
            label="Prompt template"
          >
            <textarea
              className="issue-dialog-input issue-dialog-textarea"
              id="agent-config-prompt-template"
              onChange={(event) =>
                onDraftChange({ promptTemplate: event.target.value })
              }
              placeholder="You are agent {{ agent.name }}. Your role is {{ agent.role }}…"
              value={draft.promptTemplate}
            />
          </AgentConfigField>
        </div>
      </section>

      <section className="agent-config-section">
        <div className="surface-header">
          <h3>Adapter</h3>
        </div>
        <div className="agent-config-grid">
          <AgentConfigField
            htmlFor="agent-config-adapter-type"
            label="Adapter type"
          >
            <AgentConfigSelect
              ariaLabel="Adapter type"
              id="agent-config-adapter-type"
              onChange={(value) => onDraftChange({ adapterType: value })}
              value={draft.adapterType}
            >
              {adapterTypeOptions.map((option) => (
                <option key={option} value={option}>
                  {agentAdapterTypeLabel(option)}
                </option>
              ))}
            </AgentConfigSelect>
          </AgentConfigField>

          <AgentConfigPathField
            fullWidth
            htmlFor="agent-config-working-directory"
            label="Working directory"
            onChange={(value) => onDraftChange({ workingDirectory: value })}
            onChoose={onChooseWorkingDirectory}
            placeholder="/Users/you/agents/ceo"
            value={draft.workingDirectory}
          />

          <AgentConfigPathField
            fullWidth
            htmlFor="agent-config-instructions-path"
            label="Agent instructions file"
            onChange={(value) => onDraftChange({ instructionsPath: value })}
            onChoose={onChooseInstructionsFile}
            placeholder="/Users/you/agents/ceo/AGENTS.md"
            value={draft.instructionsPath}
          />
        </div>
      </section>

      <section className="agent-config-section">
        <div className="surface-header">
          <h3>Permissions &amp; configuration</h3>
        </div>
        <div className="agent-config-grid">
          <AgentConfigField htmlFor="agent-config-command" label="Command">
            <input
              className="issue-dialog-input"
              id="agent-config-command"
              list="agent-config-command-options"
              onChange={(event) =>
                onDraftChange({ command: event.target.value })
              }
              placeholder="claude or codex"
              value={draft.command}
            />
            <datalist id="agent-config-command-options">
              {commandOptions.map((option) => (
                <option key={option} value={option} />
              ))}
            </datalist>
          </AgentConfigField>
          <AgentConfigField htmlFor="agent-config-model" label="Model">
            <AgentConfigSelect
              ariaLabel="Model"
              id="agent-config-model"
              onChange={(value) => onDraftChange({ model: value })}
              value={draft.model}
            >
              {modelOptions.map((option) => (
                <option key={option} value={option}>
                  {option === "default" ? "Default" : option}
                </option>
              ))}
            </AgentConfigSelect>
          </AgentConfigField>
          <AgentConfigField
            htmlFor="agent-config-thinking-effort"
            label="Thinking effort"
          >
            <AgentConfigSelect
              ariaLabel="Thinking effort"
              id="agent-config-thinking-effort"
              onChange={(value) => onDraftChange({ thinkingEffort: value })}
              value={draft.thinkingEffort}
            >
              {thinkingEffortOptions.map((option) => (
                <option key={option} value={option}>
                  {capitalize(option)}
                </option>
              ))}
            </AgentConfigSelect>
          </AgentConfigField>
          <AgentConfigField
            fullWidth
            htmlFor="agent-config-bootstrap-prompt"
            label="Bootstrap prompt (first run)"
          >
            <textarea
              className="issue-dialog-input issue-dialog-textarea"
              id="agent-config-bootstrap-prompt"
              onChange={(event) =>
                onDraftChange({ bootstrapPrompt: event.target.value })
              }
              placeholder="Optional initial setup prompt for the first run"
              value={draft.bootstrapPrompt}
            />
          </AgentConfigField>

          <div className="agent-config-toggle-grid agent-config-field-full">
            <AgentConfigToggleField
              checked={draft.enableChrome}
              description={browserToggleDescription}
              label={browserToggleLabel}
              onChange={(checked) => onDraftChange({ enableChrome: checked })}
            />
            <AgentConfigToggleField
              checked={draft.skipPermissions}
              description="Skip interactive permission pauses during execution."
              label="Skip permissions"
              onChange={(checked) =>
                onDraftChange({ skipPermissions: checked })
              }
            />
          </div>

          <AgentConfigField
            htmlFor="agent-config-monthly-budget"
            label="Monthly budget (USD)"
          >
            <input
              className="issue-dialog-input"
              id="agent-config-monthly-budget"
              inputMode="decimal"
              onChange={(event) =>
                onDraftChange({ monthlyBudget: event.target.value })
              }
              placeholder="0"
              value={draft.monthlyBudget}
            />
          </AgentConfigField>
          <AgentConfigField
            htmlFor="agent-config-max-turns"
            label="Max turns per run"
          >
            <div className="surface-empty-copy">
              Not currently enforced for local Claude or Codex CLI agents.
            </div>
          </AgentConfigField>
          <AgentConfigField
            fullWidth
            htmlFor="agent-config-extra-args"
            label="Extra args (comma-separated)"
          >
            <input
              className="issue-dialog-input"
              id="agent-config-extra-args"
              onChange={(event) =>
                onDraftChange({ extraArgs: event.target.value })
              }
              placeholder="--verbose, --foo=bar"
              value={draft.extraArgs}
            />
          </AgentConfigField>

          <div className="agent-config-field-full agent-config-env-section">
            <div className="surface-header">
              <h3>Environment variables</h3>
              <AgentConfigInlineButton onClick={onAddEnvVar}>
                Add variable
              </AgentConfigInlineButton>
            </div>

            {draft.envVars.length ? (
              <div className="agent-config-env-list">
                {draft.envVars.map((envVar) => (
                  <div className="agent-config-env-row" key={envVar.id}>
                    <input
                      aria-label="Environment variable key"
                      className="issue-dialog-input"
                      onChange={(event) =>
                        onEnvVarChange(envVar.id, { key: event.target.value })
                      }
                      placeholder="KEY"
                      value={envVar.key}
                    />
                    <AgentConfigSelect
                      ariaLabel="Environment variable mode"
                      onChange={(value) =>
                        onEnvVarChange(envVar.id, {
                          mode: value as "plain" | "secret",
                        })
                      }
                      value={envVar.mode}
                    >
                      <option value="plain">Plain</option>
                      <option value="secret">Secret</option>
                    </AgentConfigSelect>
                    <input
                      aria-label="Environment variable value"
                      className="issue-dialog-input"
                      onChange={(event) =>
                        onEnvVarChange(envVar.id, { value: event.target.value })
                      }
                      placeholder="value"
                      value={envVar.value}
                    />
                    <AgentConfigInlineButton
                      destructive
                      onClick={() => onRemoveEnvVar(envVar.id)}
                    >
                      Remove
                    </AgentConfigInlineButton>
                  </div>
                ))}
              </div>
            ) : (
              <p className="surface-empty-copy">
                No custom environment variables yet.
              </p>
            )}
          </div>

          <AgentConfigField
            htmlFor="agent-config-timeout"
            label="Timeout (sec)"
          >
            <input
              className="issue-dialog-input"
              id="agent-config-timeout"
              inputMode="numeric"
              onChange={(event) =>
                onDraftChange({ timeoutSec: event.target.value })
              }
              placeholder="0"
              value={draft.timeoutSec}
            />
          </AgentConfigField>
          <AgentConfigField
            htmlFor="agent-config-interrupt-grace"
            label="Interrupt grace period (sec)"
          >
            <input
              className="issue-dialog-input"
              id="agent-config-interrupt-grace"
              inputMode="numeric"
              onChange={(event) =>
                onDraftChange({ interruptGraceSec: event.target.value })
              }
              placeholder="15"
              value={draft.interruptGraceSec}
            />
          </AgentConfigField>
        </div>
      </section>

      <section className="agent-config-section">
        <div className="surface-header">
          <h3>Permissions</h3>
        </div>
        <AgentConfigToggleField
          checked={draft.canCreateAgents}
          description="Permit this agent to create and manage new agents."
          label="Can create new agents"
          onChange={(checked) => onDraftChange({ canCreateAgents: checked })}
        />
      </section>
    </form>
  );
}

function AgentConfigField({
  children,
  fullWidth = false,
  htmlFor,
  label,
}: {
  children: ReactNode;
  fullWidth?: boolean;
  htmlFor?: string;
  label: string;
}) {
  return (
    <div
      className={
        fullWidth
          ? "issue-dialog-field agent-config-field-full"
          : "issue-dialog-field"
      }
    >
      <label className="issue-dialog-label" htmlFor={htmlFor}>
        {label}
      </label>
      {children}
    </div>
  );
}

function AgentConfigSelect({
  ariaLabel,
  children,
  id,
  onChange,
  value,
}: {
  ariaLabel: string;
  children: ReactNode;
  id?: string;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <div className="issue-dialog-select-shell agent-config-select-shell">
      <select
        aria-label={ariaLabel}
        className="issue-dialog-select"
        id={id}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        {children}
      </select>
      <span aria-hidden="true" className="issue-dialog-select-arrow">
        ▼
      </span>
    </div>
  );
}

function AgentConfigInlineButton({
  children,
  destructive = false,
  onClick,
  type = "button",
}: {
  children: ReactNode;
  destructive?: boolean;
  onClick: () => void;
  type?: "button" | "submit";
}) {
  return (
    <button
      className={
        destructive
          ? "agent-config-inline-button destructive"
          : "agent-config-inline-button"
      }
      onClick={onClick}
      type={type}
    >
      {children}
    </button>
  );
}

function AgentConfigPathField({
  fullWidth = false,
  htmlFor,
  label,
  onChange,
  onChoose,
  placeholder,
  value,
}: {
  fullWidth?: boolean;
  htmlFor: string;
  label: string;
  onChange: (value: string) => void;
  onChoose: () => void;
  placeholder: string;
  value: string;
}) {
  return (
    <AgentConfigField fullWidth={fullWidth} htmlFor={htmlFor} label={label}>
      <div className="agent-config-picker-shell">
        <input
          className="issue-dialog-input agent-config-picker-input"
          id={htmlFor}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
          value={value}
        />
        <AgentConfigInlineButton onClick={onChoose}>
          Choose
        </AgentConfigInlineButton>
      </div>
    </AgentConfigField>
  );
}

function AgentConfigToggleField({
  checked,
  description,
  label,
  onChange,
}: {
  checked: boolean;
  description: string;
  label: string;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="agent-config-toggle-card">
      <div>
        <strong>{label}</strong>
        <span>{description}</span>
      </div>
      <button
        aria-pressed={checked}
        className={
          checked ? "agent-config-toggle active" : "agent-config-toggle"
        }
        onClick={() => onChange(!checked)}
        type="button"
      >
        <span />
      </button>
    </label>
  );
}

function AgentRunEventDetails({ event }: { event: AgentRunEventRecord }) {
  const payload = objectFromUnknown(event.payload);
  const item = objectFromUnknown(payload.item);
  const usage = objectFromUnknown(payload.usage);
  const cleanMessage = cleanedAgentRunEventMessage(event.message);

  if (event.event_type === "item.completed.agent_message") {
    const text = stringFromUnknown(item.text).trim() || cleanMessage;
    if (text) {
      return (
        <div className="agent-run-structured-card">
          <div className="agent-run-structured-header">
            <span className="agent-run-structured-kicker">Agent update</span>
            <span className="agent-run-structured-state neutral">
              Completed
            </span>
          </div>
          <div className="agent-run-structured-copy">{text}</div>
        </div>
      );
    }
  }

  if (
    event.event_type === "item.started.command_execution" ||
    event.event_type === "item.completed.command_execution"
  ) {
    const command = stringFromUnknown(item.command).trim();
    const output = stringFromUnknown(item.aggregated_output).trim();
    const status = stringFromUnknown(item.status, "completed");
    const exitCode = numberFromUnknown(item.exit_code);

    return (
      <div className="agent-run-structured-card">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Command</span>
          <span
            className={`agent-run-structured-state ${agentRunEventStateTone(status)}`}
          >
            {agentRunEventStateLabel(status)}
          </span>
        </div>
        {command ? (
          <pre className="agent-run-structured-command">{command}</pre>
        ) : null}
        {output ? (
          <pre className="agent-run-structured-output">{output}</pre>
        ) : null}
        {typeof exitCode === "number" ? (
          <div className="agent-run-structured-meta">
            <span>Exit code {exitCode}</span>
          </div>
        ) : null}
      </div>
    );
  }

  if (event.event_type === "thread.started") {
    const threadId = stringFromUnknown(payload.thread_id).trim();
    return (
      <div className="agent-run-structured-card subtle">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Thread</span>
          <span className="agent-run-structured-state neutral">Started</span>
        </div>
        <div className="agent-run-structured-copy">
          {threadId
            ? `Codex resumed thread ${threadId}.`
            : "Codex thread started."}
        </div>
      </div>
    );
  }

  if (event.event_type === "turn.started") {
    return (
      <div className="agent-run-structured-card subtle">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Turn</span>
          <span className="agent-run-structured-state running">Running</span>
        </div>
        <div className="agent-run-structured-copy">
          Codex started a new turn.
        </div>
      </div>
    );
  }

  if (event.event_type === "turn.completed") {
    const inputTokens = numberFromUnknown(usage.input_tokens);
    const cachedInputTokens = numberFromUnknown(usage.cached_input_tokens);
    const outputTokens = numberFromUnknown(usage.output_tokens);

    return (
      <div className="agent-run-structured-card subtle">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Turn</span>
          <span className="agent-run-structured-state succeeded">
            Completed
          </span>
        </div>
        <div className="agent-run-structured-copy">
          Codex finished the turn.
        </div>
        {inputTokens !== undefined ||
        cachedInputTokens !== undefined ||
        outputTokens !== undefined ? (
          <div className="agent-run-structured-meta">
            {inputTokens !== undefined ? (
              <span>{formatAgentRunMetricLabel("Input", inputTokens)}</span>
            ) : null}
            {cachedInputTokens !== undefined ? (
              <span>
                {formatAgentRunMetricLabel("Cached", cachedInputTokens)}
              </span>
            ) : null}
            {outputTokens !== undefined ? (
              <span>{formatAgentRunMetricLabel("Output", outputTokens)}</span>
            ) : null}
          </div>
        ) : null}
      </div>
    );
  }

  if (event.event_type === "run_started") {
    const localSessionId = stringFromUnknown(payload.local_session_id).trim();
    return (
      <div className="agent-run-structured-card subtle">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Run</span>
          <span className="agent-run-structured-state neutral">Started</span>
        </div>
        <div className="agent-run-structured-copy">
          {cleanMessage || "The run has started."}
        </div>
        {localSessionId ? (
          <div className="agent-run-structured-meta">
            <span>Local session {localSessionId}</span>
          </div>
        ) : null}
      </div>
    );
  }

  if (
    event.event_type === "finished" ||
    event.event_type === "stopped" ||
    event.event_type === "timed_out"
  ) {
    const success = booleanFromUnknown(payload.success);
    const exitCode = numberFromUnknown(payload.exit_code);
    const message =
      cleanMessage ||
      (event.event_type === "timed_out"
        ? "The run timed out."
        : event.event_type === "stopped"
          ? "The run was cancelled."
          : success
            ? "The run finished successfully."
            : "The run finished.");

    return (
      <div className="agent-run-structured-card subtle">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Run</span>
          <span
            className={`agent-run-structured-state ${agentRunEventStateTone(
              success ? "completed" : event.event_type,
            )}`}
          >
            {agentRunEventStateLabel(success ? "completed" : event.event_type)}
          </span>
        </div>
        <div className="agent-run-structured-copy">{message}</div>
        {typeof exitCode === "number" ? (
          <div className="agent-run-structured-meta">
            <span>Exit code {exitCode}</span>
          </div>
        ) : null}
      </div>
    );
  }

  if (
    (event.stream === "stderr" || event.event_type === "stderr") &&
    cleanMessage
  ) {
    return (
      <div className="agent-run-structured-card warning">
        <div className="agent-run-structured-header">
          <span className="agent-run-structured-kicker">Warning</span>
          <span className="agent-run-structured-state failed">
            {event.level ? capitalize(event.level) : "Stderr"}
          </span>
        </div>
        <pre className="agent-run-structured-output">{cleanMessage}</pre>
      </div>
    );
  }

  if (cleanMessage) {
    return <p>{cleanMessage}</p>;
  }

  if (event.payload !== undefined && event.payload !== null) {
    return (
      <pre className="agent-run-json-block">
        {formatJsonBlock(event.payload)}
      </pre>
    );
  }

  return null;
}

function AgentRunsTabPanel({
  agentRunError,
  agentRunEvents,
  agentRunLogContent,
  agentRuns,
  isLoadingAgentRunDetail,
  isLoadingAgentRuns,
  isPerformingAgentRunAction,
  onCancelSelectedRun,
  onRefreshRuns,
  onResumeSelectedRun,
  onRetrySelectedRun,
  onSelectRun,
  selectedAgent,
  selectedRun,
}: {
  agentRunError: string | null;
  agentRunEvents: AgentRunEventRecord[];
  agentRunLogContent: string;
  agentRuns: AgentRunRecord[];
  isLoadingAgentRunDetail: boolean;
  isLoadingAgentRuns: boolean;
  isPerformingAgentRunAction: boolean;
  onCancelSelectedRun: () => void;
  onRefreshRuns: () => void;
  onResumeSelectedRun: () => void;
  onRetrySelectedRun: () => void;
  onSelectRun: (runId: string) => void;
  selectedAgent: AgentRecord | null;
  selectedRun: AgentRunRecord | null;
}) {
  return (
    <div className="agents-tab-panel">
      <div className="agents-route-actions">
        {isLoadingAgentRuns || isLoadingAgentRunDetail ? (
          <span className="agents-run-loading">Loading…</span>
        ) : null}
        <button
          className="secondary-button compact-button"
          onClick={onRefreshRuns}
          type="button"
        >
          Refresh
        </button>
      </div>

      {selectedAgent ? (
        <div className="agents-runs-layout">
          <section className="surface-panel agents-runs-list-panel">
            <div className="surface-header">
              <h3>Runs</h3>
              <span>{agentRuns.length}</span>
            </div>

            {agentRunError ? (
              <div className="agents-run-error">{agentRunError}</div>
            ) : null}

            {agentRuns.length ? (
              <div className="surface-list dense">
                {agentRuns.map((run) => (
                  <button
                    className={
                      selectedRun?.id === run.id
                        ? "agent-run-list-button active"
                        : "agent-run-list-button"
                    }
                    key={run.id}
                    onClick={() => onSelectRun(run.id)}
                    type="button"
                  >
                    <div className="agent-run-list-row-head">
                      <div>
                        <strong>{shortAgentRunTitle(run.id)}</strong>
                        <span>{agentRunSummary(run)}</span>
                      </div>
                      <RunStatusBadge status={run.status} />
                    </div>
                    <div className="agent-run-list-row-meta">
                      <span>
                        {agentRunInvocationSourceLabel(run.invocation_source)}
                      </span>
                      <span>{formatRelativeAgentRunDate(run.created_at)}</span>
                      {run.wake_reason ? (
                        <span>{agentRunWakeReasonLabel(run.wake_reason)}</span>
                      ) : null}
                    </div>
                  </button>
                ))}
              </div>
            ) : (
              <p className="surface-empty-copy">
                No runs yet. They will appear here once the agent has been
                invoked.
              </p>
            )}
          </section>

          <section className="surface-panel agents-runs-detail-panel">
            {selectedRun ? (
              <>
                <div className="agents-route-header-row">
                  <div>
                    <span className="route-kicker">
                      {shortAgentRunTitle(selectedRun.id)}
                    </span>
                    <h2>{agentRunSummary(selectedRun)}</h2>
                    <p>
                      {agentRunInvocationSourceLabel(
                        selectedRun.invocation_source,
                      )}{" "}
                      · {formatRelativeAgentRunDate(selectedRun.created_at)}
                    </p>
                  </div>
                  <div className="agents-route-actions">
                    {(selectedRun.status === "queued" ||
                      selectedRun.status === "running") && (
                      <button
                        className="secondary-button compact-button"
                        disabled={isPerformingAgentRunAction}
                        onClick={onCancelSelectedRun}
                        type="button"
                      >
                        {selectedRun.status === "running"
                          ? "Stop Run"
                          : "Cancel Run"}
                      </button>
                    )}
                    {(selectedRun.status === "failed" ||
                      selectedRun.status === "timed_out") && (
                      <button
                        className="secondary-button compact-button"
                        disabled={isPerformingAgentRunAction}
                        onClick={onRetrySelectedRun}
                        type="button"
                      >
                        Retry
                      </button>
                    )}
                    {selectedRun.status === "failed" &&
                    selectedRun.error_code === "process_lost" ? (
                      <button
                        className="primary-button compact-button"
                        disabled={isPerformingAgentRunAction}
                        onClick={onResumeSelectedRun}
                        type="button"
                      >
                        Resume
                      </button>
                    ) : null}
                    <RunStatusBadge status={selectedRun.status} />
                  </div>
                </div>

                <div className="summary-grid">
                  <SummaryPill
                    label="Status"
                    value={agentRunStatusLabel(selectedRun.status)}
                  />
                  <SummaryPill
                    label="Invocation"
                    value={agentRunInvocationSourceLabel(
                      selectedRun.invocation_source,
                    )}
                  />
                  <SummaryPill
                    label="Wake reason"
                    value={agentRunWakeReasonLabel(selectedRun.wake_reason)}
                  />
                </div>

                <div className="surface-list">
                  <DetailRow
                    label="Started"
                    value={formatIssueDate(
                      selectedRun.started_at ?? selectedRun.created_at,
                    )}
                  />
                  <DetailRow
                    label="Finished"
                    value={formatIssueDate(selectedRun.finished_at)}
                  />
                  <DetailRow
                    label="Trigger detail"
                    value={agentRunTriggerDetailLabel(
                      selectedRun.trigger_detail,
                    )}
                  />
                  <DetailRow
                    label="Exit code"
                    value={
                      typeof selectedRun.exit_code === "number"
                        ? String(selectedRun.exit_code)
                        : "n/a"
                    }
                  />
                  <DetailRow
                    label="Session before"
                    value={selectedRun.session_id_before ?? "n/a"}
                  />
                  <DetailRow
                    label="Session after"
                    value={selectedRun.session_id_after ?? "n/a"}
                  />
                </div>

                <section className="agent-run-section">
                  <h3>Events</h3>
                  {agentRunEvents.length ? (
                    <div className="agent-run-event-list">
                      {agentRunEvents.map((event) => (
                        <article
                          className="agent-run-event-row"
                          key={`${event.id}-${event.seq}`}
                        >
                          <div className="agent-run-event-row-head">
                            <strong>
                              {agentRunEventLabel(event.event_type)}
                            </strong>
                            <span>{formatIssueDate(event.created_at)}</span>
                          </div>
                          <AgentRunEventDetails event={event} />
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="surface-empty-copy">
                      No run events have been recorded yet.
                    </p>
                  )}
                </section>

                <section className="agent-run-section">
                  <h3>Log output</h3>
                  <pre className="agent-run-log-block">
                    {agentRunLogContent || "No log output yet."}
                  </pre>
                </section>

                {selectedRun.result_json !== undefined &&
                selectedRun.result_json !== null ? (
                  <section className="agent-run-section">
                    <h3>Result JSON</h3>
                    <pre className="agent-run-json-block">
                      {formatJsonBlock(selectedRun.result_json)}
                    </pre>
                  </section>
                ) : null}

                {selectedRun.context_snapshot !== undefined &&
                selectedRun.context_snapshot !== null ? (
                  <section className="agent-run-section">
                    <h3>Context snapshot</h3>
                    <pre className="agent-run-json-block">
                      {formatJsonBlock(selectedRun.context_snapshot)}
                    </pre>
                  </section>
                ) : null}
              </>
            ) : (
              <p className="surface-empty-copy">
                Select a run to inspect its status, events, and log output.
              </p>
            )}
          </section>
        </div>
      ) : (
        <p>Select an agent to review its runs.</p>
      )}
    </div>
  );
}

function RunStatusBadge({ status }: { status: string }) {
  return (
    <span className={`agent-run-status-badge ${agentRunStatusTone(status)}`}>
      {agentRunStatusLabel(status)}
    </span>
  );
}

function AgentHeaderActionChip({
  icon,
  label,
  onClick,
}: {
  icon: ReactNode;
  label: string;
  onClick?: () => void;
}) {
  if (onClick) {
    return (
      <button
        className="agent-page-header-action-chip"
        onClick={onClick}
        type="button"
      >
        <span aria-hidden="true" className="agent-page-header-action-icon">
          {icon}
        </span>
        <span>{label}</span>
      </button>
    );
  }

  return (
    <span className="agent-page-header-action-chip">
      <span aria-hidden="true" className="agent-page-header-action-icon">
        {icon}
      </span>
      <span>{label}</span>
    </span>
  );
}

function BoardSidebarButton({
  active,
  icon,
  label,
  onClick,
  trailing,
}: {
  active: boolean;
  icon?: CompanyContextMenuIconKey | null;
  label: string;
  onClick: () => void;
  trailing?: string | null;
}) {
  return (
    <button
      className={
        active ? "board-sidebar-button active" : "board-sidebar-button"
      }
      onClick={onClick}
      type="button"
    >
      <span className="board-sidebar-button-copy">
        {icon ? (
          <span aria-hidden="true" className="board-sidebar-button-icon">
            <CompanyContextMenuIcon
              className="board-sidebar-icon"
              icon={icon}
            />
          </span>
        ) : null}
        <span>{label}</span>
      </span>
      {trailing ? <span className="sidebar-live-count">{trailing}</span> : null}
    </button>
  );
}

function SidebarLinkButton({
  label,
  onClick,
}: {
  label: string;
  onClick: () => void;
}) {
  return (
    <button className="sidebar-link-button" onClick={onClick} type="button">
      <span className="sidebar-link-icon">+</span>
      <span>{label}</span>
    </button>
  );
}

function ShadcnSelect<T extends string>({
  ariaLabel,
  onChange,
  options,
  value,
}: {
  ariaLabel: string;
  onChange: (value: T) => void;
  options: Array<SelectOption<T>>;
  value: T;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const selectRef = useRef<HTMLDivElement | null>(null);
  const optionRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const selectedIndex = Math.max(
    options.findIndex((option) => option.value === value),
    0,
  );
  const selectedOption = options[selectedIndex] ?? options[0] ?? null;

  useEffect(() => {
    if (!isOpen) {
      return;
    }

    const closeMenu = (event?: Event) => {
      const target = event?.target as Node | null | undefined;
      if (target && selectRef.current?.contains(target)) {
        return;
      }
      setIsOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) {
      return;
    }

    const frame = window.requestAnimationFrame(() => {
      optionRefs.current[selectedIndex]?.focus();
    });

    return () => window.cancelAnimationFrame(frame);
  }, [isOpen, selectedIndex]);

  const handleTriggerKeyDown = (
    event: ReactKeyboardEvent<HTMLButtonElement>,
  ) => {
    if (
      event.key === "ArrowDown" ||
      event.key === "ArrowUp" ||
      event.key === "Enter" ||
      event.key === " "
    ) {
      event.preventDefault();
      setIsOpen(true);
    }
  };

  const handleOptionKeyDown = (
    event: ReactKeyboardEvent<HTMLButtonElement>,
    index: number,
  ) => {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      optionRefs.current[(index + 1) % options.length]?.focus();
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      optionRefs.current[
        (index - 1 + options.length) % options.length
      ]?.focus();
      return;
    }

    if (event.key === "Home") {
      event.preventDefault();
      optionRefs.current[0]?.focus();
      return;
    }

    if (event.key === "End") {
      event.preventDefault();
      optionRefs.current[options.length - 1]?.focus();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      setIsOpen(false);
    }
  };

  return (
    <div
      className={isOpen ? "shadcn-select open" : "shadcn-select"}
      onPointerDown={(event) => event.stopPropagation()}
      ref={selectRef}
    >
      <button
        aria-expanded={isOpen}
        aria-haspopup="listbox"
        className="shadcn-select-trigger"
        onClick={() => setIsOpen((current) => !current)}
        onKeyDown={handleTriggerKeyDown}
        type="button"
      >
        <span className="shadcn-select-value">
          {selectedOption?.label ?? "Select option"}
        </span>
        <span aria-hidden="true" className="shadcn-select-icon">
          <ChevronUpDownIcon />
        </span>
      </button>

      {isOpen ? (
        <div
          aria-label={ariaLabel}
          className="shadcn-select-content"
          role="listbox"
        >
          {options.map((option, index) => {
            const isSelected = option.value === selectedOption?.value;
            return (
              <button
                aria-selected={isSelected}
                className={
                  isSelected
                    ? "shadcn-select-item is-selected"
                    : "shadcn-select-item"
                }
                key={option.value}
                onClick={() => {
                  onChange(option.value);
                  setIsOpen(false);
                }}
                onKeyDown={(event) => handleOptionKeyDown(event, index)}
                ref={(node) => {
                  optionRefs.current[index] = node;
                }}
                role="option"
                type="button"
              >
                <span>{option.label}</span>
                <span
                  aria-hidden="true"
                  className="shadcn-select-item-indicator"
                >
                  {isSelected ? <CheckIcon /> : null}
                </span>
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

function DashboardBirdsEyeRouteView({
  agents,
  chats,
  dependencyCheck,
  isLoadingOverview,
  onClosePreview,
  onCreateProject,
  onCreateQuickChat,
  onOpenIssueDetail,
  onOpenIssuePreview,
  previewIssue,
  projects,
  workspaces,
}: {
  agents: AgentRecord[];
  chats: DashboardOverviewChatRecord[];
  dependencyCheck: RuntimeCapabilities | null;
  isLoadingOverview: boolean;
  onClosePreview: () => void;
  onCreateProject: () => void;
  onCreateQuickChat: (
    title: string,
    defaults: CreateIssueDialogDefaults,
  ) => Promise<IssueRecord>;
  onOpenIssueDetail: (issueId: string) => void;
  onOpenIssuePreview: (issueId: string) => void;
  previewIssue: IssueRecord | null;
  projects: ProjectRecord[];
  workspaces: WorkspaceRecord[];
}) {
  const [expandedRowIds, setExpandedRowIds] = useState<Record<string, boolean>>(
    {},
  );
  const expandedProjectIds = useMemo(
    () =>
      projects
        .filter((project) => expandedRowIds[`project:${project.id}`] ?? false)
        .map((project) => project.id),
    [expandedRowIds, projects],
  );
  const projectWorktreesByProjectId = useDashboardProjectWorktrees(
    projects,
    expandedProjectIds,
  );
  const treeModel = useMemo(
    () =>
      buildBirdsEyeTree({
        agents,
        chats,
        dependencyCheck,
        projectWorktreesByProjectId,
        projects,
        workspaces,
      }),
    [
      agents,
      chats,
      dependencyCheck,
      projectWorktreesByProjectId,
      projects,
      workspaces,
    ],
  );
  const defaultQuickCreateState = useMemo(
    () => createBirdsEyeQuickCreateState(dependencyCheck),
    [dependencyCheck],
  );
  const [focusedRowId, setFocusedRowId] = useState<string | null>(null);
  const [pendingFocusRowId, setPendingFocusRowId] = useState<string | null>(
    null,
  );
  const [birdsEyeCanvasOffset, setBirdsEyeCanvasOffset] =
    useState<DashboardCanvasOffset>(defaultBirdsEyeCanvasOffset);
  const [birdsEyeCanvasZoomIndex, setBirdsEyeCanvasZoomIndex] = useState(
    defaultBirdsEyeCanvasZoomIndex,
  );
  const [isBirdsEyeCanvasDragging, setIsBirdsEyeCanvasDragging] =
    useState(false);
  const [isHelpMenuOpen, setIsHelpMenuOpen] = useState(false);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [commandPaletteIndex, setCommandPaletteIndex] = useState(0);
  const [quickCreateState, setQuickCreateState] =
    useState<BirdsEyeQuickCreateState>(defaultQuickCreateState);
  const focusedRowIdRef = useRef<string | null>(null);
  const rowRefs = useRef(new Map<string, HTMLButtonElement | null>());
  const quickCreateInputRef = useRef<HTMLInputElement | null>(null);
  const commandPaletteInputRef = useRef<HTMLInputElement | null>(null);
  const canvasViewportRef = useRef<HTMLDivElement | null>(null);
  const canvasPanRef = useRef<{
    pointerId: number;
    originX: number;
    originY: number;
    startX: number;
    startY: number;
  } | null>(null);
  const birdsEyeCanvasWheelZoomRef = useRef<{
    accumulatedDeltaY: number;
    lastEventTime: number;
  }>({
    accumulatedDeltaY: 0,
    lastEventTime: 0,
  });
  const helpButtonRef = useRef<HTMLButtonElement | null>(null);
  const helpMenuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    setExpandedRowIds((current) => {
      let hasChanges = false;
      const next = { ...current };

      treeModel.projects.forEach((project, index) => {
        if (next[project.rowId] === undefined) {
          next[project.rowId] = index === 0 || project.liveRunCount > 0;
          hasChanges = true;
        }

        for (const folder of project.folders) {
          if (next[folder.rowId] === undefined) {
            next[folder.rowId] =
              folder.chatCount > 0 &&
              (folder.folderType === "repo_root" ||
                folder.liveRunCount > 0 ||
                folder.chatCount <= 4);
            hasChanges = true;
          }
        }
      });

      for (const rowId of Object.keys(next)) {
        if (!treeModel.rowIds.has(rowId)) {
          delete next[rowId];
          hasChanges = true;
        }
      }

      return hasChanges ? next : current;
    });
  }, [treeModel.projects, treeModel.rowIds]);

  const visibleRows = useMemo(
    () => flattenBirdsEyeTree(treeModel.projects, expandedRowIds),
    [expandedRowIds, treeModel.projects],
  );
  const visibleRowLookup = useMemo(
    () => new Map(visibleRows.map((row) => [row.rowId, row])),
    [visibleRows],
  );
  const focusedRowIndex = Math.max(
    visibleRows.findIndex((row) => row.rowId === focusedRowId),
    0,
  );
  const focusedRow = visibleRows[focusedRowIndex] ?? null;
  const previewChat = previewIssue?.id
    ? (treeModel.chatByIssueId.get(previewIssue.id) ?? null)
    : null;
  const recentChatRowId = useMemo(() => {
    return visibleRows
      .filter(
        (row): row is BirdsEyeVisibleRow & { node: BirdsEyeChatNode } =>
          row.node.kind === "chat",
      )
      .slice()
      .sort((left, right) => {
        const leftTime =
          parseIssueDate(left.node.lastActivityAt)?.getTime() ?? 0;
        const rightTime =
          parseIssueDate(right.node.lastActivityAt)?.getTime() ?? 0;
        return rightTime - leftTime;
      })[0]?.rowId;
  }, [visibleRows]);
  const impactSessionIds = useMemo(() => {
    const ids = new Set<string>();

    for (const row of visibleRows) {
      if (row.node.kind === "chat" && row.node.sessionId) {
        ids.add(row.node.sessionId);
      }
    }

    if (previewChat?.sessionId) {
      ids.add(previewChat.sessionId);
    }

    return [...ids];
  }, [previewChat?.sessionId, visibleRows]);
  const codeImpactBySessionId = useBirdsEyeCodeImpact(impactSessionIds);
  const birdsEyeCanvasZoomScale =
    birdsEyeCanvasZoomLevels[birdsEyeCanvasZoomIndex] ?? 1;
  const setBirdsEyeFocusedRow = (
    nextRowId: string | null,
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    const previousRowId = focusedRowIdRef.current;
    if (previousRowId === nextRowId) {
      return;
    }

    focusedRowIdRef.current = nextRowId;
    setFocusedRowId(nextRowId);

    // Keep playback in the original interaction tick so browsers allow it.
    if (shouldPlayBirdsEyeFocusSound(previousRowId, nextRowId, cause)) {
      playBirdsEyeFocusSound();
    }
  };

  useEffect(() => {
    if (visibleRows.length === 0) {
      setBirdsEyeFocusedRow(null);
      return;
    }

    if (
      pendingFocusRowId &&
      visibleRows.some((row) => row.rowId === pendingFocusRowId)
    ) {
      setBirdsEyeFocusedRow(pendingFocusRowId);
      setPendingFocusRowId(null);
      return;
    }

    if (
      !(focusedRowId && visibleRows.some((row) => row.rowId === focusedRowId))
    ) {
      setBirdsEyeFocusedRow(visibleRows[0]?.rowId ?? null);
    }
  }, [focusedRowId, pendingFocusRowId, visibleRows]);

  useEffect(() => {
    if (!focusedRowId || quickCreateState.isOpen || isCommandPaletteOpen) {
      return;
    }

    rowRefs.current.get(focusedRowId)?.focus({ preventScroll: true });
  }, [focusedRowId, isCommandPaletteOpen, quickCreateState.isOpen]);

  useEffect(() => {
    if (!quickCreateState.isOpen) {
      return;
    }

    const frameId = window.requestAnimationFrame(() => {
      quickCreateInputRef.current?.focus();
      quickCreateInputRef.current?.select();
    });

    return () => {
      window.cancelAnimationFrame(frameId);
    };
  }, [quickCreateState.folderRowId, quickCreateState.isOpen]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }

    const frameId = window.requestAnimationFrame(() => {
      commandPaletteInputRef.current?.focus();
      commandPaletteInputRef.current?.select();
    });

    return () => {
      window.cancelAnimationFrame(frameId);
    };
  }, [isCommandPaletteOpen]);

  useEffect(() => {
    if (!isHelpMenuOpen) {
      return;
    }

    const closeMenu = (event?: Event) => {
      const target = event?.target as Node | null | undefined;
      if (
        target &&
        (helpButtonRef.current?.contains(target) ||
          helpMenuRef.current?.contains(target))
      ) {
        return;
      }
      setIsHelpMenuOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsHelpMenuOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isHelpMenuOpen]);

  const toggleRowExpansion = (rowId: string, nextValue?: boolean) => {
    setExpandedRowIds((current) => ({
      ...current,
      [rowId]: nextValue ?? !current[rowId],
    }));
  };

  const ensureRowAncestorsExpanded = (row: BirdsEyeVisibleRow | null) => {
    if (!row) {
      return;
    }

    const parents: string[] = [];
    let currentParentId = row.parentRowId;

    while (currentParentId) {
      parents.push(currentParentId);
      currentParentId =
        visibleRowLookup.get(currentParentId)?.parentRowId ?? null;
    }

    if (parents.length === 0) {
      return;
    }

    setExpandedRowIds((current) => {
      const next = { ...current };
      for (const parentId of parents) {
        next[parentId] = true;
      }
      return next;
    });
  };

  const focusRowByIndex = (
    index: number,
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    if (visibleRows.length === 0) {
      return;
    }

    const nextRow =
      visibleRows[clampNumber(index, 0, visibleRows.length - 1)] ?? null;
    if (!nextRow) {
      return;
    }

    ensureRowAncestorsExpanded(nextRow);
    setBirdsEyeFocusedRow(nextRow.rowId, cause);
  };

  const siblingRowsForRow = (row: BirdsEyeVisibleRow | null) => {
    if (!row) {
      return [];
    }

    return visibleRows.filter((entry) => entry.parentRowId === row.parentRowId);
  };

  const focusSiblingRow = (
    row: BirdsEyeVisibleRow | null,
    direction: "previous" | "next",
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    if (!row) {
      return;
    }

    const siblingRows = siblingRowsForRow(row);
    if (siblingRows.length <= 1) {
      return;
    }

    const currentIndex = siblingRows.findIndex(
      (entry) => entry.rowId === row.rowId,
    );
    if (currentIndex < 0) {
      return;
    }

    const nextIndex =
      direction === "next"
        ? (currentIndex + 1) % siblingRows.length
        : (currentIndex - 1 + siblingRows.length) % siblingRows.length;
    const nextRow = siblingRows[nextIndex] ?? null;

    if (!nextRow) {
      return;
    }

    setBirdsEyeFocusedRow(nextRow.rowId, cause);
  };

  const firstChildRowIdForRow = (row: BirdsEyeVisibleRow | null) => {
    if (!(row && row.hasChildren)) {
      return null;
    }

    if (row.node.kind === "project") {
      return row.node.folders[0]?.rowId ?? null;
    }

    if (row.node.kind === "folder") {
      return row.node.chats[0]?.rowId ?? null;
    }

    return null;
  };

  const openRow = (
    row: BirdsEyeVisibleRow | null,
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    if (!row) {
      return;
    }

    if (row.node.kind === "chat") {
      if (previewIssue?.id === row.node.chat.id) {
        onOpenIssueDetail(row.node.chat.id);
        return;
      }
      onOpenIssuePreview(row.node.chat.id);
      return;
    }

    if (!row.hasChildren) {
      return;
    }

    if (!(expandedRowIds[row.rowId] ?? false)) {
      toggleRowExpansion(row.rowId, true);
    }

    const firstChildRowId = firstChildRowIdForRow(row);
    if (firstChildRowId) {
      setBirdsEyeFocusedRow(firstChildRowId, cause);
    }
  };

  const closeRow = (
    row: BirdsEyeVisibleRow | null,
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    if (!row) {
      return;
    }

    if (row.node.kind === "chat") {
      onClosePreview();
      if (row.parentRowId) {
        setBirdsEyeFocusedRow(row.parentRowId, cause);
      }
      return;
    }

    if (row.parentRowId) {
      setBirdsEyeFocusedRow(row.parentRowId, cause);
      return;
    }

    if (row.hasChildren && (expandedRowIds[row.rowId] ?? false)) {
      toggleRowExpansion(row.rowId, false);
    }
  };

  const folderNodeForQuickCreateRow = (row: BirdsEyeVisibleRow | null) => {
    if (!row) {
      return null;
    }

    if (row.node.kind === "folder") {
      return row.node;
    }

    if (row.node.kind === "chat") {
      const folderNode = treeModel.rowById.get(row.node.folderRowId);
      return folderNode?.kind === "folder" ? folderNode : null;
    }

    return (
      row.node.folders.find((folder) => folder.folderType === "repo_root") ??
      row.node.folders[0] ??
      null
    );
  };

  const ensureQuickCreateFolderExpanded = (
    folder: BirdsEyeFolderNode | null,
  ) => {
    if (!folder) {
      return;
    }

    setExpandedRowIds((current) => ({
      ...current,
      [`project:${folder.projectId}`]: true,
      [folder.rowId]: true,
    }));
  };

  const quickCreateContextForRow = (row: BirdsEyeVisibleRow | null) => {
    const folder = folderNodeForQuickCreateRow(row);
    if (!folder) {
      return null;
    }

    const sourceDefaults =
      row?.node.kind === "chat"
        ? row.node.createDefaults
        : row?.node.kind === "folder"
          ? row.node.createDefaults
          : row?.node.kind === "project"
            ? folder.createDefaults
            : null;

    return {
      draft: {
        ...defaultQuickCreateState.draft,
        ...folder.createDefaults,
        ...sourceDefaults,
        command:
          sourceDefaults?.command ??
          folder.createDefaults.command ??
          defaultQuickCreateState.draft.command,
        model:
          sourceDefaults?.model ??
          folder.createDefaults.model ??
          defaultQuickCreateState.draft.model,
        thinkingEffort:
          sourceDefaults?.thinkingEffort ??
          folder.createDefaults.thinkingEffort ??
          defaultQuickCreateState.draft.thinkingEffort,
        planMode:
          sourceDefaults?.planMode ??
          folder.createDefaults.planMode ??
          defaultQuickCreateState.draft.planMode,
        enableChrome:
          sourceDefaults?.enableChrome ??
          folder.createDefaults.enableChrome ??
          defaultQuickCreateState.draft.enableChrome,
        skipPermissions:
          sourceDefaults?.skipPermissions ??
          folder.createDefaults.skipPermissions ??
          defaultQuickCreateState.draft.skipPermissions,
        priority:
          sourceDefaults?.priority ??
          folder.createDefaults.priority ??
          defaultQuickCreateState.draft.priority,
        projectId:
          sourceDefaults?.projectId ??
          folder.projectId ??
          defaultQuickCreateState.draft.projectId,
        status:
          sourceDefaults?.status ??
          folder.createDefaults.status ??
          defaultQuickCreateState.draft.status,
        workspaceTargetMode:
          sourceDefaults?.workspaceTargetMode ??
          folder.createDefaults.workspaceTargetMode ??
          defaultQuickCreateState.draft.workspaceTargetMode,
        workspaceWorktreeBranch:
          sourceDefaults?.workspaceWorktreeBranch ??
          folder.createDefaults.workspaceWorktreeBranch ??
          defaultQuickCreateState.draft.workspaceWorktreeBranch,
        workspaceWorktreeName:
          sourceDefaults?.workspaceWorktreeName ??
          folder.createDefaults.workspaceWorktreeName ??
          defaultQuickCreateState.draft.workspaceWorktreeName,
        workspaceWorktreePath:
          sourceDefaults?.workspaceWorktreePath ??
          folder.createDefaults.workspaceWorktreePath ??
          defaultQuickCreateState.draft.workspaceWorktreePath,
      },
      folder,
      row,
    };
  };

  const openQuickCreate = (rowId?: string | null) => {
    const fallbackRow =
      (rowId ? visibleRowLookup.get(rowId) : null) ??
      focusedRow ??
      visibleRows[0] ??
      null;

    if (!fallbackRow) {
      onCreateProject();
      return;
    }

    const quickCreateContext = quickCreateContextForRow(fallbackRow);
    if (!quickCreateContext) {
      onCreateProject();
      return;
    }

    ensureQuickCreateFolderExpanded(quickCreateContext.folder);
    setQuickCreateState({
      draft: quickCreateContext.draft,
      errorMessage: null,
      folderRowId: quickCreateContext.folder.rowId,
      isOpen: true,
      isSaving: false,
      sourceRowId: fallbackRow.rowId,
      title: birdsEyeSuggestedTitle(fallbackRow.node),
    });
  };

  const closeQuickCreate = () => {
    setQuickCreateState(defaultQuickCreateState);
    setBirdsEyeFocusedRow(
      quickCreateState.sourceRowId ??
        quickCreateState.folderRowId ??
        focusedRow?.rowId ??
        null,
    );
  };

  const handleBirdsEyeCanvasPointerDown = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    if (event.button !== 0) {
      return;
    }

    const target = event.target as HTMLElement | null;
    if (
      target?.closest(
        "button, a, input, textarea, select, label, [role='menu'], [role='menuitem']",
      )
    ) {
      return;
    }

    canvasPanRef.current = {
      pointerId: event.pointerId,
      originX: birdsEyeCanvasOffset.x,
      originY: birdsEyeCanvasOffset.y,
      startX: event.clientX,
      startY: event.clientY,
    };
    event.preventDefault();
    window.getSelection()?.removeAllRanges();
    setIsBirdsEyeCanvasDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const handleBirdsEyeCanvasPointerMove = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    const panState = canvasPanRef.current;
    if (!panState || panState.pointerId !== event.pointerId) {
      return;
    }

    setBirdsEyeCanvasOffset({
      x: panState.originX + event.clientX - panState.startX,
      y: panState.originY + event.clientY - panState.startY,
    });
  };

  const handleBirdsEyeCanvasPointerEnd = (
    event: PointerEvent<HTMLDivElement>,
  ) => {
    if (canvasPanRef.current?.pointerId !== event.pointerId) {
      return;
    }

    canvasPanRef.current = null;
    setIsBirdsEyeCanvasDragging(false);
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const setBirdsEyeCanvasZoom = (
    nextZoomIndex: number | ((currentZoomIndex: number) => number),
    anchor?: DashboardCanvasOffset,
  ) => {
    const viewport = canvasViewportRef.current;
    if (!viewport) {
      setBirdsEyeCanvasZoomIndex((currentZoomIndex) =>
        clampNumber(
          typeof nextZoomIndex === "function"
            ? nextZoomIndex(currentZoomIndex)
            : nextZoomIndex,
          0,
          birdsEyeCanvasZoomLevels.length - 1,
        ),
      );
      return;
    }

    setBirdsEyeCanvasZoomIndex((currentZoomIndex) => {
      const safeZoomIndex = clampNumber(
        typeof nextZoomIndex === "function"
          ? nextZoomIndex(currentZoomIndex)
          : nextZoomIndex,
        0,
        birdsEyeCanvasZoomLevels.length - 1,
      );
      if (safeZoomIndex === currentZoomIndex) {
        return currentZoomIndex;
      }

      const currentZoomScale = birdsEyeCanvasZoomLevels[currentZoomIndex] ?? 1;
      const nextZoomScale = birdsEyeCanvasZoomLevels[safeZoomIndex] ?? 1;
      const anchorX = anchor?.x ?? viewport.clientWidth / 2;
      const anchorY = anchor?.y ?? viewport.clientHeight / 2;

      setBirdsEyeCanvasOffset((currentOffset) => {
        const worldX = (anchorX - currentOffset.x) / currentZoomScale;
        const worldY = (anchorY - currentOffset.y) / currentZoomScale;

        return {
          x: anchorX - worldX * nextZoomScale,
          y: anchorY - worldY * nextZoomScale,
        };
      });

      return safeZoomIndex;
    });
  };

  const nudgeBirdsEyeCanvasZoom = (
    delta: number,
    anchor?: DashboardCanvasOffset,
  ) => {
    if (delta === 0) {
      return;
    }

    setBirdsEyeCanvasZoom(
      (currentZoomIndex) => currentZoomIndex + delta,
      anchor,
    );
  };

  const handleBirdsEyeCanvasWheel = (event: WheelEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement | null;
    if (
      target?.closest(
        "input, textarea, select, .shadcn-select-content, [role='menu']",
      )
    ) {
      return;
    }

    event.preventDefault();
    const wheelZoomState = birdsEyeCanvasWheelZoomRef.current;
    const resetThresholdMs = 180;
    if (event.timeStamp - wheelZoomState.lastEventTime > resetThresholdMs) {
      wheelZoomState.accumulatedDeltaY = 0;
    }

    wheelZoomState.lastEventTime = event.timeStamp;
    wheelZoomState.accumulatedDeltaY += event.deltaY;

    const isTrackpadPinch = event.ctrlKey;
    const threshold = event.deltaMode === 1 ? 1 : isTrackpadPinch ? 6 : 16;
    if (Math.abs(wheelZoomState.accumulatedDeltaY) < threshold) {
      return;
    }

    const zoomDelta = wheelZoomState.accumulatedDeltaY < 0 ? 1 : -1;
    wheelZoomState.accumulatedDeltaY = 0;
    const viewportRect = event.currentTarget.getBoundingClientRect();

    nudgeBirdsEyeCanvasZoom(zoomDelta, {
      x: event.clientX - viewportRect.left,
      y: event.clientY - viewportRect.top,
    });
  };

  const handleOpenBirdsEyeCommandPalette = () => {
    setIsHelpMenuOpen(false);
    setIsCommandPaletteOpen(true);
    setCommandPaletteQuery("");
  };

  const handleResetBirdsEyeCanvas = () => {
    setIsHelpMenuOpen(false);
    setBirdsEyeCanvasOffset(defaultBirdsEyeCanvasOffset);
  };

  const commandActions = useMemo(() => {
    const actions: Array<{
      description: string;
      id: string;
      keywords: string;
      label: string;
      run: () => void;
    }> = [];
    const contextDescription = focusedRow
      ? describeBirdsEyeNodeContext(focusedRow.node)
      : "current context";

    actions.push({
      description: `Create a chat in ${contextDescription}.`,
      id: "new-chat",
      keywords: `new create chat ${contextDescription}`,
      label: "New chat",
      run: () => openQuickCreate(focusedRow?.rowId),
    });

    if (focusedRow?.hasChildren) {
      const isExpanded = expandedRowIds[focusedRow.rowId] ?? false;
      actions.push({
        description: isExpanded
          ? "Collapse the focused branch."
          : "Expand the focused branch.",
        id: "toggle-branch",
        keywords: `${isExpanded ? "collapse" : "expand"} folder project branch`,
        label: isExpanded ? "Collapse branch" : "Expand branch",
        run: () => toggleRowExpansion(focusedRow.rowId),
      });
    }

    if (focusedRow?.node.kind === "chat") {
      actions.push({
        description:
          previewIssue?.id === focusedRow.node.chat.id
            ? "Open the full conversation detail."
            : "Preview the focused chat.",
        id: "preview-chat",
        keywords: "preview inspect chat",
        label:
          previewIssue?.id === focusedRow.node.chat.id
            ? "Open chat detail"
            : "Preview chat",
        run: () => openRow(focusedRow),
      });
    }

    if (previewIssue) {
      actions.push({
        description: "Close the lightweight preview.",
        id: "close-preview",
        keywords: "close preview escape",
        label: "Close preview",
        run: onClosePreview,
      });
    }

    actions.push(
      {
        description: "Jump to the top of the list.",
        id: "jump-top",
        keywords: "top start first",
        label: "Jump to top",
        run: () => focusRowByIndex(0),
      },
      {
        description: "Jump to the latest visible chat.",
        id: "jump-recent",
        keywords: "recent latest bottom",
        label: "Jump to recent",
        run: () => {
          if (!recentChatRowId) {
            focusRowByIndex(visibleRows.length - 1);
            return;
          }

          if (recentChatRowId === focusedRow?.rowId) {
            focusRowByIndex(visibleRows.length - 1);
            return;
          }

          setBirdsEyeFocusedRow(recentChatRowId);
        },
      },
      {
        description: "Create a new project.",
        id: "new-project",
        keywords: "new project create",
        label: "New project",
        run: onCreateProject,
      },
    );

    return actions;
  }, [
    expandedRowIds,
    focusedRow,
    onClosePreview,
    onCreateProject,
    previewIssue,
    recentChatRowId,
    visibleRows.length,
  ]);
  const filteredCommandActions = useMemo(() => {
    const query = commandPaletteQuery.trim().toLowerCase();
    if (!query) {
      return commandActions;
    }

    return commandActions.filter((action) =>
      `${action.label} ${action.description} ${action.keywords}`
        .toLowerCase()
        .includes(query),
    );
  }, [commandActions, commandPaletteQuery]);

  useEffect(() => {
    setCommandPaletteIndex(0);
  }, [commandPaletteQuery, isCommandPaletteOpen]);

  useEffect(() => {
    if (!quickCreateState.isOpen) {
      return;
    }

    if (
      !quickCreateState.folderRowId ||
      treeModel.rowById.get(quickCreateState.folderRowId)?.kind !== "folder"
    ) {
      setQuickCreateState(defaultQuickCreateState);
    }
  }, [
    defaultQuickCreateState,
    quickCreateState.folderRowId,
    quickCreateState.isOpen,
    treeModel.rowById,
  ]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const isPrimaryModifier = event.metaKey || event.ctrlKey;

      if (isPrimaryModifier && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setIsCommandPaletteOpen(true);
        setCommandPaletteQuery("");
        return;
      }

      if (isCommandPaletteOpen) {
        if (event.key === "Escape") {
          event.preventDefault();
          setIsCommandPaletteOpen(false);
          setCommandPaletteScope(null);
          return;
        }

        if (event.key === "ArrowDown") {
          event.preventDefault();
          setCommandPaletteIndex((current) =>
            clampNumber(
              current + 1,
              0,
              Math.max(filteredCommandActions.length - 1, 0),
            ),
          );
          return;
        }

        if (event.key === "ArrowUp") {
          event.preventDefault();
          setCommandPaletteIndex((current) =>
            clampNumber(
              current - 1,
              0,
              Math.max(filteredCommandActions.length - 1, 0),
            ),
          );
          return;
        }

        if (event.key === "Enter") {
          const action = filteredCommandActions[commandPaletteIndex] ?? null;
          if (!action) {
            return;
          }
          event.preventDefault();
          setIsCommandPaletteOpen(false);
          action.run();
        }
        return;
      }

      if (quickCreateState.isOpen) {
        if (event.key === "Escape") {
          event.preventDefault();
          closeQuickCreate();
        }
        return;
      }

      if (isEditableEventTarget(event.target)) {
        return;
      }

      if (isPrimaryModifier && event.key === "ArrowUp") {
        event.preventDefault();
        focusRowByIndex(0, "keyboard");
        return;
      }

      if (isPrimaryModifier && event.key === "ArrowDown") {
        event.preventDefault();
        if (recentChatRowId && recentChatRowId !== focusedRow?.rowId) {
          setBirdsEyeFocusedRow(recentChatRowId, "keyboard");
          return;
        }
        focusRowByIndex(visibleRows.length - 1, "keyboard");
        return;
      }

      if (
        event.key.toLowerCase() === "n" &&
        !event.altKey &&
        !isPrimaryModifier
      ) {
        event.preventDefault();
        openQuickCreate();
        return;
      }

      switch (event.key) {
        case "ArrowDown":
          event.preventDefault();
          focusSiblingRow(focusedRow, "next", "keyboard");
          return;
        case "ArrowUp":
          event.preventDefault();
          focusSiblingRow(focusedRow, "previous", "keyboard");
          return;
        case "ArrowRight":
          event.preventDefault();
          openRow(focusedRow, "keyboard");
          return;
        case "ArrowLeft":
          event.preventDefault();
          closeRow(focusedRow, "keyboard");
          return;
        case "Enter":
          event.preventDefault();
          openRow(focusedRow, "keyboard");
          return;
        case "Escape":
          if (previewIssue) {
            event.preventDefault();
            onClosePreview();
          }
          return;
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [
    commandPaletteIndex,
    filteredCommandActions,
    focusedRow,
    focusedRowIndex,
    isCommandPaletteOpen,
    onClosePreview,
    previewIssue,
    quickCreateState.isOpen,
    recentChatRowId,
    visibleRows,
  ]);

  const handleQuickCreateSubmit = async (event: FormEvent) => {
    event.preventDefault();
    const folderNode =
      quickCreateState.folderRowId &&
      treeModel.rowById.get(quickCreateState.folderRowId)?.kind === "folder"
        ? (treeModel.rowById.get(
            quickCreateState.folderRowId,
          ) as BirdsEyeFolderNode)
        : null;

    if (!folderNode) {
      return;
    }

    setQuickCreateState((current) => ({
      ...current,
      errorMessage: null,
      isSaving: true,
    }));

    try {
      ensureQuickCreateFolderExpanded(folderNode);
      const createdIssue = await onCreateQuickChat(
        quickCreateState.title,
        quickCreateState.draft,
      );
      setPendingFocusRowId(`chat:${createdIssue.id}`);
      closeQuickCreate();
    } catch (error) {
      setQuickCreateState((current) => ({
        ...current,
        errorMessage: error instanceof Error ? error.message : String(error),
        isSaving: false,
      }));
    }
  };

  const renderBirdsEyeRowButton = (row: BirdsEyeVisibleRow) => (
    <BirdsEyeRow
      buttonRef={(element) => {
        rowRefs.current.set(row.rowId, element);
      }}
      codeImpact={
        row.node.kind === "chat" && row.node.sessionId
          ? (codeImpactBySessionId[row.node.sessionId] ?? null)
          : null
      }
      isFocused={row.rowId === focusedRow?.rowId}
      isPreviewing={
        row.node.kind === "chat" && previewIssue?.id === row.node.chat.id
      }
      onClick={() => {
        setBirdsEyeFocusedRow(row.rowId, "click");
      }}
      onDoubleClick={() => {
        if (row.node.kind === "chat") {
          onOpenIssueDetail(row.node.chat.id);
        }
      }}
      onToggleExpand={() => toggleRowExpansion(row.rowId)}
      row={row}
    />
  );

  const renderBirdsEyeFolderGroup = (folder: BirdsEyeFolderNode) => {
    const folderRow = visibleRowLookup.get(folder.rowId);
    if (!folderRow) {
      return null;
    }

    const isFolderExpanded = expandedRowIds[folder.rowId] ?? false;
    const isInlineDraftOpen =
      quickCreateState.isOpen && quickCreateState.folderRowId === folder.rowId;

    return (
      <section
        className="birds-eye-group birds-eye-folder-group"
        key={folder.rowId}
      >
        {renderBirdsEyeRowButton(folderRow)}
        {isFolderExpanded ? (
          <div
            className="birds-eye-group-body birds-eye-folder-group-body"
            role="group"
          >
            {isInlineDraftOpen ? (
              <BirdsEyeQuickCreateRow
                dependencyCheck={dependencyCheck}
                draft={quickCreateState.draft}
                errorMessage={quickCreateState.errorMessage}
                folder={folder}
                inputRef={(element) => {
                  quickCreateInputRef.current = element;
                }}
                isSaving={quickCreateState.isSaving}
                onCancel={closeQuickCreate}
                onDraftChange={(patch) =>
                  setQuickCreateState((current) => ({
                    ...current,
                    draft: {
                      ...current.draft,
                      ...patch,
                    },
                    errorMessage: null,
                  }))
                }
                onSubmit={handleQuickCreateSubmit}
                onTitleChange={(title) =>
                  setQuickCreateState((current) => ({
                    ...current,
                    errorMessage: null,
                    title,
                  }))
                }
                sourceNode={
                  quickCreateState.sourceRowId
                    ? (visibleRowLookup.get(quickCreateState.sourceRowId)
                        ?.node ??
                      treeModel.rowById.get(quickCreateState.sourceRowId) ??
                      null)
                    : null
                }
                title={quickCreateState.title}
              />
            ) : null}
            {folder.chats.map((chat) => {
              const chatRow = visibleRowLookup.get(chat.rowId);
              if (!chatRow) {
                return null;
              }

              return (
                <div className="birds-eye-chat-shell" key={chat.rowId}>
                  {renderBirdsEyeRowButton(chatRow)}
                </div>
              );
            })}
          </div>
        ) : null}
      </section>
    );
  };

  const renderBirdsEyeProjectGroup = (project: BirdsEyeProjectNode) => {
    const projectRow = visibleRowLookup.get(project.rowId);
    if (!projectRow) {
      return null;
    }

    const isProjectExpanded = expandedRowIds[project.rowId] ?? false;

    return (
      <section
        className="birds-eye-group birds-eye-project-group"
        key={project.rowId}
      >
        {renderBirdsEyeRowButton(projectRow)}
        {isProjectExpanded ? (
          <div
            className="birds-eye-group-body birds-eye-project-group-body"
            role="group"
          >
            {project.folders.map((folder) => renderBirdsEyeFolderGroup(folder))}
          </div>
        ) : null}
      </section>
    );
  };

  return (
    <section className="birds-eye-route">
      <div className="birds-eye-route-header">
        <div className="birds-eye-route-header-inner">
          <DashboardBreadcrumbs items={[{ label: "Dashboard" }]} />
          <div className="birds-eye-route-actions">
            <div className="birds-eye-help-shell">
              <button
                aria-expanded={isHelpMenuOpen}
                aria-haspopup="menu"
                className={
                  isHelpMenuOpen
                    ? "secondary-button compact-button birds-eye-help-button is-open"
                    : "secondary-button compact-button birds-eye-help-button"
                }
                onClick={() => setIsHelpMenuOpen((current) => !current)}
                ref={helpButtonRef}
                type="button"
              >
                <span>Help</span>
                <span aria-hidden="true" className="birds-eye-help-button-icon">
                  <ChevronUpDownIcon />
                </span>
              </button>
              {isHelpMenuOpen ? (
                <div
                  className="birds-eye-help-menu"
                  ref={helpMenuRef}
                  role="menu"
                >
                  <button
                    className="birds-eye-help-item"
                    onClick={handleOpenBirdsEyeCommandPalette}
                    role="menuitem"
                    type="button"
                  >
                    <strong>Keyboard shortcuts</strong>
                    <span>Open the command palette.</span>
                  </button>
                  <button
                    className="birds-eye-help-item"
                    onClick={handleResetBirdsEyeCanvas}
                    role="menuitem"
                    type="button"
                  >
                    <strong>Reset canvas position</strong>
                    <span>Return the overview to its default anchor.</span>
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </div>
      </div>
      {projects.length ? (
        <div className="birds-eye-layout">
          <div className="birds-eye-tree-panel">
            <div
              className={
                isBirdsEyeCanvasDragging
                  ? "birds-eye-canvas-viewport is-dragging"
                  : "birds-eye-canvas-viewport"
              }
              onPointerCancel={handleBirdsEyeCanvasPointerEnd}
              onPointerDown={handleBirdsEyeCanvasPointerDown}
              onPointerMove={handleBirdsEyeCanvasPointerMove}
              onPointerUp={handleBirdsEyeCanvasPointerEnd}
              onWheel={handleBirdsEyeCanvasWheel}
              ref={canvasViewportRef}
            >
              <div className="birds-eye-canvas-grid" />
              <div
                className="birds-eye-canvas-stage"
                style={{
                  transform: `translate(${birdsEyeCanvasOffset.x}px, ${birdsEyeCanvasOffset.y}px) scale(${birdsEyeCanvasZoomScale})`,
                }}
              >
                <div className="birds-eye-tree" role="tree">
                  {treeModel.projects.map((project) =>
                    renderBirdsEyeProjectGroup(project),
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : isLoadingOverview ? (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Loading overview
              </span>
              <h2>Fetching projects, folders, and chats</h2>
              <p>
                The Birds Eye dashboard loads a compact overview first, then
                fills in worktrees and previews only when you open them.
              </p>
            </div>
          </div>
        </div>
      ) : (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Projects required
              </span>
              <h2>Create a project first</h2>
              <p>
                This Birds Eye view groups chat activity by project and working
                folder. Add a project with a repository anchor to start routing
                chats into repo root and worktree contexts.
              </p>
            </div>
            <button
              className="primary-button"
              onClick={onCreateProject}
              type="button"
            >
              Create project
            </button>
          </div>
        </div>
      )}
      <div className="dashboard-canvas-route-footer">
        <div className="dashboard-canvas-route-footer-inner">
          <div
            aria-label="Birds eye zoom"
            className="dashboard-canvas-zoom-control"
            role="group"
          >
            <span className="dashboard-canvas-zoom-label">Zoom</span>
            <div className="dashboard-canvas-zoom-steps">
              {birdsEyeCanvasZoomLevels.map((zoomLevel, index) => (
                <button
                  aria-pressed={index === birdsEyeCanvasZoomIndex}
                  className={
                    index === birdsEyeCanvasZoomIndex
                      ? "dashboard-canvas-zoom-step is-active"
                      : "dashboard-canvas-zoom-step"
                  }
                  key={zoomLevel}
                  onClick={() => setBirdsEyeCanvasZoom(index)}
                  type="button"
                >
                  {dashboardCanvasZoomLabel(zoomLevel)}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      <BirdsEyeCommandPalette
        actions={filteredCommandActions}
        activeIndex={commandPaletteIndex}
        inputRef={commandPaletteInputRef}
        isOpen={isCommandPaletteOpen}
        onClose={() => setIsCommandPaletteOpen(false)}
        onQueryChange={setCommandPaletteQuery}
        query={commandPaletteQuery}
      />
    </section>
  );
}

function GridDashboardBirdsEyeRouteView({
  agents,
  chats,
  dependencyCheck,
  isLoadingOverview,
  onCreateProject,
  onCreateQuickChat,
  onOpenIssueDetail,
  projects,
  renderIssueTile,
  selectedIssueTileId,
  workspaces,
}: {
  agents: AgentRecord[];
  chats: DashboardOverviewChatRecord[];
  dependencyCheck: RuntimeCapabilities | null;
  isLoadingOverview: boolean;
  onCreateProject: () => void;
  onCreateQuickChat: (
    title: string,
    defaults: CreateIssueDialogDefaults,
  ) => Promise<IssueRecord>;
  onOpenIssueDetail: (issueId: string) => void;
  projects: ProjectRecord[];
  renderIssueTile: (issueId: string, onClose: () => void) => ReactNode;
  selectedIssueTileId: string | null;
  workspaces: WorkspaceRecord[];
}) {
  const projectWorktreesByProjectId = useDashboardProjectWorktrees(
    projects,
    projects.map((project) => project.id),
  );
  const treeModel = useMemo(
    () =>
      buildBirdsEyeTree({
        agents,
        chats,
        dependencyCheck,
        projectWorktreesByProjectId,
        projects,
        workspaces,
      }),
    [
      agents,
      chats,
      dependencyCheck,
      projectWorktreesByProjectId,
      projects,
      workspaces,
    ],
  );

  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [commandPaletteIndex, setCommandPaletteIndex] = useState(0);
  const commandPaletteInputRef = useRef<HTMLInputElement | null>(null);

  const allChats = useMemo(() => {
    return treeModel.projects.flatMap((project) =>
      project.folders.flatMap((folder) =>
        folder.chats.map((chat) => ({
          chat,
          folder,
          projectId: project.project.id,
          projectLabel: project.label,
        })),
      ),
    );
  }, [treeModel.projects]);

  const commandActions = useMemo(() => {
    const query = commandPaletteQuery.trim().toLowerCase();
    return allChats
      .filter((entry) =>
        query
          ? `${entry.chat.title} ${entry.folder.label} ${entry.projectLabel}`
              .toLowerCase()
              .includes(query)
          : true,
      )
      .map((entry) => ({
        description: `${entry.projectLabel} · ${entry.folder.label}`,
        id: `chat:${entry.chat.chat.id}`,
        keywords: `${entry.chat.title} ${entry.folder.label}`,
        label: entry.chat.title,
        run: () => {
          onOpenIssueDetail(entry.chat.chat.id);
          setIsCommandPaletteOpen(false);
        },
      }));
  }, [allChats, commandPaletteQuery, onOpenIssueDetail]);

  useEffect(() => {
    setCommandPaletteIndex(0);
  }, [commandPaletteQuery, isCommandPaletteOpen]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    const frameId = window.requestAnimationFrame(() => {
      commandPaletteInputRef.current?.focus();
    });
    return () => {
      window.cancelAnimationFrame(frameId);
    };
  }, [isCommandPaletteOpen]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const isPrimaryModifier = event.metaKey || event.ctrlKey;

      if (isPrimaryModifier && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setIsCommandPaletteOpen(true);
        setCommandPaletteQuery("");
        return;
      }

      if (isCommandPaletteOpen) {
        if (event.key === "Escape") {
          event.preventDefault();
          setIsCommandPaletteOpen(false);
          return;
        }
        if (event.key === "ArrowDown") {
          event.preventDefault();
          setCommandPaletteIndex((current) =>
            Math.min(current + 1, Math.max(commandActions.length - 1, 0)),
          );
          return;
        }
        if (event.key === "ArrowUp") {
          event.preventDefault();
          setCommandPaletteIndex((current) => Math.max(current - 1, 0));
          return;
        }
        if (event.key === "Enter") {
          event.preventDefault();
          const action = commandActions[commandPaletteIndex] ?? null;
          if (action) {
            setIsCommandPaletteOpen(false);
            action.run();
          }
        }
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isCommandPaletteOpen, commandActions, commandPaletteIndex]);

  return (
    <section className="birds-eye-route">
      <div className="birds-eye-route-header">
        <div className="birds-eye-route-header-inner">
          <DashboardBreadcrumbs items={[{ label: "Dashboard" }]} />
          <div className="birds-eye-route-actions">
            <button
              className="secondary-button compact-button"
              onClick={() => {
                setIsCommandPaletteOpen(true);
                setCommandPaletteQuery("");
              }}
              type="button"
            >
              Search chats
            </button>
            <button
              className="secondary-button compact-button"
              onClick={onCreateProject}
              type="button"
            >
              Add project
            </button>
          </div>
        </div>
      </div>

      {projects.length ? (
        <div
          className={
            selectedIssueTileId
              ? "birds-eye-grid-split has-detail"
              : "birds-eye-grid-split"
          }
        >
          <div className="birds-eye-grid-panel">
            <div className="birds-eye-repo-grid">
              {treeModel.projects.map((project) => (
                <div className="birds-eye-repo-column" key={project.project.id}>
                  <div className="birds-eye-repo-column-header">
                    <strong>{project.label}</strong>
                    <span>
                      {project.folderCount} worktrees · {project.chatCount}{" "}
                      chats
                    </span>
                  </div>
                  <div className="birds-eye-repo-column-body">
                    {project.folders.map((folder) => (
                      <div
                        className="birds-eye-folder-section"
                        key={folder.folderKey}
                      >
                        <div className="birds-eye-folder-section-header">
                          <strong>{folder.label}</strong>
                          <span>
                            {folder.secondaryLabel ??
                              formatCompactIssueTimestamp(
                                folder.lastActivityAt,
                              )}
                          </span>
                        </div>
                        <div className="birds-eye-chat-list">
                          {folder.chats.length > 0 ? (
                            folder.chats.map((chat) => (
                              <button
                                className={
                                  selectedIssueTileId === chat.chat.id
                                    ? "birds-eye-chat-list-item is-selected"
                                    : "birds-eye-chat-list-item"
                                }
                                key={chat.chat.id}
                                onClick={() => onOpenIssueDetail(chat.chat.id)}
                                type="button"
                              >
                                <div className="birds-eye-chat-list-item-main">
                                  <strong>{chat.title}</strong>
                                  <span>
                                    {issueStatusLabel(chat.chat.status)}
                                  </span>
                                </div>
                                <div className="birds-eye-chat-list-item-meta">
                                  <span>
                                    {chat.runSummary ||
                                      chat.agentLabel ||
                                      "No recent action"}
                                  </span>
                                  {chat.chat.identifier ? (
                                    <span>{chat.chat.identifier}</span>
                                  ) : null}
                                </div>
                              </button>
                            ))
                          ) : (
                            <div className="birds-eye-chat-list-empty">
                              <span>No chats in this worktree</span>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {selectedIssueTileId ? (
            <div className="birds-eye-detail-pane">
              {renderIssueTile(selectedIssueTileId, () => {
                /* close handled by parent */
              })}
            </div>
          ) : null}
        </div>
      ) : isLoadingOverview ? (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Loading overview
              </span>
              <h2>Loading dashboard</h2>
              <p>Repos, worktrees, and chats are loading.</p>
            </div>
          </div>
        </div>
      ) : (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Projects required
              </span>
              <h2>Create a project first</h2>
              <p>
                Add a project with a repository anchor before opening worktrees
                and chats.
              </p>
            </div>
            <button
              className="primary-button"
              onClick={onCreateProject}
              type="button"
            >
              Create project
            </button>
          </div>
        </div>
      )}

      {isCommandPaletteOpen ? (
        <BirdsEyeCommandPalette
          actions={commandActions}
          activeIndex={commandPaletteIndex}
          inputRef={commandPaletteInputRef}
          isOpen={isCommandPaletteOpen}
          onClose={() => setIsCommandPaletteOpen(false)}
          onQueryChange={setCommandPaletteQuery}
          query={commandPaletteQuery}
        />
      ) : null}
    </section>
  );
}

function SpatialDashboardBirdsEyeRouteView({
  agents,
  canvasState,
  chats,
  dependencyCheck,
  isLoadingOverview,
  onCanvasStateChange,
  onCreateProject,
  onCreateQuickChat,
  onOpenIssueDetail,
  projects,
  renderIssueTile,
  selectedIssueTileId,
  workspaces,
}: {
  agents: AgentRecord[];
  canvasState: BirdsEyeCanvasCompanyState | null;
  chats: DashboardOverviewChatRecord[];
  dependencyCheck: RuntimeCapabilities | null;
  isLoadingOverview: boolean;
  onCanvasStateChange: (nextState: BirdsEyeCanvasState) => void | Promise<void>;
  onCreateProject: () => void;
  onCreateQuickChat: (
    title: string,
    defaults: CreateIssueDialogDefaults,
  ) => Promise<IssueRecord>;
  onOpenIssueDetail: (issueId: string) => void;
  projects: ProjectRecord[];
  renderIssueTile: (issueId: string, onClose: () => void) => ReactNode;
  selectedIssueTileId: string | null;
  workspaces: WorkspaceRecord[];
}) {
  const projectWorktreesByProjectId = useDashboardProjectWorktrees(
    projects,
    projects.map((project) => project.id),
  );
  const treeModel = useMemo(
    () =>
      buildBirdsEyeTree({
        agents,
        chats,
        dependencyCheck,
        projectWorktreesByProjectId,
        projects,
        workspaces,
      }),
    [
      agents,
      chats,
      dependencyCheck,
      projectWorktreesByProjectId,
      projects,
      workspaces,
    ],
  );
  const incomingCanvasStateKey = useMemo(
    () => JSON.stringify(canvasState ?? null),
    [canvasState],
  );
  const [localCanvasState, setLocalCanvasState] = useState<BirdsEyeCanvasState>(
    () => parseBirdsEyeCanvasState(canvasState),
  );
  const [isHelpMenuOpen, setIsHelpMenuOpen] = useState(false);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [commandPaletteMode, setCommandPaletteMode] = useState<
    "default" | "open-chat" | "run-command"
  >("default");
  const [commandPaletteScope, setCommandPaletteScope] = useState<{
    projectId: string | null;
    worktreeKey: string | null;
  } | null>(null);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [commandPaletteIndex, setCommandPaletteIndex] = useState(0);
  const [contextMenu, setContextMenu] = useState<{
    projectId: string | null;
    worktreeKey: string | null;
    x: number;
    y: number;
  } | null>(null);
  const [worktreePanelFocus, setWorktreePanelFocus] = useState<
    Record<string, "sidebar" | "tiles">
  >({});
  const [quickCreateState, setQuickCreateState] = useState<null | {
    draft: BirdsEyeQuickCreateDraft;
    errorMessage: string | null;
    isSaving: boolean;
    projectId: string;
    title: string;
    worktreeKey: string;
    x: number;
    y: number;
  }>(null);
  const [recentlyOpenedTileKey, setRecentlyOpenedTileKey] = useState<
    string | null
  >(null);
  const [measuredWorktreeHeights, setMeasuredWorktreeHeights] = useState<
    Record<string, number>
  >({});
  const [isViewportDragging, setIsViewportDragging] = useState(false);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const worktreeBoardObserversRef = useRef<Map<string, ResizeObserver>>(
    new Map(),
  );
  const repoDragRef = useRef<{
    originX: number;
    originY: number;
    pointerId: number;
    projectId: string;
    startX: number;
    startY: number;
  } | null>(null);
  const panRef = useRef<{
    originX: number;
    originY: number;
    pointerId: number;
    startX: number;
    startY: number;
  } | null>(null);
  const wheelZoomRef = useRef({
    accumulatedDeltaY: 0,
    lastEventTime: 0,
  });
  const isSpacePressedRef = useRef(false);
  const focusKeyRef = useRef<string | null>(null);
  const helpButtonRef = useRef<HTMLButtonElement | null>(null);
  const helpMenuRef = useRef<HTMLDivElement | null>(null);
  const quickCreateInputRef = useRef<HTMLInputElement | null>(null);
  const commandPaletteInputRef = useRef<HTMLInputElement | null>(null);
  const canvasModel = useMemo(
    () =>
      buildBirdsEyeCanvasModel(
        treeModel,
        localCanvasState,
        measuredWorktreeHeights,
      ),
    [localCanvasState, measuredWorktreeHeights, treeModel],
  );
  const normalizedCanvasStateKey = useMemo(
    () =>
      JSON.stringify(serializeBirdsEyeCanvasState(canvasModel.normalizedState)),
    [canvasModel.normalizedState],
  );
  const localCanvasStateKey = useMemo(
    () => JSON.stringify(serializeBirdsEyeCanvasState(localCanvasState)),
    [localCanvasState],
  );
  const effectiveCanvasState = canvasModel.normalizedState;
  const canvasZoomScale =
    birdsEyeCanvasZoomLevels[effectiveCanvasState.viewport.zoomIndex] ?? 1;
  const defaultQuickCreateDraft = useMemo(
    () => createBirdsEyeQuickCreateState(dependencyCheck).draft,
    [dependencyCheck],
  );
  const repoRegions = canvasModel.repoRegions;
  const folderByKey = useMemo(() => {
    const next = new Map<string, BirdsEyeFolderNode>();
    for (const project of treeModel.projects) {
      for (const folder of project.folders) {
        next.set(folder.folderKey, folder);
      }
    }
    return next;
  }, [treeModel.projects]);
  const projectById = useMemo(
    () =>
      new Map(
        treeModel.projects.map((project) => [project.project.id, project]),
      ),
    [treeModel.projects],
  );
  const worktreeOptions = useMemo(
    () =>
      treeModel.projects.flatMap((project) =>
        project.folders.map((folder) => ({
          folder,
          label: `${project.label} · ${folder.label}`,
          projectId: project.project.id,
          worktreeKey: folder.folderKey,
        })),
      ),
    [treeModel.projects],
  );
  const focusedTarget = effectiveCanvasState.focusedTarget;
  const focusedProject =
    (focusedTarget
      ? (projectById.get(focusedTarget.projectId) ?? null)
      : (treeModel.projects[0] ?? null)) ?? null;
  const focusedWorktree = focusedTarget?.worktreeKey
    ? (folderByKey.get(focusedTarget.worktreeKey) ?? null)
    : null;
  const focusedWorktreeTileState = focusedWorktree
    ? (effectiveCanvasState.worktreeTiles[focusedWorktree.folderKey] ??
      createEmptyBirdsEyeWorktreeTileState())
    : null;

  const setWorktreePanel = (
    worktreeKey: string | null | undefined,
    panel: "sidebar" | "tiles",
  ) => {
    if (!worktreeKey) {
      return;
    }
    setWorktreePanelFocus((current) =>
      current[worktreeKey] === panel
        ? current
        : {
            ...current,
            [worktreeKey]: panel,
          },
    );
  };

  useEffect(() => {
    setLocalCanvasState(parseBirdsEyeCanvasState(canvasState));
  }, [incomingCanvasStateKey]);

  useEffect(() => {
    if (normalizedCanvasStateKey === localCanvasStateKey) {
      return;
    }
    setLocalCanvasState(canvasModel.normalizedState);
  }, [
    canvasModel.normalizedState,
    localCanvasStateKey,
    normalizedCanvasStateKey,
  ]);

  useEffect(() => {
    if (normalizedCanvasStateKey === incomingCanvasStateKey) {
      return;
    }
    const timeoutId = window.setTimeout(() => {
      void onCanvasStateChange(effectiveCanvasState);
    }, 180);
    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [
    effectiveCanvasState,
    incomingCanvasStateKey,
    normalizedCanvasStateKey,
    onCanvasStateChange,
  ]);

  useEffect(() => {
    if (!quickCreateState) {
      return;
    }
    const frameId = window.requestAnimationFrame(() => {
      quickCreateInputRef.current?.focus();
      quickCreateInputRef.current?.select();
    });
    return () => {
      window.cancelAnimationFrame(frameId);
    };
  }, [quickCreateState?.worktreeKey]);

  useEffect(() => {
    return () => {
      for (const observer of worktreeBoardObserversRef.current.values()) {
        observer.disconnect();
      }
      worktreeBoardObserversRef.current.clear();
    };
  }, []);

  useEffect(() => {
    const validWorktreeKeys = new Set(
      treeModel.projects.flatMap((project) =>
        project.folders.map((folder) => folder.folderKey),
      ),
    );

    setMeasuredWorktreeHeights((current) => {
      let hasChanges = false;
      const nextEntries = Object.entries(current).filter(([worktreeKey]) => {
        const keep = validWorktreeKeys.has(worktreeKey);
        if (!keep) {
          hasChanges = true;
          const observer = worktreeBoardObserversRef.current.get(worktreeKey);
          observer?.disconnect();
          worktreeBoardObserversRef.current.delete(worktreeKey);
        }
        return keep;
      });

      if (!hasChanges) {
        return current;
      }

      return Object.fromEntries(nextEntries);
    });
  }, [treeModel.projects]);

  useEffect(() => {
    if (!recentlyOpenedTileKey) {
      return;
    }
    const timeoutId = window.setTimeout(() => {
      setRecentlyOpenedTileKey((current) =>
        current === recentlyOpenedTileKey ? null : current,
      );
    }, 240);
    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [recentlyOpenedTileKey]);

  useEffect(() => {
    if (!isCommandPaletteOpen) {
      return;
    }
    const frameId = window.requestAnimationFrame(() => {
      commandPaletteInputRef.current?.focus();
      commandPaletteInputRef.current?.select();
    });
    return () => {
      window.cancelAnimationFrame(frameId);
    };
  }, [isCommandPaletteOpen]);

  useEffect(() => {
    if (!isHelpMenuOpen) {
      return;
    }

    const closeMenu = (event?: Event) => {
      const target = event?.target as Node | null | undefined;
      if (
        target &&
        (helpButtonRef.current?.contains(target) ||
          helpMenuRef.current?.contains(target))
      ) {
        return;
      }
      setIsHelpMenuOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsHelpMenuOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isHelpMenuOpen]);

  useEffect(() => {
    if (!contextMenu) {
      return;
    }

    const closeMenu = () => setContextMenu(null);
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setContextMenu(null);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    document.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      document.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [contextMenu]);

  const updateCanvasState = (
    updater: (current: BirdsEyeCanvasState) => BirdsEyeCanvasState,
  ) => {
    setLocalCanvasState((current) => updater(current));
  };

  const registerWorktreeBoard =
    (worktreeKey: string) => (element: HTMLElement | null) => {
      const existingObserver =
        worktreeBoardObserversRef.current.get(worktreeKey);
      if (existingObserver) {
        existingObserver.disconnect();
        worktreeBoardObserversRef.current.delete(worktreeKey);
      }

      if (!element) {
        return;
      }

      const syncHeight = (height: number) => {
        const nextHeight = Math.ceil(height);
        if (nextHeight <= 0) {
          return;
        }
        setMeasuredWorktreeHeights((current) =>
          current[worktreeKey] === nextHeight
            ? current
            : {
                ...current,
                [worktreeKey]: nextHeight,
              },
        );
      };

      syncHeight(element.offsetHeight);

      const observer = new ResizeObserver((entries) => {
        const entry = entries[0];
        if (!entry) {
          return;
        }
        syncHeight((entry.target as HTMLElement).offsetHeight);
      });
      observer.observe(element);
      worktreeBoardObserversRef.current.set(worktreeKey, observer);
    };

  const setFocusedTarget = (
    nextTarget: BirdsEyeCanvasFocusTarget | null,
    cause: BirdsEyeFocusChangeCause = "programmatic",
  ) => {
    if (nextTarget?.worktreeKey) {
      setWorktreePanel(
        nextTarget.worktreeKey,
        nextTarget.kind === "tile" ? "tiles" : "sidebar",
      );
    }
    setLocalCanvasState((current) => {
      const previousKey = birdsEyeFocusTargetKey(current.focusedTarget);
      const nextKey = birdsEyeFocusTargetKey(nextTarget);
      if (previousKey === nextKey) {
        return current;
      }
      focusKeyRef.current = nextKey;
      if (shouldPlayBirdsEyeFocusSound(previousKey, nextKey, cause)) {
        playBirdsEyeFocusSound();
      }
      return {
        ...current,
        focusedTarget: nextTarget,
      };
    });
  };

  const setRepoPage = (projectId: string, page: number) => {
    updateCanvasState((current) => ({
      ...current,
      repoRegions: {
        ...current.repoRegions,
        [projectId]: {
          ...(current.repoRegions[projectId] ??
            defaultBirdsEyeRepoRegionState(
              treeModel.projects.findIndex(
                (project) => project.project.id === projectId,
              ),
            )),
          page,
        },
      },
    }));
  };

  const fitCanvasToViewport = () => {
    const viewport = viewportRef.current;
    if (!viewport) {
      return;
    }

    const padding = 88;
    const fitScale = Math.min(
      (viewport.clientWidth - padding * 2) / canvasModel.bounds.width,
      (viewport.clientHeight - padding * 2) / canvasModel.bounds.height,
    );
    const nextZoomIndex = birdsEyeCanvasZoomLevels.reduce(
      (bestIndex, zoomLevel, index) =>
        zoomLevel <= fitScale ? index : bestIndex,
      0,
    );

    updateCanvasState((current) => ({
      ...current,
      viewport: {
        x: padding,
        y: padding,
        zoomIndex: nextZoomIndex,
      },
    }));
  };

  const resetCanvasViewport = () => {
    updateCanvasState((current) => ({
      ...current,
      viewport: {
        x: defaultBirdsEyeCanvasOffset.x,
        y: defaultBirdsEyeCanvasOffset.y,
        zoomIndex: defaultBirdsEyeCanvasZoomIndex,
      },
    }));
  };

  const revealRepoRegionInViewport = (projectId: string) => {
    const viewport = viewportRef.current;
    const region = repoRegions.find(
      (candidate) => candidate.project.project.id === projectId,
    );
    if (!(viewport && region)) {
      return;
    }

    const padding = 56;

    updateCanvasState((current) => {
      const zoomScale =
        birdsEyeCanvasZoomLevels[current.viewport.zoomIndex] ?? 1;
      const visibleLeft = padding;
      const visibleTop = padding;
      const visibleRight = viewport.clientWidth - padding;
      const visibleBottom = viewport.clientHeight - padding;
      const regionLeft = current.viewport.x + region.x * zoomScale;
      const regionTop = current.viewport.y + region.y * zoomScale;
      const regionRight = regionLeft + region.width * zoomScale;
      const regionBottom = regionTop + region.height * zoomScale;

      let nextX = current.viewport.x;
      let nextY = current.viewport.y;

      if (regionLeft < visibleLeft) {
        nextX += visibleLeft - regionLeft;
      } else if (regionRight > visibleRight) {
        nextX -= regionRight - visibleRight;
      }

      if (regionTop < visibleTop) {
        nextY += visibleTop - regionTop;
      } else if (regionBottom > visibleBottom) {
        nextY -= regionBottom - visibleBottom;
      }

      if (nextX === current.viewport.x && nextY === current.viewport.y) {
        return current;
      }

      return {
        ...current,
        viewport: {
          ...current.viewport,
          x: nextX,
          y: nextY,
        },
      };
    });
  };

  const nudgeCanvasZoom = (delta: number, anchor?: DashboardCanvasOffset) => {
    const viewport = viewportRef.current;
    if (!viewport || delta === 0) {
      return;
    }

    updateCanvasState((current) => {
      const nextZoomIndex = clampNumber(
        current.viewport.zoomIndex + delta,
        0,
        birdsEyeCanvasZoomLevels.length - 1,
      );
      if (nextZoomIndex === current.viewport.zoomIndex) {
        return current;
      }

      const currentZoomScale =
        birdsEyeCanvasZoomLevels[current.viewport.zoomIndex] ?? 1;
      const nextZoomScale = birdsEyeCanvasZoomLevels[nextZoomIndex] ?? 1;
      const anchorX = anchor?.x ?? viewport.clientWidth / 2;
      const anchorY = anchor?.y ?? viewport.clientHeight / 2;
      const worldX = (anchorX - current.viewport.x) / currentZoomScale;
      const worldY = (anchorY - current.viewport.y) / currentZoomScale;

      return {
        ...current,
        viewport: {
          x: anchorX - worldX * nextZoomScale,
          y: anchorY - worldY * nextZoomScale,
          zoomIndex: nextZoomIndex,
        },
      };
    });
  };

  const openIssueTile = (
    projectId: string,
    worktreeKey: string,
    issueId: string,
    focusTile = true,
  ) => {
    const isAlreadyOpen =
      effectiveCanvasState.worktreeTiles[worktreeKey]?.issueIds.includes(
        issueId,
      ) ?? false;
    if (!isAlreadyOpen) {
      setRecentlyOpenedTileKey(`${worktreeKey}:${issueId}`);
    }
    setWorktreePanel(worktreeKey, focusTile ? "tiles" : "sidebar");
    updateCanvasState((current) => {
      const existingState =
        current.worktreeTiles[worktreeKey] ??
        createEmptyBirdsEyeWorktreeTileState();
      let nextIssueIds = existingState.issueIds.filter(Boolean);
      let nextLruIds = existingState.lruIssueIds.filter((entry) =>
        nextIssueIds.includes(entry),
      );

      if (!nextIssueIds.includes(issueId)) {
        if (nextIssueIds.length >= 4) {
          const evictedIssueId =
            nextLruIds.find((entry) => nextIssueIds.includes(entry)) ??
            nextIssueIds[0];
          nextIssueIds = nextIssueIds.filter(
            (entry) => entry !== evictedIssueId,
          );
          nextLruIds = nextLruIds.filter((entry) => entry !== evictedIssueId);
        }
        nextIssueIds = nextIssueIds.concat(issueId);
      }

      nextLruIds = nextLruIds
        .filter((entry) => entry !== issueId)
        .concat(issueId);

      return {
        ...current,
        focusedTarget: focusTile
          ? {
              kind: "tile",
              issueId,
              projectId,
              worktreeKey,
            }
          : {
              kind: "chat",
              issueId,
              projectId,
              worktreeKey,
            },
        worktreeTiles: {
          ...current.worktreeTiles,
          [worktreeKey]: {
            activeIssueId: issueId,
            issueIds: nextIssueIds,
            lruIssueIds: nextLruIds,
          },
        },
      };
    });
    onOpenIssueDetail(issueId);
  };

  const closeIssueTile = (
    projectId: string,
    worktreeKey: string,
    issueId: string,
  ) => {
    updateCanvasState((current) => {
      const existingState =
        current.worktreeTiles[worktreeKey] ??
        createEmptyBirdsEyeWorktreeTileState();
      const nextIssueIds = existingState.issueIds.filter(
        (entry) => entry !== issueId,
      );
      const nextLruIds = existingState.lruIssueIds.filter(
        (entry) => entry !== issueId,
      );
      const nextActiveIssueId =
        existingState.activeIssueId === issueId
          ? (nextIssueIds[0] ?? null)
          : existingState.activeIssueId;

      return {
        ...current,
        focusedTarget:
          current.focusedTarget?.kind === "tile" &&
          current.focusedTarget.issueId === issueId &&
          current.focusedTarget.worktreeKey === worktreeKey
            ? nextActiveIssueId
              ? {
                  kind: "tile",
                  issueId: nextActiveIssueId,
                  projectId,
                  worktreeKey,
                }
              : {
                  kind: "worktree",
                  issueId: null,
                  projectId,
                  worktreeKey,
                }
            : current.focusedTarget,
        worktreeTiles: {
          ...current.worktreeTiles,
          [worktreeKey]: {
            activeIssueId: nextActiveIssueId,
            issueIds: nextIssueIds,
            lruIssueIds: nextLruIds,
          },
        },
      };
    });
    setWorktreePanel(worktreeKey, nextActiveIssueId ? "tiles" : "sidebar");
  };

  const activateTile = (
    projectId: string,
    worktreeKey: string,
    issueId: string,
  ) => {
    setWorktreePanel(worktreeKey, "tiles");
    updateCanvasState((current) => {
      const existingState =
        current.worktreeTiles[worktreeKey] ??
        createEmptyBirdsEyeWorktreeTileState();
      const nextIssueIds = existingState.issueIds.includes(issueId)
        ? existingState.issueIds
        : existingState.issueIds.concat(issueId).slice(0, 4);
      const nextLruIds = existingState.lruIssueIds
        .filter((entry) => entry !== issueId)
        .concat(issueId);

      return {
        ...current,
        focusedTarget: {
          kind: "tile",
          issueId,
          projectId,
          worktreeKey,
        },
        worktreeTiles: {
          ...current.worktreeTiles,
          [worktreeKey]: {
            activeIssueId: issueId,
            issueIds: nextIssueIds,
            lruIssueIds: nextLruIds,
          },
        },
      };
    });
    onOpenIssueDetail(issueId);
  };

  const moveFocusedTile = (direction: "left" | "right" | "up" | "down") => {
    if (
      !focusedTarget ||
      focusedTarget.kind !== "tile" ||
      !focusedTarget.worktreeKey
    ) {
      return;
    }

    const tileState =
      effectiveCanvasState.worktreeTiles[focusedTarget.worktreeKey];
    if (!tileState) {
      return;
    }

    const currentIndex = tileState.issueIds.findIndex(
      (issueId) => issueId === focusedTarget.issueId,
    );
    if (currentIndex < 0) {
      return;
    }

    let nextIndex = currentIndex;
    if (direction === "left" && currentIndex % 2 === 1) {
      nextIndex = currentIndex - 1;
    }
    if (
      direction === "right" &&
      currentIndex % 2 === 0 &&
      currentIndex + 1 < tileState.issueIds.length
    ) {
      nextIndex = currentIndex + 1;
    }
    if (direction === "up" && currentIndex - 2 >= 0) {
      nextIndex = currentIndex - 2;
    }
    if (direction === "down" && currentIndex + 2 < tileState.issueIds.length) {
      nextIndex = currentIndex + 2;
    }

    if (nextIndex === currentIndex) {
      return;
    }

    updateCanvasState((current) => {
      const nextState = current.worktreeTiles[focusedTarget.worktreeKey ?? ""];
      if (!nextState) {
        return current;
      }
      const nextIssueIds = nextState.issueIds.slice();
      [nextIssueIds[currentIndex], nextIssueIds[nextIndex]] = [
        nextIssueIds[nextIndex],
        nextIssueIds[currentIndex],
      ];
      return {
        ...current,
        worktreeTiles: {
          ...current.worktreeTiles,
          [focusedTarget.worktreeKey ?? ""]: {
            ...nextState,
            issueIds: nextIssueIds,
          },
        },
      };
    });
  };

  const focusRepoSibling = (direction: "previous" | "next") => {
    const repoIds = repoRegions.map((region) => region.project.project.id);
    if (repoIds.length === 0) {
      return;
    }
    const currentProjectId = focusedTarget?.projectId ?? repoIds[0];
    const currentIndex = Math.max(repoIds.indexOf(currentProjectId), 0);
    const nextIndex =
      direction === "next"
        ? (currentIndex + 1) % repoIds.length
        : (currentIndex - 1 + repoIds.length) % repoIds.length;
    const nextProjectId = repoIds[nextIndex] ?? repoIds[0];
    setFocusedTarget(
      {
        kind: "repo",
        issueId: null,
        projectId: nextProjectId,
        worktreeKey: null,
      },
      "keyboard",
    );
    revealRepoRegionInViewport(nextProjectId);
  };

  const focusWorktreeSibling = (direction: "previous" | "next") => {
    if (!focusedProject) {
      return;
    }
    const worktreeKeys = focusedProject.folders.map(
      (folder) => folder.folderKey,
    );
    if (worktreeKeys.length === 0) {
      return;
    }
    const currentKey =
      focusedTarget?.worktreeKey ??
      focusedProject.folders[0]?.folderKey ??
      null;
    const currentIndex = Math.max(worktreeKeys.indexOf(currentKey ?? ""), 0);
    const nextIndex =
      direction === "next"
        ? (currentIndex + 1) % worktreeKeys.length
        : (currentIndex - 1 + worktreeKeys.length) % worktreeKeys.length;
    const nextWorktreeKey = worktreeKeys[nextIndex] ?? worktreeKeys[0];
    const nextPage = Math.floor(nextIndex / birdsEyeWorktreePageSize);
    setRepoPage(focusedProject.project.id, nextPage);
    setFocusedTarget(
      {
        kind: "worktree",
        issueId: null,
        projectId: focusedProject.project.id,
        worktreeKey: nextWorktreeKey,
      },
      "keyboard",
    );
  };

  const focusChatSibling = (direction: "previous" | "next") => {
    if (!focusedWorktree) {
      return;
    }
    const chatsInWorktree = focusedWorktree.chats;
    if (chatsInWorktree.length === 0) {
      return;
    }
    const currentIssueId =
      focusedTarget?.issueId ?? chatsInWorktree[0]?.chat.id ?? null;
    const currentIndex = Math.max(
      chatsInWorktree.findIndex((chat) => chat.chat.id === currentIssueId),
      0,
    );
    const nextIndex =
      direction === "next"
        ? (currentIndex + 1) % chatsInWorktree.length
        : (currentIndex - 1 + chatsInWorktree.length) % chatsInWorktree.length;
    const nextChat = chatsInWorktree[nextIndex] ?? chatsInWorktree[0];
    setFocusedTarget(
      {
        kind: "chat",
        issueId: nextChat.chat.id,
        projectId: focusedWorktree.projectId,
        worktreeKey: focusedWorktree.folderKey,
      },
      "keyboard",
    );
  };

  const cycleTileFocus = (direction: "previous" | "next") => {
    if (!focusedWorktree) {
      return;
    }
    const tileState =
      effectiveCanvasState.worktreeTiles[focusedWorktree.folderKey] ??
      createEmptyBirdsEyeWorktreeTileState();
    if (tileState.issueIds.length === 0) {
      return;
    }
    const currentIssueId =
      focusedTarget?.kind === "tile" &&
      focusedTarget.worktreeKey === focusedWorktree.folderKey
        ? focusedTarget.issueId
        : (tileState.activeIssueId ?? tileState.issueIds[0]);
    const currentIndex = Math.max(
      tileState.issueIds.findIndex((issueId) => issueId === currentIssueId),
      0,
    );
    const nextIndex =
      direction === "next"
        ? (currentIndex + 1) % tileState.issueIds.length
        : (currentIndex - 1 + tileState.issueIds.length) %
          tileState.issueIds.length;
    const nextIssueId = tileState.issueIds[nextIndex] ?? tileState.issueIds[0];
    activateTile(
      focusedWorktree.projectId,
      focusedWorktree.folderKey,
      nextIssueId,
    );
  };

  const openFocusedQuickCreate = (
    anchor?: { x: number; y: number },
    preferredProjectId?: string | null,
    preferredWorktreeKey?: string | null,
  ) => {
    const fallbackFolder =
      (preferredWorktreeKey ? folderByKey.get(preferredWorktreeKey) : null) ??
      (focusedTarget?.worktreeKey
        ? (folderByKey.get(focusedTarget.worktreeKey) ?? null)
        : null) ??
      (preferredProjectId
        ? (projectById.get(preferredProjectId)?.folders[0] ?? null)
        : null) ??
      focusedProject?.folders[0] ??
      treeModel.projects[0]?.folders[0] ??
      null;

    if (!fallbackFolder) {
      onCreateProject();
      return;
    }

    const viewportRect = viewportRef.current?.getBoundingClientRect();
    const targetX = anchor?.x ?? (viewportRect ? viewportRect.left + 120 : 120);
    const targetY = anchor?.y ?? (viewportRect ? viewportRect.top + 120 : 120);

    setQuickCreateState({
      draft: {
        ...defaultQuickCreateDraft,
        ...fallbackFolder.createDefaults,
        command:
          fallbackFolder.createDefaults.command ??
          defaultQuickCreateDraft.command,
        model:
          fallbackFolder.createDefaults.model ?? defaultQuickCreateDraft.model,
        projectId:
          fallbackFolder.projectId ??
          fallbackFolder.createDefaults.projectId ??
          "",
      },
      errorMessage: null,
      isSaving: false,
      projectId: fallbackFolder.projectId,
      title: birdsEyeSuggestedTitle(fallbackFolder),
      worktreeKey: fallbackFolder.folderKey,
      x: targetX,
      y: targetY,
    });
    setContextMenu(null);
  };

  const openChatPalette = (
    mode: "open-chat" | "run-command" | "default",
    scope: {
      projectId: string | null;
      worktreeKey: string | null;
    } | null = null,
  ) => {
    setContextMenu(null);
    setIsCommandPaletteOpen(true);
    setCommandPaletteMode(mode);
    setCommandPaletteQuery("");
    setCommandPaletteIndex(0);
    setCommandPaletteScope(scope);
  };

  const commandActions = useMemo(() => {
    const actions: Array<{
      description: string;
      id: string;
      keywords: string;
      label: string;
      run: () => void;
    }> = [];
    const scopedWorktree = commandPaletteScope?.worktreeKey
      ? (folderByKey.get(commandPaletteScope.worktreeKey) ?? null)
      : null;
    const scopedProject = commandPaletteScope?.projectId
      ? (projectById.get(commandPaletteScope.projectId) ?? null)
      : null;

    if (commandPaletteMode === "open-chat") {
      const candidateFolders = scopedWorktree
        ? [scopedWorktree]
        : focusedWorktree
          ? [focusedWorktree]
          : (scopedProject?.folders ??
            focusedProject?.folders ??
            treeModel.projects.flatMap((project) => project.folders));

      for (const folder of candidateFolders) {
        for (const chat of folder.chats) {
          actions.push({
            description: `${folder.label} · ${issueStatusLabel(chat.chat.status)}`,
            id: `chat:${chat.chat.id}`,
            keywords: `${chat.title} ${folder.label} ${chat.agentLabel}`,
            label: chat.title,
            run: () => {
              openIssueTile(
                chat.projectId,
                folder.folderKey,
                chat.chat.id,
                true,
              );
              setIsCommandPaletteOpen(false);
            },
          });
        }
      }

      return actions;
    }

    actions.push(
      {
        description: "Create a new chat in the focused worktree.",
        id: "new-chat",
        keywords: "new chat create worktree",
        label: "New chat",
        run: () =>
          openFocusedQuickCreate(
            undefined,
            commandPaletteScope?.projectId ?? null,
            commandPaletteScope?.worktreeKey ?? null,
          ),
      },
      {
        description: "Open an existing chat from the current context.",
        id: "open-chat",
        keywords: "open existing chat quick open",
        label: "Open existing chat",
        run: () => openChatPalette("open-chat", commandPaletteScope),
      },
      {
        description: "Create a new project region on the canvas.",
        id: "new-project",
        keywords: "new project region",
        label: "New project",
        run: onCreateProject,
      },
      {
        description: "Fit all repo regions into the viewport.",
        id: "fit-canvas",
        keywords: "fit canvas zoom reset",
        label: "Fit canvas",
        run: fitCanvasToViewport,
      },
      {
        description: "Reset the viewport to the default origin.",
        id: "reset-canvas",
        keywords: "reset viewport origin",
        label: "Reset canvas position",
        run: resetCanvasViewport,
      },
    );

    return actions;
  }, [
    commandPaletteScope,
    commandPaletteMode,
    defaultQuickCreateDraft,
    folderByKey,
    focusedProject,
    focusedWorktree,
    onCreateProject,
    projectById,
    treeModel.projects,
  ]);

  const filteredCommandActions = useMemo(() => {
    const query = commandPaletteQuery.trim().toLowerCase();
    if (!query) {
      return commandActions;
    }

    return commandActions.filter((action) =>
      `${action.label} ${action.description} ${action.keywords}`
        .toLowerCase()
        .includes(query),
    );
  }, [commandActions, commandPaletteQuery]);

  useEffect(() => {
    setCommandPaletteIndex(0);
  }, [commandPaletteMode, commandPaletteQuery, isCommandPaletteOpen]);

  const openContextMenu = (
    event: MouseEvent<HTMLElement>,
    projectId: string | null,
    worktreeKey: string | null,
  ) => {
    event.preventDefault();
    setContextMenu({
      projectId,
      worktreeKey,
      x: event.clientX,
      y: event.clientY,
    });
  };

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const isPrimaryModifier = event.metaKey || event.ctrlKey;

      if (event.code === "Space" && !isEditableEventTarget(event.target)) {
        isSpacePressedRef.current = true;
      }

      if (isPrimaryModifier && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setIsCommandPaletteOpen(true);
        setCommandPaletteMode("default");
        setCommandPaletteQuery("");
        setCommandPaletteScope(null);
        return;
      }

      if (isPrimaryModifier && event.key.toLowerCase() === "p") {
        event.preventDefault();
        setIsCommandPaletteOpen(true);
        setCommandPaletteMode("open-chat");
        setCommandPaletteQuery("");
        setCommandPaletteScope(
          focusedWorktree
            ? {
                projectId: focusedWorktree.projectId,
                worktreeKey: focusedWorktree.folderKey,
              }
            : null,
        );
        return;
      }

      if (isCommandPaletteOpen) {
        if (event.key === "Escape") {
          event.preventDefault();
          setIsCommandPaletteOpen(false);
          return;
        }
        if (event.key === "ArrowDown") {
          event.preventDefault();
          setCommandPaletteIndex((current) =>
            clampNumber(
              current + 1,
              0,
              Math.max(filteredCommandActions.length - 1, 0),
            ),
          );
          return;
        }
        if (event.key === "ArrowUp") {
          event.preventDefault();
          setCommandPaletteIndex((current) =>
            clampNumber(
              current - 1,
              0,
              Math.max(filteredCommandActions.length - 1, 0),
            ),
          );
          return;
        }
        if (event.key === "Enter") {
          event.preventDefault();
          const action = filteredCommandActions[commandPaletteIndex] ?? null;
          if (action) {
            setIsCommandPaletteOpen(false);
            setCommandPaletteScope(null);
            action.run();
          }
        }
        return;
      }

      if (quickCreateState) {
        if (event.key === "Escape") {
          event.preventDefault();
          setQuickCreateState(null);
        }
        return;
      }

      if (isEditableEventTarget(event.target)) {
        return;
      }

      const isArrowNavigationKey = [
        "ArrowUp",
        "ArrowDown",
        "ArrowLeft",
        "ArrowRight",
      ].includes(event.key);

      if (!focusedTarget && repoRegions.length > 0 && isArrowNavigationKey) {
        event.preventDefault();
        setFocusedTarget(
          {
            kind: "repo",
            issueId: null,
            projectId: repoRegions[0]?.project.project.id ?? "",
            worktreeKey: null,
          },
          "keyboard",
        );
        return;
      }

      if (!isPrimaryModifier && event.key.toLowerCase() === "n") {
        event.preventDefault();
        openFocusedQuickCreate();
        return;
      }

      if (event.key === "+" || event.key === "=") {
        event.preventDefault();
        nudgeCanvasZoom(1);
        return;
      }

      if (event.key === "-") {
        event.preventDefault();
        nudgeCanvasZoom(-1);
        return;
      }

      if (isPrimaryModifier && event.key === "0") {
        event.preventDefault();
        fitCanvasToViewport();
        return;
      }

      if (isPrimaryModifier && !event.shiftKey && !event.altKey) {
        if (
          event.key === "1" &&
          focusedTarget?.kind !== "tile" &&
          !focusedWorktree
        ) {
          event.preventDefault();
          updateCanvasState((current) => ({
            ...current,
            viewport: { ...current.viewport, zoomIndex: 0 },
          }));
          return;
        }
        if (
          event.key === "2" &&
          focusedTarget?.kind !== "tile" &&
          !focusedWorktree
        ) {
          event.preventDefault();
          updateCanvasState((current) => ({
            ...current,
            viewport: { ...current.viewport, zoomIndex: 2 },
          }));
          return;
        }
        if (
          event.key === "3" &&
          focusedTarget?.kind !== "tile" &&
          !focusedWorktree
        ) {
          event.preventDefault();
          updateCanvasState((current) => ({
            ...current,
            viewport: { ...current.viewport, zoomIndex: 4 },
          }));
          return;
        }
      }

      if (isPrimaryModifier && (event.key === "." || event.key === ",")) {
        event.preventDefault();
        focusWorktreeSibling(event.key === "." ? "next" : "previous");
        return;
      }

      if (event.ctrlKey && event.key === "Tab") {
        event.preventDefault();
        focusChatSibling(event.shiftKey ? "previous" : "next");
        return;
      }

      if (isPrimaryModifier && event.key === "`") {
        event.preventDefault();
        cycleTileFocus("next");
        return;
      }

      if (
        isPrimaryModifier &&
        (event.key === "ArrowUp" || event.key === "ArrowDown") &&
        focusedWorktree
      ) {
        event.preventDefault();

        if (event.key === "ArrowDown") {
          if (
            focusedTarget?.kind === "chat" &&
            focusedTarget.issueId &&
            focusedTarget.worktreeKey
          ) {
            openIssueTile(
              focusedTarget.projectId,
              focusedTarget.worktreeKey,
              focusedTarget.issueId,
              true,
            );
            return;
          }

          const activeTileIssueId =
            focusedWorktreeTileState?.activeIssueId ??
            focusedWorktreeTileState?.issueIds[0] ??
            null;
          if (activeTileIssueId) {
            activateTile(
              focusedWorktree.projectId,
              focusedWorktree.folderKey,
              activeTileIssueId,
            );
          }
          return;
        }

        const sidebarIssueId =
          focusedTarget?.kind === "tile"
            ? focusedTarget.issueId
            : focusedTarget?.kind === "chat"
              ? focusedTarget.issueId
              : (focusedWorktree.chats[0]?.chat.id ?? null);

        if (sidebarIssueId) {
          setFocusedTarget(
            {
              kind: "chat",
              issueId: sidebarIssueId,
              projectId: focusedWorktree.projectId,
              worktreeKey: focusedWorktree.folderKey,
            },
            "keyboard",
          );
        } else {
          setFocusedTarget(
            {
              kind: "worktree",
              issueId: null,
              projectId: focusedWorktree.projectId,
              worktreeKey: focusedWorktree.folderKey,
            },
            "keyboard",
          );
        }
        return;
      }

      if (
        isPrimaryModifier &&
        focusedWorktree &&
        focusedTarget?.kind === "tile"
      ) {
        if (["1", "2", "3", "4"].includes(event.key)) {
          const tileState =
            effectiveCanvasState.worktreeTiles[focusedWorktree.folderKey] ??
            createEmptyBirdsEyeWorktreeTileState();
          const issueId = tileState.issueIds[Number(event.key) - 1] ?? null;
          if (issueId) {
            event.preventDefault();
            activateTile(
              focusedWorktree.projectId,
              focusedWorktree.folderKey,
              issueId,
            );
          }
          return;
        }

        if (event.key.toLowerCase() === "w") {
          event.preventDefault();
          if (focusedTarget.issueId) {
            closeIssueTile(
              focusedWorktree.projectId,
              focusedWorktree.folderKey,
              focusedTarget.issueId,
            );
          }
          return;
        }

        if (
          event.altKey &&
          ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
            event.key,
          )
        ) {
          event.preventDefault();
          moveFocusedTile(
            event.key === "ArrowLeft"
              ? "left"
              : event.key === "ArrowRight"
                ? "right"
                : event.key === "ArrowUp"
                  ? "up"
                  : "down",
          );
          return;
        }
      }

      if (
        !isPrimaryModifier &&
        (event.key === "ArrowUp" || event.key === "ArrowDown")
      ) {
        if (focusedTarget?.kind === "chat") {
          event.preventDefault();
          focusChatSibling(event.key === "ArrowDown" ? "next" : "previous");
          return;
        }

        if (focusedTarget?.kind === "worktree") {
          const nextChat =
            event.key === "ArrowDown"
              ? (focusedWorktree?.chats[0] ?? null)
              : (focusedWorktree?.chats.at(-1) ?? null);
          if (nextChat) {
            event.preventDefault();
            setFocusedTarget(
              {
                kind: "chat",
                issueId: nextChat.chat.id,
                projectId: nextChat.projectId,
                worktreeKey: focusedWorktree?.folderKey ?? null,
              },
              "keyboard",
            );
          }
        }
      }

      if (
        isPrimaryModifier &&
        ["ArrowLeft", "ArrowRight"].includes(event.key)
      ) {
        event.preventDefault();

        if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
          const direction = event.key === "ArrowRight" ? "next" : "previous";
          if (!focusedTarget || focusedTarget.kind === "repo") {
            focusRepoSibling(direction);
            return;
          }
          if (focusedTarget.kind === "worktree") {
            focusWorktreeSibling(direction);
            return;
          }
          if (focusedTarget.kind === "chat") {
            focusChatSibling(direction);
            return;
          }
          cycleTileFocus(direction);
          return;
        }
      }

      if (
        event.key === "Enter" &&
        focusedTarget?.kind === "chat" &&
        focusedTarget.issueId &&
        focusedTarget.worktreeKey
      ) {
        event.preventDefault();
        openIssueTile(
          focusedTarget.projectId,
          focusedTarget.worktreeKey,
          focusedTarget.issueId,
          Boolean(isPrimaryModifier),
        );
        return;
      }

      if (
        event.key === "Escape" &&
        focusedTarget?.kind === "tile" &&
        focusedTarget.issueId &&
        focusedTarget.worktreeKey
      ) {
        event.preventDefault();
        closeIssueTile(
          focusedTarget.projectId,
          focusedTarget.worktreeKey,
          focusedTarget.issueId,
        );
      }
    };

    const handleKeyUp = (event: KeyboardEvent) => {
      if (event.code === "Space") {
        isSpacePressedRef.current = false;
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("keyup", handleKeyUp);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("keyup", handleKeyUp);
    };
  }, [
    canvasModel.bounds.height,
    canvasModel.bounds.width,
    commandPaletteIndex,
    effectiveCanvasState.worktreeTiles,
    filteredCommandActions,
    focusedProject,
    focusedTarget,
    focusedWorktree,
    onCreateProject,
    onOpenIssueDetail,
    quickCreateState,
    repoRegions,
    selectedIssueTileId,
  ]);

  const handleViewportPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || !isSpacePressedRef.current) {
      return;
    }

    panRef.current = {
      originX: effectiveCanvasState.viewport.x,
      originY: effectiveCanvasState.viewport.y,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
    };
    setIsViewportDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
  };

  const handleViewportPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    if (panRef.current?.pointerId === event.pointerId) {
      updateCanvasState((current) => ({
        ...current,
        viewport: {
          ...current.viewport,
          x: panRef.current!.originX + event.clientX - panRef.current!.startX,
          y: panRef.current!.originY + event.clientY - panRef.current!.startY,
        },
      }));
      return;
    }

    if (repoDragRef.current?.pointerId === event.pointerId) {
      updateCanvasState((current) => ({
        ...current,
        repoRegions: {
          ...current.repoRegions,
          [repoDragRef.current!.projectId]: {
            ...(current.repoRegions[repoDragRef.current!.projectId] ??
              defaultBirdsEyeRepoRegionState(0)),
            x:
              repoDragRef.current!.originX +
              event.clientX -
              repoDragRef.current!.startX,
            y:
              repoDragRef.current!.originY +
              event.clientY -
              repoDragRef.current!.startY,
          },
        },
      }));
    }
  };

  const handleViewportPointerEnd = (event: PointerEvent<HTMLDivElement>) => {
    if (panRef.current?.pointerId === event.pointerId) {
      panRef.current = null;
      setIsViewportDragging(false);
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId);
      }
    }

    if (repoDragRef.current?.pointerId === event.pointerId) {
      repoDragRef.current = null;
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId);
      }
    }
  };

  const handleViewportWheel = (event: WheelEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement | null;
    if (
      target?.closest(
        "input, textarea, select, button, [role='menu'], .shadcn-select-content",
      )
    ) {
      return;
    }

    event.preventDefault();
    const isZoomModifierPressed = event.metaKey || event.ctrlKey;
    if (!isZoomModifierPressed) {
      wheelZoomRef.current.accumulatedDeltaY = 0;
      const deltaMultiplier =
        event.deltaMode === 1
          ? 20
          : event.deltaMode === 2
            ? event.currentTarget.clientHeight
            : 1;
      updateCanvasState((current) => ({
        ...current,
        viewport: {
          ...current.viewport,
          x: current.viewport.x - event.deltaX * deltaMultiplier,
          y: current.viewport.y - event.deltaY * deltaMultiplier,
        },
      }));
      return;
    }

    const wheelZoomState = wheelZoomRef.current;
    if (event.timeStamp - wheelZoomState.lastEventTime > 180) {
      wheelZoomState.accumulatedDeltaY = 0;
    }

    wheelZoomState.lastEventTime = event.timeStamp;
    wheelZoomState.accumulatedDeltaY += event.deltaY;

    const threshold = event.deltaMode === 1 ? 1 : event.ctrlKey ? 6 : 18;
    if (Math.abs(wheelZoomState.accumulatedDeltaY) < threshold) {
      return;
    }

    const zoomDelta = wheelZoomState.accumulatedDeltaY < 0 ? 1 : -1;
    wheelZoomState.accumulatedDeltaY = 0;
    const viewportRect = event.currentTarget.getBoundingClientRect();
    nudgeCanvasZoom(zoomDelta, {
      x: event.clientX - viewportRect.left,
      y: event.clientY - viewportRect.top,
    });
  };

  const handleQuickCreateSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (!quickCreateState) {
      return;
    }

    const folder = folderByKey.get(quickCreateState.worktreeKey) ?? null;
    if (!folder) {
      return;
    }

    setQuickCreateState((current) =>
      current
        ? {
            ...current,
            errorMessage: null,
            isSaving: true,
          }
        : current,
    );

    try {
      const createdIssue = await onCreateQuickChat(quickCreateState.title, {
        ...quickCreateState.draft,
        projectId: quickCreateState.projectId,
      });
      setQuickCreateState(null);
      openIssueTile(folder.projectId, folder.folderKey, createdIssue.id, true);
    } catch (error) {
      setQuickCreateState((current) =>
        current
          ? {
              ...current,
              errorMessage:
                error instanceof Error ? error.message : String(error),
              isSaving: false,
            }
          : current,
      );
    }
  };

  return (
    <section className="birds-eye-route birds-eye-route-spatial">
      <div className="birds-eye-route-header">
        <div className="birds-eye-route-header-inner">
          <DashboardBreadcrumbs items={[{ label: "Dashboard" }]} />
          <div className="birds-eye-route-actions">
            <button
              className="secondary-button compact-button"
              onClick={onCreateProject}
              type="button"
            >
              Add project
            </button>
            <div className="birds-eye-help-shell">
              <button
                aria-expanded={isHelpMenuOpen}
                aria-haspopup="menu"
                className={
                  isHelpMenuOpen
                    ? "secondary-button compact-button birds-eye-help-button is-open"
                    : "secondary-button compact-button birds-eye-help-button"
                }
                onClick={() => setIsHelpMenuOpen((current) => !current)}
                ref={helpButtonRef}
                type="button"
              >
                <span>Help</span>
                <span aria-hidden="true" className="birds-eye-help-button-icon">
                  <ChevronUpDownIcon />
                </span>
              </button>
              {isHelpMenuOpen ? (
                <div
                  className="birds-eye-help-menu"
                  ref={helpMenuRef}
                  role="menu"
                >
                  <button
                    className="birds-eye-help-item"
                    onClick={() => {
                      setIsHelpMenuOpen(false);
                      setIsCommandPaletteOpen(true);
                      setCommandPaletteMode("default");
                      setCommandPaletteQuery("");
                      setCommandPaletteScope(null);
                    }}
                    role="menuitem"
                    type="button"
                  >
                    <strong>Keyboard shortcuts</strong>
                    <span>
                      Open the command palette for the spatial canvas.
                    </span>
                  </button>
                  <button
                    className="birds-eye-help-item"
                    onClick={fitCanvasToViewport}
                    role="menuitem"
                    type="button"
                  >
                    <strong>Fit canvas</strong>
                    <span>Frame all repo regions inside the viewport.</span>
                  </button>
                  <button
                    className="birds-eye-help-item"
                    onClick={resetCanvasViewport}
                    role="menuitem"
                    type="button"
                  >
                    <strong>Reset viewport</strong>
                    <span>Return to the default origin and zoom.</span>
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </div>
      </div>

      {projects.length ? (
        <div className="birds-eye-layout birds-eye-layout-spatial">
          <div className="birds-eye-tree-panel birds-eye-tree-panel-spatial">
            <div
              className={
                isViewportDragging
                  ? "birds-eye-canvas-viewport is-dragging"
                  : "birds-eye-canvas-viewport"
              }
              onPointerCancel={handleViewportPointerEnd}
              onPointerDown={handleViewportPointerDown}
              onPointerMove={handleViewportPointerMove}
              onPointerUp={handleViewportPointerEnd}
              onWheel={handleViewportWheel}
              ref={viewportRef}
            >
              <div className="birds-eye-canvas-grid" />
              <div
                className="birds-eye-canvas-stage birds-eye-canvas-stage-spatial"
                style={{
                  transform: `translate(${effectiveCanvasState.viewport.x}px, ${effectiveCanvasState.viewport.y}px) scale(${canvasZoomScale})`,
                }}
              >
                <div className="birds-eye-spatial-plane" role="tree">
                  {repoRegions.map((region) => {
                    const isFocusedRepo =
                      focusedTarget?.kind === "repo" &&
                      focusedTarget.projectId === region.project.project.id;

                    return (
                      <section
                        className={
                          isFocusedRepo
                            ? "birds-eye-repo-region is-focused"
                            : "birds-eye-repo-region"
                        }
                        key={region.project.project.id}
                        style={{
                          left: region.x,
                          top: region.y,
                          width: region.width,
                          height: region.height,
                        }}
                      >
                        <div
                          className="birds-eye-repo-region-header"
                          onClick={() =>
                            setFocusedTarget(
                              {
                                kind: "repo",
                                issueId: null,
                                projectId: region.project.project.id,
                                worktreeKey: null,
                              },
                              "click",
                            )
                          }
                          onPointerDown={(event) => {
                            if (
                              event.button !== 0 ||
                              isSpacePressedRef.current
                            ) {
                              return;
                            }
                            repoDragRef.current = {
                              originX:
                                effectiveCanvasState.repoRegions[
                                  region.project.project.id
                                ]?.x ?? region.x,
                              originY:
                                effectiveCanvasState.repoRegions[
                                  region.project.project.id
                                ]?.y ?? region.y,
                              pointerId: event.pointerId,
                              projectId: region.project.project.id,
                              startX: event.clientX,
                              startY: event.clientY,
                            };
                            event.currentTarget.setPointerCapture(
                              event.pointerId,
                            );
                            event.stopPropagation();
                          }}
                          role="presentation"
                        >
                          <div>
                            <strong>{region.project.label}</strong>
                            <span>
                              {region.project.folderCount} worktrees ·{" "}
                              {region.project.chatCount} chats
                            </span>
                          </div>
                          {region.totalPages > 1 ? (
                            <div className="birds-eye-repo-region-pagination">
                              <button
                                className="secondary-button compact-button"
                                onClick={() =>
                                  setRepoPage(
                                    region.project.project.id,
                                    clampNumber(
                                      region.page - 1,
                                      0,
                                      region.totalPages - 1,
                                    ),
                                  )
                                }
                                type="button"
                              >
                                ◂
                              </button>
                              <span>
                                {region.page + 1}/{region.totalPages}
                              </span>
                              <button
                                className="secondary-button compact-button"
                                onClick={() =>
                                  setRepoPage(
                                    region.project.project.id,
                                    clampNumber(
                                      region.page + 1,
                                      0,
                                      region.totalPages - 1,
                                    ),
                                  )
                                }
                                type="button"
                              >
                                ▸
                              </button>
                            </div>
                          ) : null}
                        </div>

                        <div className="birds-eye-repo-worktree-grid">
                          {region.visibleWorktrees.map((board) => {
                            const isFocusedWorktree =
                              focusedTarget?.kind === "worktree" &&
                              focusedTarget.projectId ===
                                board.folder.projectId &&
                              focusedTarget.worktreeKey ===
                                board.folder.folderKey;
                            const activePanel =
                              worktreePanelFocus[board.folder.folderKey] ??
                              (focusedTarget?.kind === "tile" &&
                              focusedTarget.worktreeKey ===
                                board.folder.folderKey
                                ? "tiles"
                                : "sidebar");

                            return (
                              <section
                                className={
                                  isFocusedWorktree
                                    ? "birds-eye-worktree-board is-focused"
                                    : "birds-eye-worktree-board"
                                }
                                key={board.key}
                                onClick={() =>
                                  setFocusedTarget(
                                    {
                                      kind: "worktree",
                                      issueId: null,
                                      projectId: board.folder.projectId,
                                      worktreeKey: board.folder.folderKey,
                                    },
                                    "click",
                                  )
                                }
                                ref={registerWorktreeBoard(
                                  board.folder.folderKey,
                                )}
                                style={{
                                  left: board.x,
                                  minHeight: board.height,
                                  top: board.y,
                                  width: board.width,
                                }}
                              >
                                <div className="birds-eye-worktree-board-header">
                                  <div>
                                    <strong>{board.folder.label}</strong>
                                    <span>
                                      {board.folder.secondaryLabel ??
                                        formatCompactIssueTimestamp(
                                          board.folder.lastActivityAt,
                                        )}
                                    </span>
                                  </div>
                                </div>

                                <div className="birds-eye-worktree-body">
                                  <aside
                                    className={
                                      activePanel === "sidebar"
                                        ? "birds-eye-worktree-sidebar is-focused-panel"
                                        : "birds-eye-worktree-sidebar"
                                    }
                                    onClick={(event) => event.stopPropagation()}
                                    onContextMenu={(event) =>
                                      event.stopPropagation()
                                    }
                                  >
                                    <div className="birds-eye-worktree-sidebar-scroll">
                                      {board.chats.length > 0 ? (
                                        board.chats.map((chat) => {
                                          const isFocusedChat =
                                            focusedTarget?.kind === "chat" &&
                                            focusedTarget.issueId ===
                                              chat.chat.id &&
                                            focusedTarget.worktreeKey ===
                                              board.folder.folderKey;
                                          const isOpen =
                                            board.tileState.issueIds.includes(
                                              chat.chat.id,
                                            );
                                          const isActiveTile =
                                            board.tileState.activeIssueId ===
                                            chat.chat.id;

                                          return (
                                            <SpatialBirdsEyeSidebarChatRow
                                              chat={chat}
                                              isActiveTile={isActiveTile}
                                              isFocused={isFocusedChat}
                                              isOpen={isOpen}
                                              key={chat.chat.id}
                                              onClick={() => {
                                                if (isOpen) {
                                                  activateTile(
                                                    board.folder.projectId,
                                                    board.folder.folderKey,
                                                    chat.chat.id,
                                                  );
                                                  return;
                                                }

                                                openIssueTile(
                                                  board.folder.projectId,
                                                  board.folder.folderKey,
                                                  chat.chat.id,
                                                  true,
                                                );
                                              }}
                                            />
                                          );
                                        })
                                      ) : (
                                        <div className="birds-eye-worktree-sidebar-empty">
                                          <strong>No chats yet</strong>
                                          <span>
                                            Create the first chat from the
                                            canvas.
                                          </span>
                                        </div>
                                      )}
                                    </div>
                                  </aside>

                                  <div
                                    className={
                                      activePanel === "tiles"
                                        ? "birds-eye-worktree-execution-surface is-focused-panel"
                                        : "birds-eye-worktree-execution-surface"
                                    }
                                    onClick={(event) => {
                                      event.stopPropagation();
                                      if (board.tileState.activeIssueId) {
                                        activateTile(
                                          board.folder.projectId,
                                          board.folder.folderKey,
                                          board.tileState.activeIssueId,
                                        );
                                        return;
                                      }
                                      setFocusedTarget(
                                        {
                                          kind: "worktree",
                                          issueId: null,
                                          projectId: board.folder.projectId,
                                          worktreeKey: board.folder.folderKey,
                                        },
                                        "click",
                                      );
                                      setWorktreePanel(
                                        board.folder.folderKey,
                                        "tiles",
                                      );
                                    }}
                                  >
                                    {board.tileState.issueIds.length > 0 ? (
                                      <div
                                        className={`birds-eye-worktree-tile-grid tile-count-${board.tileState.issueIds.length}`}
                                      >
                                        {board.tileState.issueIds.map(
                                          (issueId) => {
                                            const tileChat =
                                              board.folder.chats.find(
                                                (chat) =>
                                                  chat.chat.id === issueId,
                                              ) ?? null;
                                            if (!tileChat) {
                                              return null;
                                            }

                                            const isTileFocused =
                                              focusedTarget?.kind === "tile" &&
                                              focusedTarget.issueId ===
                                                issueId &&
                                              focusedTarget.worktreeKey ===
                                                board.folder.folderKey;
                                            const isActiveFullTile =
                                              selectedIssueTileId === issueId &&
                                              board.tileState.activeIssueId ===
                                                issueId;

                                            return (
                                              <div
                                                className={
                                                  recentlyOpenedTileKey ===
                                                  `${board.folder.folderKey}:${issueId}`
                                                    ? isActiveFullTile
                                                      ? isTileFocused
                                                        ? "birds-eye-chat-tile is-focused is-active is-entering"
                                                        : "birds-eye-chat-tile is-active is-entering"
                                                      : isTileFocused
                                                        ? "birds-eye-chat-tile is-focused is-entering"
                                                        : "birds-eye-chat-tile is-entering"
                                                    : isActiveFullTile
                                                      ? isTileFocused
                                                        ? "birds-eye-chat-tile is-focused is-active"
                                                        : "birds-eye-chat-tile is-active"
                                                      : isTileFocused
                                                        ? "birds-eye-chat-tile is-focused"
                                                        : "birds-eye-chat-tile"
                                                }
                                                key={issueId}
                                                onClick={(event) => {
                                                  event.stopPropagation();
                                                  activateTile(
                                                    board.folder.projectId,
                                                    board.folder.folderKey,
                                                    issueId,
                                                  );
                                                }}
                                                onContextMenu={(event) =>
                                                  event.stopPropagation()
                                                }
                                              >
                                                <div className="birds-eye-chat-tile-header">
                                                  <div>
                                                    <strong>
                                                      {tileChat.chat
                                                        .identifier ??
                                                        tileChat.title}
                                                    </strong>
                                                    <span>
                                                      {issueStatusLabel(
                                                        tileChat.chat.status,
                                                      )}
                                                    </span>
                                                  </div>
                                                  <button
                                                    className="secondary-button compact-button"
                                                    onClick={(event) => {
                                                      event.stopPropagation();
                                                      closeIssueTile(
                                                        board.folder.projectId,
                                                        board.folder.folderKey,
                                                        issueId,
                                                      );
                                                    }}
                                                    type="button"
                                                  >
                                                    Close
                                                  </button>
                                                </div>
                                                {isActiveFullTile ? (
                                                  <div className="birds-eye-chat-tile-body is-active">
                                                    {renderIssueTile(
                                                      issueId,
                                                      () =>
                                                        closeIssueTile(
                                                          board.folder
                                                            .projectId,
                                                          board.folder
                                                            .folderKey,
                                                          issueId,
                                                        ),
                                                    )}
                                                  </div>
                                                ) : (
                                                  <div className="birds-eye-chat-tile-body">
                                                    <SpatialBirdsEyeTileStub
                                                      chat={tileChat}
                                                      onActivate={() =>
                                                        activateTile(
                                                          board.folder
                                                            .projectId,
                                                          board.folder
                                                            .folderKey,
                                                          issueId,
                                                        )
                                                      }
                                                    />
                                                  </div>
                                                )}
                                              </div>
                                            );
                                          },
                                        )}
                                      </div>
                                    ) : null}

                                    <div
                                      className={
                                        board.tileState.issueIds.length > 0
                                          ? "birds-eye-worktree-canvas-layer"
                                          : "birds-eye-worktree-canvas-layer is-empty"
                                      }
                                      onContextMenu={(event) =>
                                        openContextMenu(
                                          event,
                                          board.folder.projectId,
                                          board.folder.folderKey,
                                        )
                                      }
                                    >
                                      {quickCreateState?.worktreeKey ===
                                      board.folder.folderKey ? (
                                        <div className="birds-eye-worktree-ghost-card">
                                          <span>New chat</span>
                                          <strong>
                                            {quickCreateState.title ||
                                              "Untitled chat"}
                                          </strong>
                                        </div>
                                      ) : null}
                                      {board.tileState.issueIds.length > 0 ? (
                                        <div className="birds-eye-worktree-canvas-copy">
                                          <span>
                                            Right-click to create or reopen a
                                            chat in this worktree.
                                          </span>
                                        </div>
                                      ) : (
                                        <div className="birds-eye-worktree-empty-state">
                                          <strong>
                                            Open a chat or right-click to create
                                            one
                                          </strong>
                                          <span>
                                            Keep the full history in the sidebar
                                            while up to four chats run here.
                                          </span>
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                </div>
                              </section>
                            );
                          })}
                        </div>
                      </section>
                    );
                  })}

                  <button
                    className="birds-eye-add-project-region"
                    onClick={onCreateProject}
                    style={{
                      left:
                        (repoRegions.at(-1)?.x ??
                          defaultBirdsEyeCanvasOffset.x) +
                        (repoRegions.at(-1)?.width ?? 0) +
                        birdsEyeRepoRegionGapX,
                      top: birdsEyeRepoRegionDefaultY,
                    }}
                    type="button"
                  >
                    <span>+</span>
                    <strong>Add project</strong>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : isLoadingOverview ? (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Loading overview
              </span>
              <h2>Hydrating the spatial canvas</h2>
              <p>
                Repos, worktrees, and chats are loading into the local-first
                canvas.
              </p>
            </div>
          </div>
        </div>
      ) : (
        <div className="dashboard-canvas-empty-wrap birds-eye-empty-wrap">
          <div className="dashboard-canvas-empty-card birds-eye-empty-card">
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Projects required
              </span>
              <h2>Create a project first</h2>
              <p>
                Add a project with a repository anchor before opening worktrees
                and chats on the canvas.
              </p>
            </div>
            <button
              className="primary-button"
              onClick={onCreateProject}
              type="button"
            >
              Create project
            </button>
          </div>
        </div>
      )}

      <div className="dashboard-canvas-route-footer">
        <div className="dashboard-canvas-route-footer-inner">
          <div className="birds-eye-footer-hint">
            <span>Space + drag pans</span>
            <span>Cmd/Ctrl + ↑ or ↓ switches panels</span>
            <span>Right-click the worktree canvas to create</span>
          </div>
          <div
            aria-label="Birds eye zoom"
            className="dashboard-canvas-zoom-control"
            role="group"
          >
            <span className="dashboard-canvas-zoom-label">Zoom</span>
            <div className="dashboard-canvas-zoom-steps">
              {birdsEyeCanvasZoomLevels.map((zoomLevel, index) => (
                <button
                  aria-pressed={
                    index === effectiveCanvasState.viewport.zoomIndex
                  }
                  className={
                    index === effectiveCanvasState.viewport.zoomIndex
                      ? "dashboard-canvas-zoom-step is-active"
                      : "dashboard-canvas-zoom-step"
                  }
                  key={zoomLevel}
                  onClick={() =>
                    updateCanvasState((current) => ({
                      ...current,
                      viewport: {
                        ...current.viewport,
                        zoomIndex: index,
                      },
                    }))
                  }
                  type="button"
                >
                  {dashboardCanvasZoomLabel(zoomLevel)}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {contextMenu ? (
        <SpatialBirdsEyeContextMenu
          onAction={(action) => {
            if (action === "new-chat") {
              openFocusedQuickCreate(
                { x: contextMenu.x, y: contextMenu.y },
                contextMenu.projectId,
                contextMenu.worktreeKey,
              );
              return;
            }

            if (action === "new-agent-session") {
              return;
            }

            if (action === "open-existing-chat") {
              openChatPalette("open-chat", {
                projectId: contextMenu.projectId,
                worktreeKey: contextMenu.worktreeKey,
              });
              return;
            }

            openChatPalette("run-command", {
              projectId: contextMenu.projectId,
              worktreeKey: contextMenu.worktreeKey,
            });
          }}
          x={contextMenu.x}
          y={contextMenu.y}
        />
      ) : null}

      {quickCreateState ? (
        <SpatialBirdsEyeQuickCreatePanel
          dependencyCheck={dependencyCheck}
          draft={quickCreateState.draft}
          errorMessage={quickCreateState.errorMessage}
          inputRef={(element) => {
            quickCreateInputRef.current = element;
          }}
          isSaving={quickCreateState.isSaving}
          onCancel={() => setQuickCreateState(null)}
          onDraftChange={(patch) =>
            setQuickCreateState((current) =>
              current
                ? {
                    ...current,
                    draft: {
                      ...current.draft,
                      ...patch,
                    },
                    errorMessage: null,
                  }
                : current,
            )
          }
          onProjectWorktreeChange={(value) => {
            const nextOption =
              worktreeOptions.find((option) => option.worktreeKey === value) ??
              null;
            if (!nextOption) {
              return;
            }

            setQuickCreateState((current) =>
              current
                ? {
                    ...current,
                    draft: {
                      ...defaultQuickCreateDraft,
                      ...nextOption.folder.createDefaults,
                      command:
                        nextOption.folder.createDefaults.command ??
                        defaultQuickCreateDraft.command,
                      model:
                        nextOption.folder.createDefaults.model ??
                        defaultQuickCreateDraft.model,
                      projectId: nextOption.projectId,
                    },
                    projectId: nextOption.projectId,
                    worktreeKey: nextOption.worktreeKey,
                  }
                : current,
            );
          }}
          onSubmit={handleQuickCreateSubmit}
          onTitleChange={(title) =>
            setQuickCreateState((current) =>
              current
                ? {
                    ...current,
                    errorMessage: null,
                    title,
                  }
                : current,
            )
          }
          selectedWorktreeKey={quickCreateState.worktreeKey}
          title={quickCreateState.title}
          worktreeOptions={worktreeOptions}
          x={quickCreateState.x}
          y={quickCreateState.y}
        />
      ) : null}

      {isCommandPaletteOpen ? (
        <BirdsEyeCommandPalette
          actions={filteredCommandActions}
          activeIndex={commandPaletteIndex}
          inputRef={commandPaletteInputRef}
          isOpen={isCommandPaletteOpen}
          onClose={() => {
            setIsCommandPaletteOpen(false);
            setCommandPaletteScope(null);
          }}
          onQueryChange={setCommandPaletteQuery}
          query={commandPaletteQuery}
        />
      ) : null}
    </section>
  );
}

function SpatialBirdsEyeContextMenu({
  onAction,
  x,
  y,
}: {
  onAction: (
    action:
      | "new-chat"
      | "new-agent-session"
      | "open-existing-chat"
      | "run-command",
  ) => void;
  x: number;
  y: number;
}) {
  return (
    <div className="birds-eye-context-menu" style={{ left: x, top: y }}>
      <button onClick={() => onAction("new-chat")} type="button">
        <strong>New Chat</strong>
        <span>Create a chat at this location.</span>
      </button>
      <button className="is-disabled" disabled type="button">
        <strong>New Agent Session</strong>
        <span>Coming soon.</span>
      </button>
      <button onClick={() => onAction("open-existing-chat")} type="button">
        <strong>Open Existing Chat</strong>
        <span>Search and open a chat in context.</span>
      </button>
      <button onClick={() => onAction("run-command")} type="button">
        <strong>Run Command</strong>
        <span>Open the command palette for this context.</span>
      </button>
    </div>
  );
}

function SpatialBirdsEyeQuickCreatePanel({
  dependencyCheck,
  draft,
  errorMessage,
  inputRef,
  isSaving,
  onCancel,
  onDraftChange,
  onProjectWorktreeChange,
  onSubmit,
  onTitleChange,
  selectedWorktreeKey,
  title,
  worktreeOptions,
  x,
  y,
}: {
  dependencyCheck: RuntimeCapabilities | null;
  draft: BirdsEyeQuickCreateDraft;
  errorMessage: string | null;
  inputRef: (element: HTMLInputElement | null) => void;
  isSaving: boolean;
  onCancel: () => void;
  onDraftChange: (patch: Partial<BirdsEyeQuickCreateDraft>) => void;
  onProjectWorktreeChange: (value: string) => void;
  onSubmit: (event: FormEvent) => void;
  onTitleChange: (title: string) => void;
  selectedWorktreeKey: string;
  title: string;
  worktreeOptions: Array<{
    folder: BirdsEyeFolderNode;
    label: string;
    projectId: string;
    worktreeKey: string;
  }>;
  x: number;
  y: number;
}) {
  const runtimeProvider = detectAgentCliProvider(draft.command, draft.model);
  const runtimeModelOptions = buildAgentModelOptions(
    { command: draft.command, model: draft.model },
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    draft.thinkingEffort,
  );

  return (
    <div className="birds-eye-quick-create-popover" style={{ left: x, top: y }}>
      <form className="birds-eye-quick-create-panel" onSubmit={onSubmit}>
        <div className="birds-eye-quick-create-copy">
          <span className="route-kicker">New chat</span>
          <strong>Spawn a new local-first agent chat</strong>
        </div>

        <input
          className="birds-eye-draft-title-input"
          onChange={(event) => onTitleChange(event.target.value)}
          placeholder="Name this chat"
          ref={inputRef}
          value={title}
        />

        <div className="birds-eye-quick-create-grid">
          <label className="birds-eye-draft-field">
            <span>Worktree</span>
            <IssueDialogInlineSelect
              ariaLabel="Target worktree"
              className="birds-eye-draft-select"
              onChange={onProjectWorktreeChange}
              value={selectedWorktreeKey}
            >
              {worktreeOptions.map((option) => (
                <option key={option.worktreeKey} value={option.worktreeKey}>
                  {option.label}
                </option>
              ))}
            </IssueDialogInlineSelect>
          </label>

          <label className="birds-eye-draft-field">
            <span>Model</span>
            <IssueDialogInlineSelect
              ariaLabel="New chat model"
              className="birds-eye-draft-select"
              onChange={(value) => onDraftChange({ model: value })}
              value={draft.model}
            >
              {runtimeModelOptions.map((option) => (
                <option key={option} value={option}>
                  {option === "default" ? "Default" : option}
                </option>
              ))}
            </IssueDialogInlineSelect>
          </label>

          <label className="birds-eye-draft-field">
            <span>Thinking</span>
            <IssueDialogInlineSelect
              ariaLabel="New chat thinking effort"
              className="birds-eye-draft-select"
              onChange={(value) => onDraftChange({ thinkingEffort: value })}
              value={draft.thinkingEffort}
            >
              {runtimeThinkingEffortOptions.map((option) => (
                <option key={option} value={option}>
                  {capitalize(option)}
                </option>
              ))}
            </IssueDialogInlineSelect>
          </label>

          <div className="birds-eye-draft-field birds-eye-draft-toggle-field">
            <span>Plan mode</span>
            <button
              aria-label="Toggle plan mode"
              aria-pressed={draft.planMode}
              className={
                draft.planMode
                  ? "agent-config-toggle active"
                  : "agent-config-toggle"
              }
              disabled={runtimeProvider !== "claude"}
              onClick={() => onDraftChange({ planMode: !draft.planMode })}
              type="button"
            >
              <span />
            </button>
          </div>
        </div>

        {errorMessage ? (
          <span className="project-kanban-add-card-error">{errorMessage}</span>
        ) : null}

        <div className="birds-eye-draft-actions">
          <button
            className="secondary-button compact-button"
            onClick={onCancel}
            type="button"
          >
            Cancel
          </button>
          <button
            className="primary-button compact-button"
            disabled={isSaving}
            type="submit"
          >
            {isSaving ? "Creating..." : "Create chat"}
          </button>
        </div>
      </form>
    </div>
  );
}

function SpatialBirdsEyeSidebarChatRow({
  chat,
  isActiveTile,
  isFocused,
  isOpen,
  onClick,
}: {
  chat: BirdsEyeChatNode;
  isActiveTile: boolean;
  isFocused: boolean;
  isOpen: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={
        isActiveTile
          ? isFocused
            ? "birds-eye-sidebar-chat-row is-open is-active is-focused"
            : "birds-eye-sidebar-chat-row is-open is-active"
          : isOpen
            ? isFocused
              ? "birds-eye-sidebar-chat-row is-open is-focused"
              : "birds-eye-sidebar-chat-row is-open"
            : isFocused
              ? "birds-eye-sidebar-chat-row is-focused"
              : "birds-eye-sidebar-chat-row"
      }
      onClick={onClick}
      type="button"
    >
      <span
        className={
          isOpen
            ? isActiveTile
              ? "birds-eye-sidebar-chat-indicator is-open is-active"
              : "birds-eye-sidebar-chat-indicator is-open"
            : "birds-eye-sidebar-chat-indicator"
        }
      >
        {isOpen ? "●" : "○"}
      </span>
      <div className="birds-eye-sidebar-chat-main">
        <div className="birds-eye-sidebar-chat-header">
          <strong>{chat.title}</strong>
          {chat.chat.identifier ? <span>{chat.chat.identifier}</span> : null}
        </div>
        <div className="birds-eye-sidebar-chat-meta">
          <span>{issueStatusLabel(chat.chat.status)}</span>
          {isOpen ? (
            <span>{isActiveTile ? "Focused tile" : "Open"}</span>
          ) : null}
        </div>
        <div className="birds-eye-sidebar-chat-last-action">
          {chat.runSummary || chat.agentLabel || "No recent action"}
        </div>
      </div>
    </button>
  );
}

function SpatialBirdsEyeTileStub({
  chat,
  onActivate,
}: {
  chat: BirdsEyeChatNode;
  onActivate: () => void;
}) {
  return (
    <button className="birds-eye-tile-stub" onClick={onActivate} type="button">
      <strong>{chat.title}</strong>
      <span>{chat.chat.identifier ?? issueStatusLabel(chat.chat.status)}</span>
      <p>{chat.runSummary || chat.agentLabel || "Background tile"}</p>
    </button>
  );
}

function BirdsEyeCommandPalette({
  actions,
  activeIndex,
  inputRef,
  isOpen,
  onClose,
  onQueryChange,
  query,
}: {
  actions: Array<{
    description: string;
    id: string;
    label: string;
    run: () => void;
  }>;
  activeIndex: number;
  inputRef: RefObject<HTMLInputElement | null>;
  isOpen: boolean;
  onClose: () => void;
  onQueryChange: (value: string) => void;
  query: string;
}) {
  if (!isOpen) {
    return null;
  }

  return (
    <div
      className="birds-eye-command-backdrop"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="birds-eye-command-palette"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <input
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="Search commands"
          ref={inputRef}
          value={query}
        />
        <div className="birds-eye-command-list">
          {actions.length ? (
            actions.map((action, index) => (
              <button
                className={
                  index === activeIndex
                    ? "birds-eye-command-row is-active"
                    : "birds-eye-command-row"
                }
                key={action.id}
                onClick={() => {
                  onClose();
                  action.run();
                }}
                type="button"
              >
                <strong>{action.label}</strong>
                <span>{action.description}</span>
              </button>
            ))
          ) : (
            <p className="surface-empty-copy">No matching commands.</p>
          )}
        </div>
      </div>
    </div>
  );
}

function BirdsEyeRow({
  buttonRef,
  codeImpact,
  isFocused,
  isPreviewing,
  onClick,
  onDoubleClick,
  onToggleExpand,
  row,
}: {
  buttonRef: (element: HTMLButtonElement | null) => void;
  codeImpact: BirdsEyeCodeImpactSummary | null;
  isFocused: boolean;
  isPreviewing: boolean;
  onClick: () => void;
  onDoubleClick: () => void;
  onToggleExpand: () => void;
  row: BirdsEyeVisibleRow;
}) {
  const node = row.node;
  const isChat = node.kind === "chat";

  return (
    <button
      aria-expanded={row.hasChildren ? row.isExpanded : undefined}
      aria-selected={isFocused}
      className={[
        "birds-eye-row",
        `depth-${row.depth}`,
        node.kind === "project" ? "is-project" : "",
        node.kind === "folder" ? "is-folder" : "",
        isFocused ? "is-focused" : "",
        isPreviewing ? "is-previewing" : "",
        isChat ? "is-chat" : "",
      ]
        .filter(Boolean)
        .join(" ")}
      onClick={onClick}
      onDoubleClick={onDoubleClick}
      ref={buttonRef}
      tabIndex={isFocused ? 0 : -1}
      type="button"
    >
      <div className="birds-eye-row-indent" style={{ width: 0 }} />
      <div className="birds-eye-row-chevron">
        {row.hasChildren ? (
          <span
            className={
              row.isExpanded
                ? "birds-eye-chevron is-expanded"
                : "birds-eye-chevron"
            }
            onClick={(event) => {
              event.stopPropagation();
              onToggleExpand();
            }}
            role="presentation"
          >
            ▸
          </span>
        ) : null}
      </div>

      <div className="birds-eye-row-main">
        {node.kind === "project" ? <strong>{node.label}</strong> : null}

        {node.kind === "folder" ? <strong>{node.label}</strong> : null}

        {node.kind === "chat" ? (
          <>
            <div className="birds-eye-chat-title-row">
              <strong>{node.title}</strong>
            </div>
            <span>
              {[
                issueStatusLabel(node.chat.status),
                node.agentLabel,
                node.runStatus ? agentRunStatusLabel(node.runStatus) : null,
                node.runSummary,
              ]
                .filter(Boolean)
                .join(" · ")}
            </span>
          </>
        ) : null}
      </div>

      <div className="birds-eye-row-meta">
        {node.kind === "project" || node.kind === "folder" ? (
          <>
            <span className="birds-eye-row-metric">
              {node.kind === "project"
                ? `${node.folderCount} ${node.folderCount === 1 ? "folder" : "folders"}`
                : `${node.chatCount} ${node.chatCount === 1 ? "chat" : "chats"}`}
            </span>
            {node.liveRunCount > 0 ? (
              <span className="birds-eye-row-metric">
                {node.liveRunCount} live
              </span>
            ) : null}
            <span className="birds-eye-row-metric">
              {formatCompactIssueTimestamp(node.lastActivityAt)}
            </span>
          </>
        ) : (
          <>
            <span className="birds-eye-row-metric">
              {formatCompactIssueTimestamp(node.lastActivityAt)}
            </span>
          </>
        )}
      </div>
    </button>
  );
}

export function BirdsEyeQuickCreateRow({
  dependencyCheck,
  draft,
  errorMessage,
  folder,
  inputRef,
  isSaving,
  onCancel,
  onDraftChange,
  onSubmit,
  onTitleChange,
  sourceNode,
  title,
}: {
  dependencyCheck: RuntimeCapabilities | null;
  draft: BirdsEyeQuickCreateDraft;
  errorMessage: string | null;
  folder: BirdsEyeFolderNode;
  inputRef: (element: HTMLInputElement | null) => void;
  isSaving: boolean;
  onCancel: () => void;
  onDraftChange: (patch: Partial<BirdsEyeQuickCreateDraft>) => void;
  onSubmit: (event: FormEvent) => void;
  onTitleChange: (title: string) => void;
  sourceNode: BirdsEyeTreeNode | null;
  title: string;
}) {
  const runtimeProvider = detectAgentCliProvider(draft.command, draft.model);
  const runtimeProviderOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    draft.command,
    draft.model,
  );
  const runtimeModelOptions = buildAgentModelOptions(
    { command: draft.command, model: draft.model },
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    draft.thinkingEffort,
  );
  const sourceLabel =
    sourceNode?.kind === "chat"
      ? `Prefilled from ${sourceNode.title}`
      : `New chat in ${folder.label}`;

  return (
    <div className="birds-eye-chat-shell birds-eye-draft-shell">
      <form
        className="birds-eye-row birds-eye-row-draft is-chat"
        onSubmit={onSubmit}
      >
        <div className="birds-eye-row-indent" style={{ width: 0 }} />
        <div className="birds-eye-row-chevron birds-eye-draft-marker">+</div>

        <div className="birds-eye-row-main birds-eye-draft-main">
          <div className="birds-eye-draft-header">
            <input
              className="birds-eye-draft-title-input"
              onChange={(event) => onTitleChange(event.target.value)}
              placeholder="New conversation"
              ref={inputRef}
              value={title}
            />
            <span className="birds-eye-draft-context">{sourceLabel}</span>
          </div>

          <div className="birds-eye-draft-controls">
            <label className="birds-eye-draft-field">
              <span>Provider</span>
              <IssueDialogInlineSelect
                ariaLabel="New chat provider"
                className="birds-eye-draft-select"
                onChange={(value) =>
                  onDraftChange(
                    runtimeDraftPatchForProviderSelection(
                      value,
                      draft,
                      dependencyCheck,
                    ),
                  )
                }
                value={draft.command}
              >
                {runtimeProviderOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </IssueDialogInlineSelect>
            </label>

            <label className="birds-eye-draft-field">
              <span>Model</span>
              <IssueDialogInlineSelect
                ariaLabel="New chat model"
                className="birds-eye-draft-select"
                onChange={(value) => onDraftChange({ model: value })}
                value={draft.model}
              >
                {runtimeModelOptions.map((option) => (
                  <option key={option} value={option}>
                    {option === "default" ? "Default" : option}
                  </option>
                ))}
              </IssueDialogInlineSelect>
            </label>

            <label className="birds-eye-draft-field">
              <span>Thinking</span>
              <IssueDialogInlineSelect
                ariaLabel="New chat thinking effort"
                className="birds-eye-draft-select"
                onChange={(value) => onDraftChange({ thinkingEffort: value })}
                value={draft.thinkingEffort}
              >
                {runtimeThinkingEffortOptions.map((option) => (
                  <option key={option} value={option}>
                    {capitalize(option)}
                  </option>
                ))}
              </IssueDialogInlineSelect>
            </label>

            <div className="birds-eye-draft-field birds-eye-draft-toggle-field">
              <span>Plan mode</span>
              <button
                aria-label="Toggle plan mode"
                aria-pressed={draft.planMode}
                className={
                  draft.planMode
                    ? "agent-config-toggle active"
                    : "agent-config-toggle"
                }
                disabled={runtimeProvider !== "claude"}
                onClick={() => onDraftChange({ planMode: !draft.planMode })}
                type="button"
              >
                <span />
              </button>
            </div>
          </div>

          {errorMessage ? (
            <span className="project-kanban-add-card-error">
              {errorMessage}
            </span>
          ) : null}
        </div>

        <div className="birds-eye-row-meta birds-eye-draft-actions">
          <button
            className="secondary-button compact-button"
            onClick={onCancel}
            type="button"
          >
            Cancel
          </button>
          <button
            className="primary-button compact-button"
            disabled={isSaving}
            type="submit"
          >
            {isSaving ? "Creating..." : "Create"}
          </button>
        </div>
      </form>
    </div>
  );
}

function BirdsEyePreviewPanel({
  agents,
  attachments,
  codeImpact,
  comments,
  errorMessage,
  isLoading,
  issue,
  onClose,
  onOpenIssue,
  runCardUpdate,
  subissueCount,
}: {
  agents: AgentRecord[];
  attachments: IssueAttachmentRecord[];
  codeImpact: BirdsEyeCodeImpactSummary | null;
  comments: IssueCommentRecord[];
  errorMessage: string | null;
  isLoading: boolean;
  issue: IssueRecord | null;
  onClose: () => void;
  onOpenIssue: (issueId: string) => void;
  runCardUpdate: IssueRunCardUpdateRecord | null;
  subissueCount: number;
}) {
  const latestComments = [...comments].slice(-3).reverse();

  return (
    <aside className="birds-eye-preview-panel">
      {issue ? (
        <>
          <div className="birds-eye-preview-header">
            <div>
              <span className="route-kicker">
                {issue.identifier ?? "Conversation"}
              </span>
              <h2>{issue.title}</h2>
              <p>
                {issue.description?.trim() ||
                  "Use the lightweight preview for the latest messages, attachments, and code impact without leaving the dashboard."}
              </p>
            </div>
            <button
              aria-label="Close preview"
              className="project-dialog-close issue-dialog-close"
              onClick={onClose}
              type="button"
            >
              x
            </button>
          </div>

          <div className="birds-eye-preview-summary">
            <SummaryPill
              label="Status"
              value={issueStatusLabel(issue.status)}
            />
            <SummaryPill label="Agent" value={issueModelLabel(issue, agents)} />
            <SummaryPill
              label="Last activity"
              value={formatRelativeIssueDate(issue.updated_at)}
            />
            <SummaryPill
              label="Code impact"
              value={birdsEyeImpactLabel(codeImpact)}
            />
            <SummaryPill label="Queued" value={subissueCount} />
          </div>

          {runCardUpdate ? (
            <section className="birds-eye-preview-update">
              <div className="birds-eye-preview-update-header">
                <strong>Latest model run</strong>
                <RunStatusBadge status={runCardUpdate.run_status} />
              </div>
              <p>{issueRunCardUpdateSummary(runCardUpdate)}</p>
              <span>
                {formatRelativeIssueDate(runCardUpdate.last_activity_at)}
              </span>
            </section>
          ) : null}

          {errorMessage ? (
            <div className="issue-dialog-alert">{errorMessage}</div>
          ) : null}
          {isLoading ? (
            <p className="issues-detail-copy muted">
              Loading the latest conversation state...
            </p>
          ) : null}

          <section className="birds-eye-preview-section">
            <div className="issues-detail-subsection-copy">
              <h3>Recent messages</h3>
              <p className="issues-detail-copy muted">
                Latest context without opening the full thread.
              </p>
            </div>
            {latestComments.length ? (
              <div className="issues-comment-list">
                {latestComments.map((comment) => (
                  <article className="issues-comment-card" key={comment.id}>
                    <div className="issues-comment-card-target">
                      {issueCommentAuthorLabel(agents, comment)}
                    </div>
                    <p>{comment.body}</p>
                    <span>{formatIssueDate(comment.created_at)}</span>
                  </article>
                ))}
              </div>
            ) : (
              <p className="issues-detail-copy muted">No messages yet.</p>
            )}
          </section>

          <section className="birds-eye-preview-section">
            <div className="issues-detail-subsection-copy">
              <h3>Attachments</h3>
              <p className="issues-detail-copy muted">
                Files linked to this conversation.
              </p>
            </div>
            {attachments.length ? (
              <div className="issue-attachment-list">
                {attachments.slice(0, 4).map((attachment) => (
                  <div className="issue-attachment-row" key={attachment.id}>
                    <div className="issue-attachment-meta">
                      <strong>
                        {attachment.original_filename ??
                          fileName(attachment.local_path)}
                      </strong>
                      <span>
                        {formatFileSize(attachment.byte_size)} ·{" "}
                        {formatIssueDate(attachment.created_at)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="issues-detail-copy muted">No attachments yet.</p>
            )}
          </section>

          <div className="birds-eye-preview-footer">
            <button
              className="primary-button compact-button"
              onClick={() => onOpenIssue(issue.id)}
              type="button"
            >
              Open conversation
            </button>
          </div>
        </>
      ) : (
        <div className="birds-eye-preview-empty">
          <span className="route-kicker">Preview</span>
          <h2>Focus a chat to inspect it lightly</h2>
          <p>
            Right or Enter previews the focused chat. Escape closes the preview,
            and Enter again opens the full conversation detail only when you
            actually need it.
          </p>
        </div>
      )}
    </aside>
  );
}

function DashboardCanvasRouteView({
  agents,
  canvasBounds,
  canvasOffset,
  canvasZoomIndex,
  canvasZoomLevels,
  canvasZoomScale,
  isDragging,
  onCreateProject,
  onOpenIssue,
  onPointerCancel,
  onPointerDown,
  onPointerMove,
  onPointerUp,
  onCreateIssueForColumn,
  onCreateProjectView,
  onProjectGroupingChange,
  onZoomIndexChange,
  issueRunCardUpdatesByIssueId,
  onWheel,
  projectColumns,
  selectedProjectId,
  viewportRef,
}: {
  agents: AgentRecord[];
  canvasBounds: { height: number; width: number };
  canvasOffset: DashboardCanvasOffset;
  canvasZoomIndex: number;
  canvasZoomLevels: readonly number[];
  canvasZoomScale: number;
  isDragging: boolean;
  onCreateProject: () => void;
  onOpenIssue: (issueId: string) => void;
  onPointerCancel: (event: PointerEvent<HTMLDivElement>) => void;
  onPointerDown: (event: PointerEvent<HTMLDivElement>) => void;
  onPointerMove: (event: PointerEvent<HTMLDivElement>) => void;
  onPointerUp: (event: PointerEvent<HTMLDivElement>) => void;
  onCreateIssueForColumn: (defaults?: CreateIssueDialogDefaults) => void;
  onCreateProjectView: (
    projectId: string,
    draft: DashboardProjectViewDraft,
  ) => Promise<void>;
  onProjectGroupingChange: (
    projectId: string,
    viewId: string,
    grouping: DashboardProjectGrouping,
  ) => void;
  onZoomIndexChange: (nextZoomIndex: number) => void;
  issueRunCardUpdatesByIssueId: Record<string, IssueRunCardUpdateRecord>;
  onWheel: (event: WheelEvent<HTMLDivElement>) => void;
  projectColumns: DashboardProjectColumnLayout[];
  selectedProjectId: string | null;
  viewportRef: RefObject<HTMLDivElement | null>;
}) {
  const [creatingProjectId, setCreatingProjectId] = useState<string | null>(
    null,
  );
  const [newProjectViewName, setNewProjectViewName] = useState("");
  const [newProjectViewGrouping, setNewProjectViewGrouping] =
    useState<DashboardProjectGrouping>("status");
  const [projectViewError, setProjectViewError] = useState<string | null>(null);
  const [savingProjectId, setSavingProjectId] = useState<string | null>(null);

  useEffect(() => {
    if (
      creatingProjectId &&
      !projectColumns.some((column) => column.project.id === creatingProjectId)
    ) {
      setCreatingProjectId(null);
      setNewProjectViewName("");
      setNewProjectViewGrouping("status");
      setProjectViewError(null);
      setSavingProjectId(null);
    }
  }, [creatingProjectId, projectColumns]);

  const handleOpenProjectViewComposer = (
    projectColumn: DashboardProjectColumnLayout,
  ) => {
    setCreatingProjectId(projectColumn.project.id);
    setNewProjectViewName(nextDashboardProjectViewName(projectColumn.boards));
    setNewProjectViewGrouping(
      nextDashboardProjectViewGrouping(projectColumn.boards),
    );
    setProjectViewError(null);
  };

  const handleCloseProjectViewComposer = () => {
    setCreatingProjectId(null);
    setNewProjectViewName("");
    setNewProjectViewGrouping("status");
    setProjectViewError(null);
    setSavingProjectId(null);
  };

  const handleSaveProjectView = async (projectId: string) => {
    setSavingProjectId(projectId);
    setProjectViewError(null);

    try {
      await onCreateProjectView(projectId, {
        grouping: newProjectViewGrouping,
        name: newProjectViewName,
      });
      handleCloseProjectViewComposer();
    } catch (error) {
      setProjectViewError(
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setSavingProjectId((current) => (current === projectId ? null : current));
    }
  };

  return (
    <section className="dashboard-canvas-route">
      <div className="dashboard-canvas-route-header">
        <div className="dashboard-canvas-route-header-inner">
          <DashboardBreadcrumbs items={[{ label: "Dashboard" }]} />
        </div>
      </div>
      {projectColumns.length ? (
        <div
          className={
            isDragging
              ? "dashboard-canvas-viewport is-dragging"
              : "dashboard-canvas-viewport"
          }
          onPointerCancel={onPointerCancel}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onWheel={onWheel}
          ref={viewportRef}
        >
          <div className="dashboard-canvas-grid" />
          <div
            className="dashboard-canvas-stage"
            style={{
              height: canvasBounds.height * canvasZoomScale,
              transform: `translate(${canvasOffset.x}px, ${canvasOffset.y}px)`,
              width: canvasBounds.width * canvasZoomScale,
            }}
          >
            <div
              className="dashboard-canvas-stage-scaler"
              style={{
                height: canvasBounds.height,
                transform: `scale(${canvasZoomScale})`,
                width: canvasBounds.width,
              }}
            >
              {projectColumns.map((projectColumn) => {
                const isSelected =
                  selectedProjectId === projectColumn.project.id;
                const isCreatingProjectView =
                  creatingProjectId === projectColumn.project.id;
                const isSavingProjectView =
                  savingProjectId === projectColumn.project.id;

                return (
                  <div
                    className={
                      isSelected
                        ? "dashboard-project-column is-selected"
                        : "dashboard-project-column"
                    }
                    key={projectColumn.project.id}
                    style={{
                      left: projectColumn.left,
                      top: projectColumn.top,
                      width: projectColumn.width,
                    }}
                  >
                    {projectColumn.boards.map((projectBoard) => (
                      <article
                        className={
                          isSelected
                            ? "project-kanban-board is-selected"
                            : "project-kanban-board"
                        }
                        key={projectBoard.boardId}
                        style={{
                          width: projectBoard.width,
                        }}
                      >
                        <div className="project-kanban-board-header">
                          <div className="project-kanban-board-copy">
                            <span className="project-kanban-view-label">
                              {projectBoard.viewName}
                            </span>
                            <h2>
                              {projectBoard.project.name ??
                                projectBoard.project.title ??
                                "Untitled project"}
                            </h2>
                            <p className="project-kanban-board-path">
                              {projectBoard.project.primary_workspace?.cwd ??
                                "Choose a repository to anchor this project."}
                            </p>
                          </div>
                          <div className="project-kanban-board-side">
                            <label className="project-kanban-board-grouping">
                              <span>Group by</span>
                              <ShadcnSelect
                                ariaLabel={`Group ${projectBoard.project.name ?? projectBoard.project.title ?? "project"} ${projectBoard.viewName} by`}
                                onChange={(nextValue) =>
                                  onProjectGroupingChange(
                                    projectColumn.project.id,
                                    projectBoard.viewId,
                                    nextValue,
                                  )
                                }
                                options={dashboardProjectGroupingSelectOptions}
                                value={projectBoard.grouping}
                              />
                            </label>

                            <div className="project-kanban-board-meta">
                              <span>
                                {projectBoard.issueCount} conversations
                              </span>
                              <span>
                                {projectBoard.project.target_date
                                  ? `Target ${formatShortDate(projectBoard.project.target_date)}`
                                  : "No target date"}
                              </span>
                            </div>
                          </div>
                        </div>

                        <div
                          className="project-kanban-columns"
                          style={{
                            gap: dashboardProjectBoardColumnGap,
                            gridAutoColumns: `${dashboardProjectBoardColumnWidth}px`,
                          }}
                        >
                          {projectBoard.columns.map((column) => {
                            const createIssueCard = (
                              <button
                                className="project-kanban-column-create"
                                onClick={() =>
                                  onCreateIssueForColumn({
                                    projectId: projectBoard.project.id,
                                    ...column.createDefaults,
                                  })
                                }
                                type="button"
                              >
                                <span
                                  aria-hidden="true"
                                  className="project-kanban-column-create-icon"
                                >
                                  +
                                </span>
                                <span className="project-kanban-column-create-copy">
                                  <strong>New conversation</strong>
                                </span>
                              </button>
                            );

                            return (
                              <section
                                className="project-kanban-column"
                                key={column.id}
                              >
                                <div className="project-kanban-column-header">
                                  <div className="project-kanban-column-header-copy">
                                    <span>{column.label}</span>
                                    <strong>{column.issues.length}</strong>
                                  </div>
                                </div>

                                <div className="project-kanban-cards">
                                  {column.issues.length ? (
                                    <>
                                      {column.issues.map((issue) => {
                                        const cardUpdate =
                                          issueRunCardUpdatesByIssueId[
                                            issue.id
                                          ] ?? null;
                                        const cardUpdateSummary = cardUpdate
                                          ? issueRunCardUpdateSummary(
                                              cardUpdate,
                                            )
                                          : null;
                                        const issueAgentLabel = issueModelLabel(
                                          issue,
                                          agents,
                                        );
                                        const hasAssignedAgent =
                                          Boolean(issue.assignee_agent_id) ||
                                          Object.keys(
                                            objectFromUnknown(
                                              issue.assignee_adapter_overrides,
                                            ),
                                          ).length > 0;

                                        return (
                                          <button
                                            className="project-kanban-card"
                                            key={issue.id}
                                            onClick={() =>
                                              onOpenIssue(issue.id)
                                            }
                                            type="button"
                                          >
                                            <div className="project-kanban-card-header">
                                              <span className="project-kanban-card-identifier">
                                                {issue.identifier ?? ""}
                                              </span>
                                              <span
                                                aria-label={
                                                  hasAssignedAgent
                                                    ? `Assigned agent ${issueAgentLabel}`
                                                    : "No assigned agent"
                                                }
                                                className={
                                                  hasAssignedAgent
                                                    ? "project-kanban-card-assignee-avatar"
                                                    : "project-kanban-card-assignee-avatar is-unassigned"
                                                }
                                                title={issueAgentLabel}
                                              >
                                                {agentInitials(issueAgentLabel)}
                                              </span>
                                            </div>
                                            <strong>{issue.title}</strong>
                                            {cardUpdate ? (
                                              <div className="project-kanban-card-update">
                                                <span
                                                  className={`agent-run-status-badge ${agentRunStatusTone(cardUpdate.run_status)} project-kanban-card-update-status`}
                                                >
                                                  {agentRunStatusLabel(
                                                    cardUpdate.run_status,
                                                  )}
                                                </span>
                                                <span
                                                  className="project-kanban-card-update-copy"
                                                  title={
                                                    cardUpdateSummary ??
                                                    undefined
                                                  }
                                                >
                                                  {cardUpdateSummary}
                                                </span>
                                              </div>
                                            ) : null}
                                          </button>
                                        );
                                      })}
                                      {createIssueCard}
                                    </>
                                  ) : (
                                    <div className="project-kanban-column-empty">
                                      <span>No conversations yet</span>
                                      {createIssueCard}
                                    </div>
                                  )}
                                </div>
                              </section>
                            );
                          })}
                        </div>
                      </article>
                    ))}

                    <div className="project-kanban-add-slot">
                      {isCreatingProjectView ? (
                        <div className="project-kanban-add-card">
                          <div className="project-kanban-add-card-copy">
                            <strong>Save another view</strong>
                            <p>
                              Keep alternate groupings for this project in the
                              same dashboard column.
                            </p>
                            {projectViewError ? (
                              <span className="project-kanban-add-card-error">
                                {projectViewError}
                              </span>
                            ) : null}
                          </div>
                          <div className="project-kanban-add-card-controls">
                            <input
                              className="project-kanban-add-input"
                              onChange={(event) =>
                                setNewProjectViewName(event.target.value)
                              }
                              placeholder="View name"
                              value={newProjectViewName}
                            />
                            <div className="project-kanban-add-grouping">
                              <ShadcnSelect
                                ariaLabel="Choose grouping for saved project view"
                                onChange={setNewProjectViewGrouping}
                                options={dashboardProjectGroupingSelectOptions}
                                value={newProjectViewGrouping}
                              />
                            </div>
                            <div className="project-kanban-add-actions">
                              <button
                                className="secondary-button compact-button"
                                disabled={isSavingProjectView}
                                onClick={handleCloseProjectViewComposer}
                                type="button"
                              >
                                Cancel
                              </button>
                              <button
                                className="primary-button compact-button"
                                disabled={isSavingProjectView}
                                onClick={() =>
                                  void handleSaveProjectView(
                                    projectColumn.project.id,
                                  )
                                }
                                type="button"
                              >
                                {isSavingProjectView
                                  ? "Saving..."
                                  : "Save view"}
                              </button>
                            </div>
                          </div>
                        </div>
                      ) : (
                        <button
                          className="project-kanban-add-button"
                          onClick={() =>
                            handleOpenProjectViewComposer(projectColumn)
                          }
                          type="button"
                        >
                          <span
                            aria-hidden="true"
                            className="project-kanban-add-button-icon"
                          >
                            +
                          </span>
                          <span className="project-kanban-add-button-copy">
                            <strong>Save another view</strong>
                            <small>
                              Add a dimmed secondary kanban variant for this
                              project column.
                            </small>
                          </span>
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      ) : (
        <div className="dashboard-canvas-empty-wrap">
          <div className="dashboard-canvas-empty-card">
            <div aria-hidden="true" className="dashboard-canvas-empty-icon">
              <svg fill="none" viewBox="0 0 48 48">
                <path
                  d="M10 13.5h28A3.5 3.5 0 0 1 41.5 17v18A3.5 3.5 0 0 1 38 38.5H10A3.5 3.5 0 0 1 6.5 35V17A3.5 3.5 0 0 1 10 13.5Z"
                  stroke="currentColor"
                  strokeWidth="2.4"
                />
                <path
                  d="M16 24h16M24 16v16"
                  stroke="currentColor"
                  strokeLinecap="round"
                  strokeWidth="2.4"
                />
              </svg>
            </div>
            <div className="dashboard-canvas-empty-copy">
              <span className="dashboard-canvas-empty-badge">
                Projects required
              </span>
              <h2>Create a project first</h2>
              <p>
                Each project gets its own kanban board on this canvas. Add a
                project with a repository anchor to start laying out your board.
              </p>
            </div>
            <button
              className="primary-button"
              onClick={onCreateProject}
              type="button"
            >
              Create project
            </button>
          </div>
        </div>
      )}
      <div className="dashboard-canvas-route-footer">
        <div className="dashboard-canvas-route-footer-inner">
          <div
            aria-label="Dashboard zoom"
            className="dashboard-canvas-zoom-control"
            role="group"
          >
            <span className="dashboard-canvas-zoom-label">Zoom</span>
            <div className="dashboard-canvas-zoom-steps">
              {canvasZoomLevels.map((zoomLevel, index) => (
                <button
                  aria-pressed={index === canvasZoomIndex}
                  className={
                    index === canvasZoomIndex
                      ? "dashboard-canvas-zoom-step is-active"
                      : "dashboard-canvas-zoom-step"
                  }
                  key={zoomLevel}
                  onClick={() => onZoomIndexChange(index)}
                  type="button"
                >
                  {dashboardCanvasZoomLabel(zoomLevel)}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function IssueDetailView({
  issue,
  issueDraft,
  isSavingIssue,
  isWorking,
  attachments,
  availableStatusOptions,
  dependencyCheck,
  projects,
  agents,
  selectableParentIssues,
  subissues,
  comments,
  issueEditorError,
  issueWorkspaceSidebar,
  newCommentBody,
  onBack,
  onCommitIssuePatch,
  onHideIssue,
  onIssueDraftChange,
  onOpenRunDetail,
  onOpenQueuedConversation,
  onNewCommentBodyChange,
  onAddComment,
  onAddAttachment,
  onQueueMessage,
  onRevealAttachment,
  projectLabel,
  parentIssueLabel,
  statusLabel,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  isSavingIssue: boolean;
  isWorking: boolean;
  attachments: IssueAttachmentRecord[];
  availableStatusOptions: string[];
  dependencyCheck: RuntimeCapabilities | null;
  projects: ProjectRecord[];
  agents: AgentRecord[];
  selectableParentIssues: IssueRecord[];
  subissues: IssueRecord[];
  comments: IssueCommentRecord[];
  issueEditorError: string | null;
  issueWorkspaceSidebar?: ReactNode;
  newCommentBody: string;
  onBack: () => void;
  onCommitIssuePatch: (patch: Partial<IssueEditDraft>) => void;
  onHideIssue: () => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  onOpenRunDetail: (run: AgentRunRecord) => void;
  onOpenQueuedConversation: (issueId: string) => void;
  onNewCommentBodyChange: (value: string) => void;
  onAddComment: () => void;
  onAddAttachment: () => void;
  onQueueMessage: () => void;
  onRevealAttachment: (attachment: IssueAttachmentRecord) => void;
  projectLabel: (projectId?: string | null) => string;
  parentIssueLabel: (parentIssueId?: string | null) => string;
  statusLabel: (value: string) => string;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const [activeTab, setActiveTab] = useState<IssueDetailTab>("conversation");
  const [linkedRuns, setLinkedRuns] = useState<IssueLinkedRun[]>([]);
  const [isLoadingLinkedRuns, setIsLoadingLinkedRuns] = useState(false);
  const [linkedRunsError, setLinkedRunsError] = useState<string | null>(null);
  const [isPropertiesOpen, setIsPropertiesOpen] = useState(false);
  const [isIssueActionsOpen, setIsIssueActionsOpen] = useState(false);
  const descriptionInputRef = useRef<HTMLTextAreaElement | null>(null);
  const issueActionsMenuRef = useRef<HTMLDivElement | null>(null);
  const issueActionsButtonRef = useRef<HTMLButtonElement | null>(null);

  const issueProjectName = projectLabel(issueDraft.projectId || null);
  const issueValidationMessage = issueStatusAssigneeValidationMessage(
    issueDraft.status,
    issueDraft.assigneeAgentId,
    agents,
  );
  const visibleIssueEditorError = issueValidationMessage ?? issueEditorError;
  const selectedProject =
    projects.find((project) => project.id === issueDraft.projectId) ?? null;
  const selectedProjectRepoPath =
    selectedProject?.primary_workspace?.cwd ?? null;
  const normalizedIssueStatus = normalizeBoardIssueValue(issue.status);
  const commentWillReopenIssue =
    normalizedIssueStatus === "done" || normalizedIssueStatus === "cancelled";
  const selectedWorkspaceTargetValue = issueWorkspaceTargetSelectValue(
    issueDraft.workspaceTargetMode,
    issueDraft.workspaceWorktreePath,
  );
  const workspaceTargetHint = issueWorkspaceTargetHint({
    errorMessage: workspaceTargetErrorMessage,
    hasProject: Boolean(selectedProject),
    hasRepoPath: Boolean(selectedProjectRepoPath),
    isLoading: workspaceTargetLoading,
    worktreeCount: workspaceTargetWorktrees.length,
  });
  const fallbackSelectedWorktree =
    selectedWorkspaceTargetValue.startsWith("existing:") &&
    !workspaceTargetWorktrees.some(
      (worktree) =>
        existingWorktreeTargetValue(worktree.path) ===
        selectedWorkspaceTargetValue,
    )
      ? {
          name:
            issueDraft.workspaceWorktreeName ||
            fileName(issueDraft.workspaceWorktreePath),
          path: issueDraft.workspaceWorktreePath,
        }
      : null;
  const runtimeProvider = detectAgentCliProvider(
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeModelOptions = buildAgentModelOptions(
    issueDraft,
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    issueDraft.thinkingEffort,
  );
  const runtimeProviderOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeBrowserToggleLabel =
    runtimeProvider === "codex" ? "Enable web search" : "Enable Chrome";
  const runtimeBrowserToggleDescription =
    runtimeProvider === "codex"
      ? "Expose Codex web search during runs."
      : "Allow browser automation inside Claude runs.";

  const syncDescriptionInputHeight = () => {
    const textarea = descriptionInputRef.current;
    if (!textarea) {
      return;
    }

    textarea.style.height = "0px";
    textarea.style.height = `${textarea.scrollHeight}px`;
  };

  useLayoutEffect(() => {
    syncDescriptionInputHeight();
  }, [issue.id, issueDraft.description]);

  useEffect(() => {
    setActiveTab("conversation");
    setIsPropertiesOpen(false);
    setIsIssueActionsOpen(false);

    let cancelled = false;
    setIsLoadingLinkedRuns(true);

    void boardListIssueRuns(issue.id, 100)
      .then((runs) => {
        if (cancelled) {
          return;
        }

        const nextLinkedRuns = (runs as AgentRunRecord[]).map((run) => ({
          label: issueLinkedRunLabel(issue, run),
          run,
        }));

        startTransition(() => {
          setLinkedRuns(nextLinkedRuns);
          setLinkedRunsError(null);
        });
      })
      .catch((error) => {
        if (cancelled) {
          return;
        }

        setLinkedRuns([]);
        setLinkedRunsError(
          error instanceof Error
            ? error.message
            : "Could not load linked runs.",
        );
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoadingLinkedRuns(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [issue.id, issue.checkout_run_id, issue.execution_run_id]);

  useEffect(() => {
    if (!isIssueActionsOpen) {
      return;
    }

    const closeMenu = (event: Event) => {
      const target = event.target as Node | null;
      if (
        (issueActionsMenuRef.current &&
          target &&
          issueActionsMenuRef.current.contains(target)) ||
        (issueActionsButtonRef.current &&
          target &&
          issueActionsButtonRef.current.contains(target))
      ) {
        return;
      }

      setIsIssueActionsOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsIssueActionsOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isIssueActionsOpen]);

  useEffect(() => {
    if (!isPropertiesOpen) {
      return;
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsPropertiesOpen(false);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isPropertiesOpen]);

  const commitTitleOnBlur = () => {
    const trimmedTitle = issueDraft.title.trim();
    const currentTitle = issue.title.trim();

    if (!trimmedTitle) {
      onIssueDraftChange({ title: issue.title });
      return;
    }

    if (trimmedTitle !== issueDraft.title) {
      onIssueDraftChange({ title: trimmedTitle });
    }

    if (trimmedTitle !== currentTitle) {
      onCommitIssuePatch({ title: trimmedTitle });
    }
  };

  const commitDescriptionOnBlur = () => {
    const trimmedDescription = issueDraft.description.trim();
    const currentDescription = (issue.description ?? "").trim();

    if (trimmedDescription !== issueDraft.description) {
      onIssueDraftChange({ description: trimmedDescription });
    }

    if (trimmedDescription !== currentDescription) {
      onCommitIssuePatch({ description: trimmedDescription });
    }
  };

  const commitPropertyPatch = (patch: Partial<IssueEditDraft>) => {
    onIssueDraftChange(patch);
    onCommitIssuePatch(patch);
  };

  const handleToggleProperties = () => {
    setIsIssueActionsOpen(false);
    setIsPropertiesOpen((current) => !current);
  };

  const handleToggleIssueActions = () => {
    setIsPropertiesOpen(false);
    setIsIssueActionsOpen((current) => !current);
  };

  const handleHideIssue = () => {
    setIsIssueActionsOpen(false);
    setIsPropertiesOpen(false);
    onHideIssue();
  };

  const issueBreadcrumbTitle = issueDraft.title.trim() || issue.title;

  return (
    <section className="route-scroll issues-detail-route">
      <DashboardBreadcrumbs
        items={[
          { label: "Conversations", onClick: onBack },
          { label: issueBreadcrumbTitle },
        ]}
      />

      <div className="issues-detail-layout">
        <section className="issues-detail-panel issues-detail-main-panel">
          <div className="issues-detail-identity-row">
            <div className="issues-detail-identity-copy">
              <span className="issues-detail-identifier">
                {issue.identifier ?? issue.id}
              </span>
              <span className="issues-detail-project-name">
                {issueProjectName}
              </span>
            </div>
            <div className="issues-detail-toolbar-actions">
              <button
                aria-label={
                  isPropertiesOpen
                    ? "Close properties sidebar"
                    : "Open properties sidebar"
                }
                className={
                  isPropertiesOpen
                    ? "icon-button issues-detail-toolbar-button active"
                    : "icon-button issues-detail-toolbar-button"
                }
                onClick={handleToggleProperties}
                type="button"
              >
                <SlidersHorizontalIcon />
              </button>
              <div className="issues-detail-toolbar-menu-shell">
                <button
                  aria-expanded={isIssueActionsOpen}
                  aria-haspopup="menu"
                  aria-label="Conversation actions"
                  className={
                    isIssueActionsOpen
                      ? "icon-button issues-detail-toolbar-button active"
                      : "icon-button issues-detail-toolbar-button"
                  }
                  onClick={handleToggleIssueActions}
                  ref={issueActionsButtonRef}
                  type="button"
                >
                  <EllipsisHorizontalIcon />
                </button>
                {isIssueActionsOpen ? (
                  <div
                    className="issues-detail-toolbar-menu"
                    onPointerDown={(event) => event.stopPropagation()}
                    ref={issueActionsMenuRef}
                    role="menu"
                  >
                    <button
                      className="issues-detail-toolbar-menu-item"
                      disabled={isSavingIssue}
                      onClick={handleHideIssue}
                      role="menuitem"
                      type="button"
                    >
                      Hide this conversation
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          </div>

          <div className="issues-detail-title-row">
            <div className="issues-detail-title-block">
              <input
                className="issues-inline-title-input"
                onBlur={commitTitleOnBlur}
                onChange={(event) =>
                  onIssueDraftChange({
                    title: event.target.value,
                  })
                }
                placeholder="Conversation title"
                value={issueDraft.title}
              />
              <textarea
                className="issues-inline-description-input"
                onBlur={commitDescriptionOnBlur}
                onChange={(event) =>
                  onIssueDraftChange({
                    description: event.target.value,
                  })
                }
                onInput={syncDescriptionInputHeight}
                placeholder="Add context, decisions, or the next thing a model should pick up."
                ref={descriptionInputRef}
                rows={1}
                value={issueDraft.description}
              />
              <div className="issues-detail-inline-meta">
                <span className="issues-detail-copy muted">
                  Title and description save when you leave the field.
                </span>
                {isSavingIssue ? (
                  <span className="issues-detail-inline-saving">Saving…</span>
                ) : null}
              </div>
            </div>
          </div>

          {visibleIssueEditorError ? (
            <div className="issue-dialog-alert">{visibleIssueEditorError}</div>
          ) : null}

          <section className="issues-detail-section">
            <div
              aria-label="Conversation details sections"
              className="issues-detail-tabs"
              role="tablist"
            >
              <button
                aria-selected={activeTab === "conversation"}
                className={
                  activeTab === "conversation"
                    ? "issues-detail-tab-button active"
                    : "issues-detail-tab-button"
                }
                onClick={() => setActiveTab("conversation")}
                role="tab"
                type="button"
              >
                Conversation
              </button>
              <button
                aria-selected={activeTab === "runs"}
                className={
                  activeTab === "runs"
                    ? "issues-detail-tab-button active"
                    : "issues-detail-tab-button"
                }
                onClick={() => setActiveTab("runs")}
                role="tab"
                type="button"
              >
                Runs
              </button>
              <button
                aria-selected={activeTab === "queued"}
                className={
                  activeTab === "queued"
                    ? "issues-detail-tab-button active"
                    : "issues-detail-tab-button"
                }
                onClick={() => setActiveTab("queued")}
                role="tab"
                type="button"
              >
                Queued
              </button>
            </div>

            <div className="issues-detail-tab-panel" role="tabpanel">
              {activeTab === "conversation" ? (
                <>
                  <div className="issues-detail-subsection">
                    <div className="issues-detail-subsection-header">
                      <div className="issues-detail-subsection-copy">
                        <h3>Attachments</h3>
                        <p className="issues-detail-copy muted">
                          Files live with the local board data and are included
                          in future model runs for this conversation.
                        </p>
                      </div>
                      <button
                        className="secondary-button compact-button"
                        disabled={isWorking}
                        onClick={onAddAttachment}
                        type="button"
                      >
                        {isWorking ? "Uploading..." : "Add attachment"}
                      </button>
                    </div>

                    {attachments.length ? (
                      <div className="issue-attachment-list">
                        {attachments.map((attachment) => (
                          <div
                            className="issue-attachment-row"
                            key={attachment.id}
                          >
                            <div className="issue-attachment-meta">
                              <strong>
                                {attachment.original_filename ??
                                  fileName(attachment.local_path)}
                              </strong>
                              <span>
                                {formatFileSize(attachment.byte_size)} ·{" "}
                                {attachment.content_type} ·{" "}
                                {formatIssueDate(attachment.created_at)}
                              </span>
                            </div>
                            <div className="issue-attachment-actions">
                              <button
                                className="secondary-button compact-button"
                                onClick={() => onRevealAttachment(attachment)}
                                type="button"
                              >
                                Reveal
                              </button>
                            </div>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="issues-detail-copy muted">
                        No attachments yet.
                      </p>
                    )}
                  </div>

                  <div className="issues-detail-subsection">
                    <div className="issues-detail-subsection-header">
                      <div className="issues-detail-subsection-copy">
                        <h3>Messages</h3>
                      </div>
                    </div>

                    {comments.length ? (
                      <div className="issues-comment-list">
                        {comments.map((comment) => (
                          <article
                            className="issues-comment-card"
                            key={comment.id}
                          >
                            <div className="issues-comment-card-target">
                              {issueCommentAuthorLabel(agents, comment)}
                            </div>
                            <p>{comment.body}</p>
                            <span>{formatIssueDate(comment.created_at)}</span>
                          </article>
                        ))}
                      </div>
                    ) : (
                      <p className="issues-detail-copy muted">
                        No messages yet.
                      </p>
                    )}

                    <div className="issues-comment-composer">
                      <textarea
                        onChange={(event) =>
                          onNewCommentBodyChange(event.target.value)
                        }
                        placeholder="Send a message..."
                        value={newCommentBody}
                      />
                      <div className="issues-comment-composer-footer">
                        <button
                          aria-label="Add attachment"
                          className="icon-button issues-comment-attachment-button"
                          disabled={isWorking}
                          onClick={onAddAttachment}
                          type="button"
                        >
                          <AttachmentButtonIcon />
                        </button>
                        <div className="issues-comment-composer-actions">
                          {commentWillReopenIssue ? (
                            <label className="issues-comment-reopen-indicator">
                              <input checked readOnly type="checkbox" />
                              <span>Re-open conversation</span>
                            </label>
                          ) : null}
                          <button
                            className="secondary-button issues-comment-submit-button"
                            disabled={isWorking || !newCommentBody.trim()}
                            onClick={onAddComment}
                            type="button"
                          >
                            Send message
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </>
              ) : null}

              {activeTab === "runs" ? (
                <>
                  {isLoadingLinkedRuns ? (
                    <p className="issues-detail-copy muted">Loading runs...</p>
                  ) : null}
                  {linkedRunsError ? (
                    <p className="issues-detail-copy muted">
                      {linkedRunsError}
                    </p>
                  ) : null}
                  {linkedRuns.length ? (
                    <div className="issues-linked-run-list">
                      {linkedRuns.map(({ label, run }) => (
                        <button
                          aria-label={`Open ${label ?? "linked"} ${shortAgentRunTitle(run.id)} details`}
                          className="issues-linked-run-card"
                          key={`${label ?? "linked"}-${run.id}`}
                          onClick={() => onOpenRunDetail(run)}
                          type="button"
                        >
                          <div className="issues-linked-run-header">
                            <div className="issues-linked-run-agent">
                              <span
                                aria-hidden="true"
                                className="issues-linked-run-agent-avatar"
                              >
                                {agentInitials(issueModelLabel(issue, agents))}
                              </span>
                              <strong>{issueModelLabel(issue, agents)}</strong>
                            </div>
                            <span className="issues-linked-run-created-at">
                              {formatIssueDate(run.created_at)}
                            </span>
                          </div>
                          <div className="issues-linked-run-summary">
                            <span>{agentRunSummary(run)}</span>
                            {label ? (
                              <span className="issues-linked-run-role-pill">
                                {label}
                              </span>
                            ) : null}
                          </div>
                          <div className="issues-linked-run-meta">
                            <span className="issues-linked-run-id-pill">
                              {run.id.slice(0, 8)}
                            </span>
                            <RunStatusBadge status={run.status} />
                          </div>
                        </button>
                      ))}
                    </div>
                  ) : isLoadingLinkedRuns || linkedRunsError ? null : (
                    <p className="issues-detail-copy muted">
                      No model runs linked to this conversation yet.
                    </p>
                  )}
                </>
              ) : null}

              {activeTab === "queued" ? (
                <div className="issues-detail-subsection">
                  <div className="issues-detail-subsection-header">
                    <div className="issues-detail-subsection-copy">
                      <h3>Queued messages</h3>
                      <p className="issues-detail-copy muted">
                        Keep follow-ups attached here until you are ready to
                        open them as full conversations.
                      </p>
                    </div>
                    <button
                      className="secondary-button compact-button"
                      onClick={onQueueMessage}
                      type="button"
                    >
                      Queue message
                    </button>
                  </div>

                  {subissues.length ? (
                    <div className="surface-list dense">
                      {subissues.map((child) => (
                        <button
                          className="file-list-button"
                          key={child.id}
                          onClick={() => onOpenQueuedConversation(child.id)}
                          type="button"
                        >
                          <strong>{child.title}</strong>
                          <span>
                            {statusLabel(child.status)} ·{" "}
                            {formatCompactIssueTimestamp(child.updated_at)}
                          </span>
                        </button>
                      ))}
                    </div>
                  ) : (
                    <p className="issues-detail-copy muted">
                      No queued messages yet.
                    </p>
                  )}
                </div>
              ) : null}
            </div>
          </section>
        </section>

        {issueWorkspaceSidebar}

        {isPropertiesOpen ? (
          <>
            <button
              aria-label="Close properties sidebar"
              className="issues-properties-overlay"
              onClick={() => setIsPropertiesOpen(false)}
              type="button"
            />
            <aside
              aria-label="Conversation properties"
              className="issues-properties-drawer"
              onPointerDown={(event) => event.stopPropagation()}
              role="dialog"
            >
              <div className="issues-properties-drawer-header">
                <strong>Properties</strong>
                <button
                  aria-label="Close properties sidebar"
                  className="icon-button issues-detail-toolbar-button"
                  onClick={() => setIsPropertiesOpen(false)}
                  type="button"
                >
                  <CloseIcon />
                </button>
              </div>
              <div className="issues-properties-drawer-body">
                {visibleIssueEditorError ? (
                  <div className="issue-dialog-alert">
                    {visibleIssueEditorError}
                  </div>
                ) : null}

                <section className="issues-properties-section">
                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Status"
                    onChange={(value) =>
                      commitPropertyPatch({
                        status: value,
                      })
                    }
                    tone={normalizeBoardIssueValue(issueDraft.status)}
                    value={issueDraft.status}
                  >
                    {availableStatusOptions.map((status) => (
                      <option key={status} value={status}>
                        {statusLabel(status)}
                      </option>
                    ))}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Project"
                    onChange={(value) =>
                      commitPropertyPatch({
                        projectId: value,
                        workspaceTargetMode: "main",
                        workspaceWorktreePath: "",
                        workspaceWorktreeBranch: "",
                        workspaceWorktreeName: "",
                      })
                    }
                    tone="project"
                    value={issueDraft.projectId}
                  >
                    <option disabled value="">
                      {projects.length ? "Select project" : "Create project"}
                    </option>
                    {projects.map((project) => (
                      <option key={project.id} value={project.id}>
                        {project.name ?? project.title ?? project.id}
                      </option>
                    ))}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue || !selectedProjectRepoPath}
                    hint={workspaceTargetHint}
                    label="Worktree target"
                    onChange={(value) =>
                      commitPropertyPatch(
                        issueWorkspaceDraftPatchFromSelection(
                          value,
                          workspaceTargetWorktrees,
                          issueDraft,
                        ),
                      )
                    }
                    tone="neutral"
                    value={selectedWorkspaceTargetValue}
                  >
                    <option value="main">Repo root</option>
                    <option value="new_worktree">New git worktree</option>
                    {workspaceTargetWorktrees.map((worktree) => (
                      <option
                        key={worktree.path}
                        value={existingWorktreeTargetValue(worktree.path)}
                      >
                        {worktree.branch
                          ? `${worktree.name} · ${worktree.branch}`
                          : worktree.name}
                      </option>
                    ))}
                    {fallbackSelectedWorktree ? (
                      <option
                        value={existingWorktreeTargetValue(
                          fallbackSelectedWorktree.path,
                        )}
                      >
                        {fallbackSelectedWorktree.name}
                      </option>
                    ) : null}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Parent Conversation"
                    onChange={(value) =>
                      commitPropertyPatch({
                        parentId: value,
                      })
                    }
                    tone="neutral"
                    value={issueDraft.parentId}
                  >
                    <option value="">No parent conversation</option>
                    {selectableParentIssues.map((parentIssue) => (
                      <option key={parentIssue.id} value={parentIssue.id}>
                        {parentIssue.identifier ?? parentIssue.title}
                      </option>
                    ))}
                  </IssuePropertySelectRow>
                </section>

                <div className="issues-properties-divider" />

                <section className="issues-properties-section">
                  <h3>Model configuration</h3>
                  <div className="agent-config-grid">
                    <AgentConfigField
                      htmlFor="issue-detail-command"
                      label="Provider"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation provider"
                        id="issue-detail-command"
                        onChange={(value) =>
                          commitPropertyPatch(
                            runtimeDraftPatchForProviderSelection(
                              value,
                              issueDraft,
                              dependencyCheck,
                            ),
                          )
                        }
                        value={issueDraft.command}
                      >
                        {runtimeProviderOptions.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-model"
                      label="Model"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation model"
                        id="issue-detail-model"
                        onChange={(value) =>
                          commitPropertyPatch({ model: value })
                        }
                        value={issueDraft.model}
                      >
                        {runtimeModelOptions.map((option) => (
                          <option key={option} value={option}>
                            {option === "default" ? "Default" : option}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-thinking"
                      label="Thinking effort"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation thinking effort"
                        id="issue-detail-thinking"
                        onChange={(value) =>
                          commitPropertyPatch({ thinkingEffort: value })
                        }
                        value={issueDraft.thinkingEffort}
                      >
                        {runtimeThinkingEffortOptions.map((option) => (
                          <option key={option} value={option}>
                            {capitalize(option)}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-plan-mode"
                      label="Plan mode"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation plan mode"
                        id="issue-detail-plan-mode"
                        onChange={(value) =>
                          commitPropertyPatch({ planMode: value === "plan" })
                        }
                        value={issueDraft.planMode ? "plan" : "default"}
                      >
                        <option value="default">Off</option>
                        <option
                          disabled={runtimeProvider !== "claude"}
                          value="plan"
                        >
                          Claude plan mode
                        </option>
                      </AgentConfigSelect>
                    </AgentConfigField>
                  </div>

                  <div className="agent-config-toggle-grid">
                    <AgentConfigToggleField
                      checked={issueDraft.enableChrome}
                      description={runtimeBrowserToggleDescription}
                      label={runtimeBrowserToggleLabel}
                      onChange={(checked) =>
                        commitPropertyPatch({ enableChrome: checked })
                      }
                    />
                    <AgentConfigToggleField
                      checked={issueDraft.skipPermissions}
                      description="Let the model run without daemon approval prompts."
                      label="Skip permissions"
                      onChange={(checked) =>
                        commitPropertyPatch({ skipPermissions: checked })
                      }
                    />
                  </div>
                </section>

                <div className="issues-properties-divider" />

                <section className="issues-properties-section">
                  <IssuePropertyStaticRow
                    label="Created by"
                    value={issueCreatorLabel(issue, agents)}
                  />
                  <IssuePropertyStaticRow
                    label="Started"
                    value={
                      issue.started_at
                        ? formatBoardDate(issue.started_at)
                        : "Not started"
                    }
                  />
                  <IssuePropertyStaticRow
                    label="Completed"
                    value={
                      issue.completed_at
                        ? formatBoardDate(issue.completed_at)
                        : "Not completed"
                    }
                  />
                  <IssuePropertyStaticRow
                    label="Created"
                    value={formatBoardDate(issue.created_at)}
                  />
                  <IssuePropertyStaticRow
                    label="Updated"
                    value={formatRelativeIssueDate(issue.updated_at)}
                  />
                </section>
              </div>
            </aside>
          </>
        ) : null}
      </div>
    </section>
  );
}

function ConversationIssueDetailView({
  attachments,
  availableStatusOptions,
  dependencyCheck,
  issue,
  issueDraft,
  issueEditorError,
  issueWorkspaceSidebar,
  isSavingIssue,
  isWorking,
  onAddAttachment,
  onBack,
  onCommitIssuePatch,
  onHideIssue,
  onIssueDraftChange,
  onOpenQueuedConversation,
  onPromptChange,
  onQueueMessage,
  onRespondToQuestion,
  onRevealAttachment,
  onRevealRepo,
  onSendPrompt,
  onStopSession,
  parentIssueLabel,
  projectLabel,
  prompt,
  providerLabel,
  runtimeStatusLabel,
  session,
  sessionMessages,
  statusLabel,
  agents,
  projects,
  selectableParentIssues,
  subissues,
  workspace,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  attachments: IssueAttachmentRecord[];
  availableStatusOptions: string[];
  dependencyCheck: RuntimeCapabilities | null;
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  issueEditorError: string | null;
  issueWorkspaceSidebar?: ReactNode;
  isSavingIssue: boolean;
  isWorking: boolean;
  onAddAttachment: () => void;
  onBack: () => void;
  onCommitIssuePatch: (patch: Partial<IssueEditDraft>) => void;
  onHideIssue: () => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  onOpenQueuedConversation: (issueId: string) => void;
  onPromptChange: (value: string) => void;
  onQueueMessage: () => void;
  onRespondToQuestion: (response: string) => void;
  onRevealAttachment: (attachment: IssueAttachmentRecord) => void;
  onRevealRepo: () => void;
  onSendPrompt: (content: string) => void;
  onStopSession: () => void;
  parentIssueLabel: (parentIssueId?: string | null) => string;
  projectLabel: (projectId?: string | null) => string;
  prompt: string;
  providerLabel: string;
  runtimeStatusLabel: string;
  session: SessionRecord | null;
  sessionMessages: SessionMessage[];
  statusLabel: (value: string) => string;
  agents: AgentRecord[];
  projects: ProjectRecord[];
  selectableParentIssues: IssueRecord[];
  subissues: IssueRecord[];
  workspace: WorkspaceRecord | null;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const [isPropertiesOpen, setIsPropertiesOpen] = useState(false);
  const [isIssueActionsOpen, setIsIssueActionsOpen] = useState(false);
  const descriptionInputRef = useRef<HTMLTextAreaElement | null>(null);
  const issueActionsMenuRef = useRef<HTMLDivElement | null>(null);
  const issueActionsButtonRef = useRef<HTMLButtonElement | null>(null);

  const conversationRows = useMemo(
    () => buildConversationTimeline(sessionMessages),
    [sessionMessages],
  );
  const issueProjectName = projectLabel(issueDraft.projectId || null);
  const issueValidationMessage = issueStatusAssigneeValidationMessage(
    issueDraft.status,
    issueDraft.assigneeAgentId,
    agents,
  );
  const visibleIssueEditorError = issueValidationMessage ?? issueEditorError;
  const selectedProject =
    projects.find((project) => project.id === issueDraft.projectId) ?? null;
  const selectedProjectRepoPath =
    selectedProject?.primary_workspace?.cwd ?? null;
  const selectedWorkspaceTargetValue = issueWorkspaceTargetSelectValue(
    issueDraft.workspaceTargetMode,
    issueDraft.workspaceWorktreePath,
  );
  const workspaceTargetHint = issueWorkspaceTargetHint({
    errorMessage: workspaceTargetErrorMessage,
    hasProject: Boolean(selectedProject),
    hasRepoPath: Boolean(selectedProjectRepoPath),
    isLoading: workspaceTargetLoading,
    worktreeCount: workspaceTargetWorktrees.length,
  });
  const fallbackSelectedWorktree =
    selectedWorkspaceTargetValue.startsWith("existing:") &&
    !workspaceTargetWorktrees.some(
      (worktree) =>
        existingWorktreeTargetValue(worktree.path) ===
        selectedWorkspaceTargetValue,
    )
      ? {
          name:
            issueDraft.workspaceWorktreeName ||
            fileName(issueDraft.workspaceWorktreePath),
          path: issueDraft.workspaceWorktreePath,
        }
      : null;
  const runtimeProvider = detectAgentCliProvider(
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeModelOptions = buildAgentModelOptions(
    issueDraft,
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    issueDraft.thinkingEffort,
  );
  const runtimeProviderOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeBrowserToggleLabel =
    runtimeProvider === "codex" ? "Enable web search" : "Enable Chrome";
  const runtimeBrowserToggleDescription =
    runtimeProvider === "codex"
      ? "Expose Codex web search during runs."
      : "Allow browser automation inside Claude runs.";
  const queuedPreview = subissues.slice(0, 4);
  const hasWorkspaceSession = Boolean(workspace?.session_id);
  const isConversationLoading =
    hasWorkspaceSession && session == null && sessionMessages.length === 0;
  const issueBreadcrumbTitle = issueDraft.title.trim() || issue.title;
  const composerDisabled = isWorking || !session;

  const syncDescriptionInputHeight = () => {
    const textarea = descriptionInputRef.current;
    if (!textarea) {
      return;
    }

    textarea.style.height = "0px";
    textarea.style.height = `${textarea.scrollHeight}px`;
  };

  useLayoutEffect(() => {
    syncDescriptionInputHeight();
  }, [issue.id, issueDraft.description]);

  useEffect(() => {
    setIsPropertiesOpen(false);
    setIsIssueActionsOpen(false);
  }, [issue.id]);

  useEffect(() => {
    if (!isIssueActionsOpen) {
      return;
    }

    const closeMenu = (event: Event) => {
      const target = event.target as Node | null;
      if (
        (issueActionsMenuRef.current &&
          target &&
          issueActionsMenuRef.current.contains(target)) ||
        (issueActionsButtonRef.current &&
          target &&
          issueActionsButtonRef.current.contains(target))
      ) {
        return;
      }

      setIsIssueActionsOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsIssueActionsOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isIssueActionsOpen]);

  useEffect(() => {
    if (!isPropertiesOpen) {
      return;
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsPropertiesOpen(false);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isPropertiesOpen]);

  const commitTitleOnBlur = () => {
    const trimmedTitle = issueDraft.title.trim();
    const currentTitle = issue.title.trim();

    if (!trimmedTitle) {
      onIssueDraftChange({ title: issue.title });
      return;
    }

    if (trimmedTitle !== issueDraft.title) {
      onIssueDraftChange({ title: trimmedTitle });
    }

    if (trimmedTitle !== currentTitle) {
      onCommitIssuePatch({ title: trimmedTitle });
    }
  };

  const commitDescriptionOnBlur = () => {
    const trimmedDescription = issueDraft.description.trim();
    const currentDescription = (issue.description ?? "").trim();

    if (trimmedDescription !== issueDraft.description) {
      onIssueDraftChange({ description: trimmedDescription });
    }

    if (trimmedDescription !== currentDescription) {
      onCommitIssuePatch({ description: trimmedDescription });
    }
  };

  const commitPropertyPatch = (patch: Partial<IssueEditDraft>) => {
    onIssueDraftChange(patch);
    onCommitIssuePatch(patch);
  };

  const handleToggleProperties = () => {
    setIsIssueActionsOpen(false);
    setIsPropertiesOpen((current) => !current);
  };

  const handleToggleIssueActions = () => {
    setIsPropertiesOpen(false);
    setIsIssueActionsOpen((current) => !current);
  };

  const handleHideIssue = () => {
    setIsIssueActionsOpen(false);
    setIsPropertiesOpen(false);
    onHideIssue();
  };

  const handleSubmitPrompt = (event: FormEvent) => {
    event.preventDefault();
    if (!prompt.trim()) {
      return;
    }
    onSendPrompt(prompt);
  };

  return (
    <section className="route-scroll issues-detail-route conversation-detail-route">
      <DashboardBreadcrumbs
        items={[
          { label: "Conversations", onClick: onBack },
          { label: issueBreadcrumbTitle },
        ]}
      />

      <div className="conversation-detail-shell">
        <section className="conversation-detail-main">
          <div className="issues-detail-identity-row">
            <div className="issues-detail-identity-copy">
              <span className="issues-detail-identifier">
                {issue.identifier ?? issue.id}
              </span>
              <span className="issues-detail-project-name">
                {issueProjectName}
              </span>
            </div>
            <div className="conversation-detail-toolbar-actions">
              <button
                className="secondary-button compact-button"
                disabled={isWorking}
                onClick={onAddAttachment}
                type="button"
              >
                Add attachment
              </button>
              {workspace?.workspace_repo_path ? (
                <button
                  className="secondary-button compact-button"
                  onClick={onRevealRepo}
                  type="button"
                >
                  Reveal repo
                </button>
              ) : null}
              {session ? (
                <button
                  className="secondary-button compact-button"
                  onClick={onStopSession}
                  type="button"
                >
                  Stop {providerLabel}
                </button>
              ) : null}
              <button
                aria-label={
                  isPropertiesOpen
                    ? "Close properties sidebar"
                    : "Open properties sidebar"
                }
                className={
                  isPropertiesOpen
                    ? "icon-button issues-detail-toolbar-button active"
                    : "icon-button issues-detail-toolbar-button"
                }
                onClick={handleToggleProperties}
                type="button"
              >
                <SlidersHorizontalIcon />
              </button>
              <div className="issues-detail-toolbar-menu-shell">
                <button
                  aria-expanded={isIssueActionsOpen}
                  aria-haspopup="menu"
                  aria-label="Conversation actions"
                  className={
                    isIssueActionsOpen
                      ? "icon-button issues-detail-toolbar-button active"
                      : "icon-button issues-detail-toolbar-button"
                  }
                  onClick={handleToggleIssueActions}
                  ref={issueActionsButtonRef}
                  type="button"
                >
                  <EllipsisHorizontalIcon />
                </button>
                {isIssueActionsOpen ? (
                  <div
                    className="issues-detail-toolbar-menu"
                    onPointerDown={(event) => event.stopPropagation()}
                    ref={issueActionsMenuRef}
                    role="menu"
                  >
                    <button
                      className="issues-detail-toolbar-menu-item"
                      disabled={isSavingIssue}
                      onClick={handleHideIssue}
                      role="menuitem"
                      type="button"
                    >
                      Hide this conversation
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          </div>

          <div className="conversation-detail-header-card">
            <div className="conversation-detail-title-stack">
              <input
                className="issues-inline-title-input conversation-detail-title-input"
                onBlur={commitTitleOnBlur}
                onChange={(event) =>
                  onIssueDraftChange({
                    title: event.target.value,
                  })
                }
                placeholder="Conversation title"
                value={issueDraft.title}
              />
              <textarea
                className="issues-inline-description-input conversation-detail-description-input"
                onBlur={commitDescriptionOnBlur}
                onChange={(event) =>
                  onIssueDraftChange({
                    description: event.target.value,
                  })
                }
                onInput={syncDescriptionInputHeight}
                placeholder="Add context, decisions, or the next thing a model should pick up."
                ref={descriptionInputRef}
                rows={1}
                value={issueDraft.description}
              />
              <div className="conversation-detail-meta-row">
                <span className="issues-detail-copy muted">
                  Parent {parentIssueLabel(issue.parent_id)} · Created by{" "}
                  {issueCreatorLabel(issue, agents)} · Updated{" "}
                  {formatRelativeIssueDate(issue.updated_at)}
                </span>
                {isSavingIssue ? (
                  <span className="issues-detail-inline-saving">Saving…</span>
                ) : null}
              </div>
            </div>

            <div className="conversation-detail-summary-grid">
              <SummaryPill label="Status" value={statusLabel(issue.status)} />
              <SummaryPill
                label="Project"
                value={projectLabel(issue.project_id)}
              />
              <SummaryPill label="Agent" value={providerLabel} />
              <SummaryPill label="Runtime" value={runtimeStatusLabel} />
              <SummaryPill label="Attachments" value={attachments.length} />
              <SummaryPill label="Queued" value={subissues.length} />
            </div>
          </div>

          {visibleIssueEditorError ? (
            <div className="issue-dialog-alert">{visibleIssueEditorError}</div>
          ) : null}

          <div className="conversation-detail-utility-grid">
            <section className="conversation-support-card">
              <div className="conversation-support-card-header">
                <div>
                  <h3>Attached context</h3>
                  <p className="issues-detail-copy muted">
                    Files stored with the board issue and available to future
                    runs.
                  </p>
                </div>
                <button
                  className="secondary-button compact-button"
                  disabled={isWorking}
                  onClick={onAddAttachment}
                  type="button"
                >
                  Add
                </button>
              </div>

              {attachments.length ? (
                <div className="conversation-attachment-list">
                  {attachments.map((attachment) => (
                    <button
                      className="conversation-attachment-chip"
                      key={attachment.id}
                      onClick={() => onRevealAttachment(attachment)}
                      type="button"
                    >
                      <strong>
                        {attachment.original_filename ??
                          fileName(attachment.local_path)}
                      </strong>
                      <span>
                        {formatFileSize(attachment.byte_size)} ·{" "}
                        {formatIssueDate(attachment.created_at)}
                      </span>
                    </button>
                  ))}
                </div>
              ) : (
                <p className="issues-detail-copy muted">No attachments yet.</p>
              )}
            </section>

            <section className="conversation-support-card">
              <div className="conversation-support-card-header">
                <div>
                  <h3>Queued follow-ups</h3>
                  <p className="issues-detail-copy muted">
                    Lightweight child conversations that are still attached
                    here.
                  </p>
                </div>
                <button
                  className="secondary-button compact-button"
                  onClick={onQueueMessage}
                  type="button"
                >
                  Queue
                </button>
              </div>

              {queuedPreview.length ? (
                <div className="conversation-queued-list">
                  {queuedPreview.map((child) => (
                    <button
                      className="conversation-queued-row"
                      key={child.id}
                      onClick={() => onOpenQueuedConversation(child.id)}
                      type="button"
                    >
                      <strong>{child.title}</strong>
                      <span>
                        {statusLabel(child.status)} ·{" "}
                        {formatCompactIssueTimestamp(child.updated_at)}
                      </span>
                    </button>
                  ))}
                </div>
              ) : (
                <p className="issues-detail-copy muted">
                  No queued follow-ups.
                </p>
              )}
            </section>
          </div>

          <section className="conversation-timeline-panel">
            <div className="conversation-timeline-panel-header">
              <div>
                <span className="route-kicker">Daemon Conversation</span>
                <h2>
                  {session?.title ??
                    (issueDraft.title.trim() || "Conversation")}
                </h2>
                <p className="issues-detail-copy muted">
                  {session
                    ? `${conversationRows.length} rendered rows · session ${session.id.slice(0, 8)}`
                    : hasWorkspaceSession
                      ? "Waiting for the workspace session to attach."
                      : "This conversation does not have an active daemon workspace yet."}
                </p>
              </div>
            </div>

            {isConversationLoading ? (
              <div className="conversation-empty-state">
                <h3>Loading daemon conversation…</h3>
                <p>
                  The issue already has a workspace session. The transcript will
                  appear once the session state finishes hydrating.
                </p>
              </div>
            ) : hasWorkspaceSession ? (
              conversationRows.length ? (
                <div className="conversation-timeline-scroll">
                  <ConversationTimeline
                    onRespondToQuestion={onRespondToQuestion}
                    rows={conversationRows}
                  />
                </div>
              ) : (
                <div className="conversation-empty-state">
                  <h3>No daemon messages yet</h3>
                  <p>
                    Send the first prompt below to start the workspace
                    transcript for this conversation.
                  </p>
                </div>
              )
            ) : (
              <div className="conversation-empty-state">
                <h3>No workspace session</h3>
                <p>
                  This issue does not have a checked-out daemon workspace, so
                  there is no live transcript, file tree, or git history to show
                  yet.
                </p>
              </div>
            )}

            {hasWorkspaceSession ? (
              <form
                className="conversation-composer"
                onSubmit={handleSubmitPrompt}
              >
                <textarea
                  className="conversation-composer-input"
                  disabled={composerDisabled}
                  onChange={(event) => onPromptChange(event.target.value)}
                  placeholder={`Send a prompt to ${providerLabel}`}
                  rows={3}
                  value={prompt}
                />
                <div className="conversation-composer-footer">
                  <span className="issues-detail-copy muted">
                    Replies, tool calls, sub-agents, and code changes stream
                    from the daemon session.
                  </span>
                  <button
                    className="primary-button"
                    disabled={composerDisabled || !prompt.trim()}
                    type="submit"
                  >
                    Send prompt
                  </button>
                </div>
              </form>
            ) : null}
          </section>
        </section>

        {issueWorkspaceSidebar ? (
          issueWorkspaceSidebar
        ) : (
          <aside className="conversation-detail-empty-sidebar">
            <section className="inspector-panel workspace-details-panel">
              <h3>Workspace Inspector</h3>
              <p className="issues-detail-copy muted">
                Changes, files, and commits appear here once this conversation
                has an attached daemon workspace.
              </p>
              <div className="workspace-detail-grid">
                <DetailRow label="Status" value={statusLabel(issue.status)} />
                <DetailRow
                  label="Project"
                  value={projectLabel(issue.project_id)}
                />
                <DetailRow
                  label="Parent"
                  value={parentIssueLabel(issue.parent_id)}
                />
                <DetailRow
                  label="Updated"
                  value={formatRelativeIssueDate(issue.updated_at)}
                />
              </div>
            </section>
          </aside>
        )}

        {isPropertiesOpen ? (
          <>
            <button
              aria-label="Close properties sidebar"
              className="issues-properties-overlay"
              onClick={() => setIsPropertiesOpen(false)}
              type="button"
            />
            <aside
              aria-label="Conversation properties"
              className="issues-properties-drawer"
              onPointerDown={(event) => event.stopPropagation()}
              role="dialog"
            >
              <div className="issues-properties-drawer-header">
                <strong>Properties</strong>
                <button
                  aria-label="Close properties sidebar"
                  className="icon-button issues-detail-toolbar-button"
                  onClick={() => setIsPropertiesOpen(false)}
                  type="button"
                >
                  <CloseIcon />
                </button>
              </div>
              <div className="issues-properties-drawer-body">
                {visibleIssueEditorError ? (
                  <div className="issue-dialog-alert">
                    {visibleIssueEditorError}
                  </div>
                ) : null}

                <section className="issues-properties-section">
                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Status"
                    onChange={(value) =>
                      commitPropertyPatch({
                        status: value,
                      })
                    }
                    tone={normalizeBoardIssueValue(issueDraft.status)}
                    value={issueDraft.status}
                  >
                    {availableStatusOptions.map((status) => (
                      <option key={status} value={status}>
                        {statusLabel(status)}
                      </option>
                    ))}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Project"
                    onChange={(value) =>
                      commitPropertyPatch({
                        projectId: value,
                        workspaceTargetMode: "main",
                        workspaceWorktreePath: "",
                        workspaceWorktreeBranch: "",
                        workspaceWorktreeName: "",
                      })
                    }
                    tone="project"
                    value={issueDraft.projectId}
                  >
                    <option disabled value="">
                      {projects.length ? "Select project" : "Create project"}
                    </option>
                    {projects.map((project) => (
                      <option key={project.id} value={project.id}>
                        {project.name ?? project.title ?? project.id}
                      </option>
                    ))}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue || !selectedProjectRepoPath}
                    hint={workspaceTargetHint}
                    label="Worktree target"
                    onChange={(value) =>
                      commitPropertyPatch(
                        issueWorkspaceDraftPatchFromSelection(
                          value,
                          workspaceTargetWorktrees,
                          issueDraft,
                        ),
                      )
                    }
                    tone="neutral"
                    value={selectedWorkspaceTargetValue}
                  >
                    <option value="main">Repo root</option>
                    <option value="new_worktree">New git worktree</option>
                    {workspaceTargetWorktrees.map((worktree) => (
                      <option
                        key={worktree.path}
                        value={existingWorktreeTargetValue(worktree.path)}
                      >
                        {worktree.branch
                          ? `${worktree.name} · ${worktree.branch}`
                          : worktree.name}
                      </option>
                    ))}
                    {fallbackSelectedWorktree ? (
                      <option
                        value={existingWorktreeTargetValue(
                          fallbackSelectedWorktree.path,
                        )}
                      >
                        {fallbackSelectedWorktree.name}
                      </option>
                    ) : null}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Parent Conversation"
                    onChange={(value) =>
                      commitPropertyPatch({
                        parentId: value,
                      })
                    }
                    tone="neutral"
                    value={issueDraft.parentId}
                  >
                    <option value="">No parent conversation</option>
                    {selectableParentIssues.map((parentIssue) => (
                      <option key={parentIssue.id} value={parentIssue.id}>
                        {parentIssue.identifier ?? parentIssue.title}
                      </option>
                    ))}
                  </IssuePropertySelectRow>
                </section>

                <div className="issues-properties-divider" />

                <section className="issues-properties-section">
                  <h3>Model configuration</h3>
                  <div className="agent-config-grid">
                    <AgentConfigField
                      htmlFor="issue-detail-command"
                      label="Provider"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation provider"
                        id="issue-detail-command"
                        onChange={(value) =>
                          commitPropertyPatch(
                            runtimeDraftPatchForProviderSelection(
                              value,
                              issueDraft,
                              dependencyCheck,
                            ),
                          )
                        }
                        value={issueDraft.command}
                      >
                        {runtimeProviderOptions.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-model"
                      label="Model"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation model"
                        id="issue-detail-model"
                        onChange={(value) =>
                          commitPropertyPatch({ model: value })
                        }
                        value={issueDraft.model}
                      >
                        {runtimeModelOptions.map((option) => (
                          <option key={option} value={option}>
                            {option === "default" ? "Default" : option}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-thinking"
                      label="Thinking effort"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation thinking effort"
                        id="issue-detail-thinking"
                        onChange={(value) =>
                          commitPropertyPatch({ thinkingEffort: value })
                        }
                        value={issueDraft.thinkingEffort}
                      >
                        {runtimeThinkingEffortOptions.map((option) => (
                          <option key={option} value={option}>
                            {capitalize(option)}
                          </option>
                        ))}
                      </AgentConfigSelect>
                    </AgentConfigField>

                    <AgentConfigField
                      htmlFor="issue-detail-plan-mode"
                      label="Plan mode"
                    >
                      <AgentConfigSelect
                        ariaLabel="Conversation plan mode"
                        id="issue-detail-plan-mode"
                        onChange={(value) =>
                          commitPropertyPatch({ planMode: value === "plan" })
                        }
                        value={issueDraft.planMode ? "plan" : "default"}
                      >
                        <option value="default">Off</option>
                        <option
                          disabled={runtimeProvider !== "claude"}
                          value="plan"
                        >
                          Claude plan mode
                        </option>
                      </AgentConfigSelect>
                    </AgentConfigField>
                  </div>

                  <div className="agent-config-toggle-grid">
                    <AgentConfigToggleField
                      checked={issueDraft.enableChrome}
                      description={runtimeBrowserToggleDescription}
                      label={runtimeBrowserToggleLabel}
                      onChange={(checked) =>
                        commitPropertyPatch({ enableChrome: checked })
                      }
                    />
                    <AgentConfigToggleField
                      checked={issueDraft.skipPermissions}
                      description="Let the model run without daemon approval prompts."
                      label="Skip permissions"
                      onChange={(checked) =>
                        commitPropertyPatch({ skipPermissions: checked })
                      }
                    />
                  </div>
                </section>

                <div className="issues-properties-divider" />

                <section className="issues-properties-section">
                  <IssuePropertyStaticRow
                    label="Created by"
                    value={issueCreatorLabel(issue, agents)}
                  />
                  <IssuePropertyStaticRow
                    label="Started"
                    value={
                      issue.started_at
                        ? formatBoardDate(issue.started_at)
                        : "Not started"
                    }
                  />
                  <IssuePropertyStaticRow
                    label="Completed"
                    value={
                      issue.completed_at
                        ? formatBoardDate(issue.completed_at)
                        : "Not completed"
                    }
                  />
                  <IssuePropertyStaticRow
                    label="Created"
                    value={formatBoardDate(issue.created_at)}
                  />
                  <IssuePropertyStaticRow
                    label="Updated"
                    value={formatRelativeIssueDate(issue.updated_at)}
                  />
                </section>
              </div>
            </aside>
          </>
        ) : null}
      </div>
    </section>
  );
}

export function IssueWorkspaceDetailView({
  agents,
  availableStatusOptions,
  dependencyCheck,
  embedded = false,
  issue,
  issueDraft,
  issueEditorError,
  issueWorkspaceSidebar,
  isSavingIssue,
  isWorking,
  onBack,
  onAddAttachment,
  onCommitIssuePatch,
  onIssueDraftChange,
  onPromptChange,
  onRespondToQuestion,
  onRevealRepo,
  onRunTerminal,
  onTerminalCommandChange,
  onSelectWorkspaceCenterTab,
  onSendPrompt,
  onStopSession,
  onStopTerminal,
  previewTabLabel,
  projectLabel,
  projects,
  prompt,
  selectableParentIssues,
  selectedDiff,
  selectedFile,
  selectedFilePath,
  session,
  sessionErrorMessage,
  sessionLoading,
  latestCompletionSummary,
  sessionRows,
  statusLabel,
  runtimeStatusValue,
  terminalCommand,
  terminalContainerRef,
  terminalStatusValue,
  workspace,
  workspaceCenterTab,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  agents: AgentRecord[];
  availableStatusOptions: string[];
  dependencyCheck: RuntimeCapabilities | null;
  embedded?: boolean;
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  issueEditorError: string | null;
  issueWorkspaceSidebar?: ReactNode;
  isSavingIssue: boolean;
  isWorking: boolean;
  onBack: () => void;
  onAddAttachment: () => void;
  onCommitIssuePatch: (patch: Partial<IssueEditDraft>) => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  onPromptChange: (value: string) => void;
  onRespondToQuestion: (response: string) => void;
  onRevealRepo: () => void;
  onRunTerminal: (event: FormEvent) => void;
  onTerminalCommandChange: (value: string) => void;
  onSelectWorkspaceCenterTab: (tab: WorkspaceCenterTab) => void;
  onSendPrompt: (content: string) => void;
  onStopSession: () => void;
  onStopTerminal: () => void;
  previewTabLabel: string;
  projectLabel: (projectId?: string | null) => string;
  projects: ProjectRecord[];
  prompt: string;
  selectableParentIssues: IssueRecord[];
  selectedDiff: GitDiffResult | null;
  selectedFile: FileReadResult | null;
  selectedFilePath: string | null;
  session: SessionRecord | null;
  sessionErrorMessage: string | null;
  sessionLoading: boolean;
  latestCompletionSummary: SessionCompletionSummary | null;
  sessionRows: SessionConversationRow[];
  statusLabel: (value: string) => string;
  runtimeStatusValue: string;
  terminalCommand: string;
  terminalContainerRef: RefObject<HTMLDivElement | null>;
  terminalStatusValue: string;
  workspace: WorkspaceRecord | null;
  workspaceCenterTab: WorkspaceCenterTab;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const issueProjectName = projectLabel(
    issueDraft.projectId || issue.project_id,
  );
  const issueBreadcrumbTitle = issueDraft.title.trim() || issue.title;
  const hasWorkspaceSession = Boolean(workspace?.session_id);
  const isConversationLoading = sessionLoading && sessionRows.length === 0;
  const composerDisabled = !session;
  const effectiveWorkspaceCenterTab =
    workspaceCenterTab === "runs" ? "conversation" : workspaceCenterTab;
  const runtimeProvider = detectAgentCliProvider(
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeProviderOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    issueDraft.command,
    issueDraft.model,
  );
  const runtimeModelOptions = buildAgentModelOptions(
    issueDraft,
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    issueDraft.thinkingEffort,
  );
  const isSessionStreaming = runtimeStatusValue === "running";
  const isSessionAwaitingInput = runtimeStatusValue === "waiting";
  const runtimeTone = workspaceRuntimeTone(
    runtimeStatusValue,
    sessionErrorMessage,
  );

  const commitRuntimePatch = (patch: Partial<IssueEditDraft>) => {
    onIssueDraftChange(patch);
    onCommitIssuePatch(patch);
  };

  const handleSendPromptFromComposer = () => {
    if (!prompt.trim()) {
      return;
    }
    onSendPrompt(prompt);
  };

  return (
    <section
      className={
        embedded
          ? "issues-detail-route conversation-detail-route issues-detail-route-embedded"
          : "route-scroll issues-detail-route conversation-detail-route"
      }
    >
      {embedded ? null : (
        <DashboardBreadcrumbs
          items={[
            { label: "Conversations", onClick: onBack },
            { label: issueBreadcrumbTitle },
          ]}
        />
      )}

      <div className="conversation-detail-shell workspace-issue-detail-shell">
        <main className="workspace-center">
          {workspace ? (
            <>
              <div className="workspace-center-header">
                <div className="workspace-tab-strip">
                  <WorkspaceCenterTabButton
                    active={effectiveWorkspaceCenterTab === "conversation"}
                    label={
                      session?.title ?? (issueDraft.title.trim() || issue.title)
                    }
                    onClick={() => onSelectWorkspaceCenterTab("conversation")}
                  />
                  <WorkspaceCenterTabButton
                    active={effectiveWorkspaceCenterTab === "terminal"}
                    label="Terminal"
                    onClick={() => onSelectWorkspaceCenterTab("terminal")}
                  />
                  {selectedFilePath ? (
                    <WorkspaceCenterTabButton
                      active={effectiveWorkspaceCenterTab === "preview"}
                      label={previewTabLabel}
                      onClick={() => onSelectWorkspaceCenterTab("preview")}
                    />
                  ) : null}
                </div>
              </div>

              {effectiveWorkspaceCenterTab === "conversation" ? (
                <section className="workspace-panel workspace-chat-panel workspace-conversation-panel">
                  <WorkspaceSessionHeaderCard
                    agentLabel={
                      issueAssigneeLabel(
                        agents,
                        issueDraft.assigneeAgentId || issue.assignee_agent_id,
                      ) ||
                      providerLabelForRuntimeConfig(
                        issueDraft.command,
                        issueDraft.model,
                      )
                    }
                    issueLabel={issueDraft.title.trim() || issue.title}
                    renderedCount={sessionRows.length}
                    sessionId={session?.id ?? null}
                    title={
                      session?.title ?? (issueDraft.title.trim() || issue.title)
                    }
                  />

                  {isConversationLoading ? (
                    <div className="conversation-empty-state">
                      <h3>Loading conversation…</h3>
                      <p>The daemon session is hydrating its transcript.</p>
                    </div>
                  ) : sessionRows.length ? (
                    <div className="conversation-timeline-scroll">
                      <SessionConversationTimeline
                        onRespondToQuestion={onRespondToQuestion}
                        rows={sessionRows}
                      />
                    </div>
                  ) : (
                    <div className="conversation-empty-state">
                      <h3>No daemon messages yet</h3>
                      <p>
                        Send the first prompt below to start the workspace
                        transcript.
                      </p>
                    </div>
                  )}

                  <WorkspaceRuntimeStatusLine
                    detail={sessionErrorMessage}
                    status={runtimeStatusValue}
                    tone={runtimeTone}
                  />

                  <WorkspaceChatComposer
                    disabled={composerDisabled}
                    isAwaitingInput={isSessionAwaitingInput}
                    isPlanMode={issueDraft.planMode}
                    isStreaming={isSessionStreaming}
                    latestCompletionSummary={latestCompletionSummary}
                    modelOptions={runtimeModelOptions}
                    onAddAttachment={onAddAttachment}
                    onCancel={session ? onStopSession : undefined}
                    onChange={onPromptChange}
                    onModelChange={(value) =>
                      commitRuntimePatch({ model: value })
                    }
                    onPlanModeChange={(value) =>
                      commitRuntimePatch({
                        planMode: runtimeProvider === "claude" ? value : false,
                      })
                    }
                    onProviderChange={(value) =>
                      commitRuntimePatch(
                        runtimeDraftPatchForProviderSelection(
                          value,
                          issueDraft,
                          dependencyCheck,
                        ),
                      )
                    }
                    onSend={handleSendPromptFromComposer}
                    onThinkingEffortChange={(value) =>
                      commitRuntimePatch({ thinkingEffort: value })
                    }
                    providerOptions={runtimeProviderOptions}
                    selectedModel={issueDraft.model}
                    selectedProvider={issueDraft.command}
                    selectedThinkingEffort={issueDraft.thinkingEffort}
                    thinkingEffortOptions={runtimeThinkingEffortOptions}
                    value={prompt}
                  />
                </section>
              ) : null}

              {effectiveWorkspaceCenterTab === "terminal" ? (
                <section className="workspace-panel workspace-chat-panel">
                  <div className="workspace-panel-header">
                    <h3>Terminal</h3>
                    <button
                      className="secondary-button"
                      onClick={onStopTerminal}
                      type="button"
                    >
                      Stop
                    </button>
                  </div>
                  <div className="terminal-frame" ref={terminalContainerRef} />
                  <form
                    className="workspace-terminal-form"
                    onSubmit={onRunTerminal}
                  >
                    <input
                      onChange={(event) =>
                        onTerminalCommandChange(event.target.value)
                      }
                      placeholder="Run a shell command in the selected session"
                      value={terminalCommand}
                    />
                    <button
                      className="primary-button"
                      disabled={isWorking}
                      type="submit"
                    >
                      Run
                    </button>
                  </form>
                </section>
              ) : null}

              {effectiveWorkspaceCenterTab === "preview" ? (
                <section className="workspace-panel workspace-chat-panel">
                  <div className="workspace-panel-header">
                    <div>
                      <span className="route-kicker">
                        {selectedDiff ? "Diff preview" : "File preview"}
                      </span>
                      <h1>{selectedFilePath ?? "Preview"}</h1>
                    </div>
                  </div>
                  {selectedDiff ? (
                    <div className="workspace-preview">
                      <div className="summary-grid">
                        <SummaryPill
                          label="Added"
                          value={selectedDiff.additions}
                        />
                        <SummaryPill
                          label="Deleted"
                          value={selectedDiff.deletions}
                        />
                        <SummaryPill
                          label="Binary"
                          value={selectedDiff.is_binary ? "yes" : "no"}
                        />
                      </div>
                      <pre>{selectedDiff.diff}</pre>
                    </div>
                  ) : selectedFile ? (
                    <div className="workspace-preview">
                      <pre>{selectedFile.content}</pre>
                    </div>
                  ) : (
                    <p>Select a file or change to preview it here.</p>
                  )}
                </section>
              ) : null}
            </>
          ) : (
            <section className="workspace-empty-state workspace-center-empty">
              <h3>Creating workspace…</h3>
              <p>
                This issue always runs from a workspace. The daemon is still
                attaching the repo root or git worktree for this issue.
              </p>
            </section>
          )}
        </main>

        {issueWorkspaceSidebar ? (
          issueWorkspaceSidebar
        ) : embedded ? null : (
          <aside className="conversation-detail-empty-sidebar">
            <section className="inspector-panel workspace-details-panel">
              <h3>Workspace Inspector</h3>
              <p className="issues-detail-copy muted">
                The issue workspace sidebar appears once the daemon attaches the
                worktree.
              </p>
            </section>
          </aside>
        )}
      </div>
    </section>
  );
}

function SessionConversationTimeline({
  onRespondToQuestion,
  rows,
}: {
  onRespondToQuestion: (response: string) => void;
  rows: SessionConversationRow[];
}) {
  return (
    <div className="conversation-timeline">
      {rows.map((row) => (
        <SessionConversationRowView
          key={row.id}
          onRespondToQuestion={onRespondToQuestion}
          row={row}
        />
      ))}
    </div>
  );
}

function SessionConversationRowView({
  onRespondToQuestion,
  row,
}: {
  onRespondToQuestion: (response: string) => void;
  row: SessionConversationRow;
}) {
  const isUser = row.role === "user";

  return (
    <article
      className={
        isUser
          ? "conversation-row conversation-row-user"
          : row.role === "system" || row.role === "result"
            ? "conversation-row conversation-row-system"
            : "conversation-row"
      }
    >
      <div className="conversation-row-content">
        {row.blocks.map((block) => {
          if (block.kind === "text") {
            return (
              <ConversationTextBlockView key={block.id} text={block.text} />
            );
          }
          if (block.kind === "error") {
            return (
              <div className="conversation-error-card" key={block.id}>
                {block.message}
              </div>
            );
          }
          if (block.kind === "todo") {
            return (
              <ConversationTodoListCard
                items={block.todoList.items}
                key={block.id}
              />
            );
          }
          if (block.kind === "tool") {
            return <ConversationToolCard key={block.id} tool={block.tool} />;
          }
          if (block.kind === "subagent") {
            return (
              <ConversationSubAgentCard
                activity={block.activity}
                key={block.id}
              />
            );
          }
          if (block.kind === "question") {
            return (
              <ConversationQuestionCard
                key={block.id}
                onSubmit={onRespondToQuestion}
                question={block.question}
              />
            );
          }
          if (block.kind === "command") {
            return (
              <SessionConversationCommandCard block={block} key={block.id} />
            );
          }
          if (block.kind === "note") {
            return <SessionConversationNoteCard block={block} key={block.id} />;
          }
          if (block.kind === "compactBoundary") {
            return (
              <SessionConversationNoteCard
                block={{
                  id: block.id,
                  kicker: "Boundary",
                  kind: "note",
                  meta: [],
                  text: block.text,
                  tone: "neutral",
                }}
                key={block.id}
              />
            );
          }
          if (block.kind === "result") {
            return (
              <SessionConversationNoteCard
                block={{
                  id: block.id,
                  kicker: "Result",
                  kind: "note",
                  meta: block.meta,
                  text: block.text,
                  tone: block.tone,
                }}
                key={block.id}
              />
            );
          }
          return null;
        })}
      </div>
    </article>
  );
}

export function WorkspaceSessionHeaderCard({
  agentLabel,
  issueLabel,
  onPrimaryAction,
  onRevealRepo,
  onStopSession,
  primaryActionLabel,
  renderedCount,
  sessionId,
  title,
}: {
  agentLabel: string;
  issueLabel: string;
  onPrimaryAction?: (() => void) | undefined;
  onRevealRepo?: (() => void) | undefined;
  onStopSession?: (() => void) | undefined;
  primaryActionLabel?: string | undefined;
  renderedCount: number;
  sessionId: string | null;
  title: string;
}) {
  return (
    <div className="workspace-session-header-card">
      <div className="workspace-session-header-copy">
        <strong>{title}</strong>
        {agentLabel ? (
          <span className="workspace-session-header-meta">{agentLabel}</span>
        ) : null}
        {issueLabel && issueLabel !== title ? (
          <span className="workspace-session-header-meta">{issueLabel}</span>
        ) : null}
        {sessionId ? (
          <span className="workspace-session-header-id">{sessionId}</span>
        ) : null}
      </div>

      <div className="workspace-session-header-actions">
        {onPrimaryAction && primaryActionLabel ? (
          <button
            className="secondary-button compact-button"
            onClick={onPrimaryAction}
            type="button"
          >
            {primaryActionLabel}
          </button>
        ) : onStopSession ? (
          <button
            className="secondary-button compact-button"
            onClick={onStopSession}
            type="button"
          >
            Stop
          </button>
        ) : null}
        {onRevealRepo ? (
          <button
            className="secondary-button compact-button"
            onClick={onRevealRepo}
            type="button"
          >
            Reveal repo
          </button>
        ) : null}
        <div className="workspace-session-header-count">
          <span>Rendered</span>
          <strong>{renderedCount}</strong>
        </div>
      </div>
    </div>
  );
}

export function WorkspaceRuntimeStatusLine({
  detail,
  status,
  tone,
}: {
  detail?: string | null;
  status: string;
  tone: "error" | "idle" | "running" | "waiting";
}) {
  return (
    <div className={`workspace-runtime-line ${tone}`}>
      <span className="workspace-runtime-line-dot" />
      <span>{status}</span>
      {detail ? (
        <span className="workspace-runtime-line-detail">{detail}</span>
      ) : null}
    </div>
  );
}

export function WorkspaceChatComposer({
  disabled,
  isAwaitingInput = false,
  isPlanMode,
  isStreaming,
  latestCompletionSummary,
  modelOptions,
  onAddAttachment,
  onCancel,
  onChange,
  onModelChange,
  onPlanModeChange,
  onProviderChange,
  onSend,
  onThinkingEffortChange,
  providerOptions = [],
  selectedModel,
  selectedProvider,
  selectedThinkingEffort,
  thinkingEffortOptions,
  value,
}: {
  disabled: boolean;
  isAwaitingInput?: boolean;
  isPlanMode: boolean;
  isStreaming: boolean;
  latestCompletionSummary?: SessionCompletionSummary | null;
  modelOptions: string[];
  onAddAttachment?: (() => void) | undefined;
  onCancel?: (() => void) | undefined;
  onChange: (value: string) => void;
  onModelChange: (value: string) => void;
  onPlanModeChange: (value: boolean) => void;
  onProviderChange?: ((value: string) => void) | undefined;
  onSend: () => void;
  onThinkingEffortChange: (value: string) => void;
  providerOptions?: Array<{ label: string; value: string }>;
  selectedModel: string;
  selectedProvider?: string | null;
  selectedThinkingEffort: string;
  thinkingEffortOptions: string[];
  value: string;
}) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const composerRef = useRef<HTMLFormElement | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);
  const trimmedValue = value.trim();
  const isCompact = !isExpanded && trimmedValue.length === 0;
  const planModeAvailable =
    detectAgentCliProvider(selectedProvider, selectedModel) === "claude";
  const completionMetrics = formatSessionCompletionMetrics(
    latestCompletionSummary ?? null,
  );

  useEffect(() => {
    if (trimmedValue.length > 0) {
      setIsExpanded(true);
    }
  }, [trimmedValue]);

  useEffect(() => {
    if (!isCompact) {
      inputRef.current?.focus();
    }
  }, [isCompact]);

  useEffect(() => {
    if (!isMenuOpen) {
      return;
    }

    const closeMenu = (event: Event) => {
      const target = event.target as Node | null;
      if (target && composerRef.current?.contains(target)) {
        return;
      }
      setIsMenuOpen(false);
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setIsMenuOpen(false);
      }
    };

    document.addEventListener("pointerdown", closeMenu);
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("pointerdown", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [isMenuOpen]);

  const handleBlur = () => {
    requestAnimationFrame(() => {
      const activeElement = document.activeElement;
      if (
        trimmedValue.length === 0 &&
        !(activeElement && composerRef.current?.contains(activeElement))
      ) {
        setIsExpanded(false);
        setIsMenuOpen(false);
      }
    });
  };

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    if (disabled) {
      return;
    }
    if (isStreaming && !isAwaitingInput) {
      onCancel?.();
      return;
    }
    if (trimmedValue.length === 0) {
      return;
    }
    onSend();
  };

  const handleInputKeyDown = (
    event: ReactKeyboardEvent<HTMLTextAreaElement>,
  ) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault();
      if (
        !(disabled || (isStreaming && !isAwaitingInput)) &&
        trimmedValue.length > 0
      ) {
        onSend();
      }
      return;
    }

    if (event.shiftKey && event.key === "Tab") {
      event.preventDefault();
      if (planModeAvailable) {
        onPlanModeChange(!isPlanMode);
      }
    }
  };

  return (
    <form
      className={
        isCompact
          ? "workspace-chat-composer is-compact"
          : isPlanMode
            ? "workspace-chat-composer is-expanded is-plan"
            : "workspace-chat-composer is-expanded"
      }
      onClick={() => {
        if (!disabled && isCompact) {
          setIsExpanded(true);
        }
      }}
      onSubmit={handleSubmit}
      ref={composerRef}
    >
      {!isCompact && isPlanMode ? (
        <div className="workspace-chat-composer-plan">
          <span className="workspace-chat-composer-plan-icon">⌘</span>
          <span>
            Plan mode — Claude will create a plan before making changes
          </span>
        </div>
      ) : null}

      {isCompact ? (
        <div className="workspace-chat-composer-compact-copy">
          What do you want to build?
        </div>
      ) : (
        <textarea
          className="workspace-chat-composer-input"
          disabled={disabled}
          onBlur={handleBlur}
          onChange={(event) => onChange(event.target.value)}
          onFocus={() => setIsExpanded(true)}
          onKeyDown={handleInputKeyDown}
          placeholder="What do you want to build?"
          ref={inputRef}
          rows={3}
          value={value}
        />
      )}

      <div className="workspace-chat-composer-toolbar">
        <div className="workspace-chat-composer-controls">
          {isCompact ? (
            <span className="workspace-chat-composer-compact-spacer" />
          ) : (
            <>
              {providerOptions.length > 0 && onProviderChange ? (
                <WorkspaceChatComposerSelect
                  ariaLabel="Conversation provider"
                  disabled={disabled}
                  onChange={onProviderChange}
                  value={
                    selectedProvider ?? providerOptions[0]?.value ?? "claude"
                  }
                >
                  {providerOptions.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </WorkspaceChatComposerSelect>
              ) : null}

              <WorkspaceChatComposerSelect
                ariaLabel="Conversation model"
                disabled={disabled}
                onChange={onModelChange}
                value={selectedModel}
              >
                {modelOptions.map((option) => (
                  <option key={option} value={option}>
                    {option === "default" ? "Default" : option}
                  </option>
                ))}
              </WorkspaceChatComposerSelect>

              <WorkspaceChatComposerSelect
                ariaLabel="Conversation thinking effort"
                disabled={disabled}
                onChange={onThinkingEffortChange}
                value={selectedThinkingEffort}
              >
                {thinkingEffortOptions.map((option) => (
                  <option key={option} value={option}>
                    {capitalize(option)}
                  </option>
                ))}
              </WorkspaceChatComposerSelect>

              <div className="workspace-chat-composer-trailing">
                <div className="workspace-chat-plus-shell">
                  <button
                    aria-expanded={isMenuOpen}
                    aria-label="Composer actions"
                    className="workspace-chat-plus-button"
                    disabled={disabled}
                    onClick={(event) => {
                      event.preventDefault();
                      event.stopPropagation();
                      setIsMenuOpen((current) => !current);
                    }}
                    type="button"
                  >
                    +
                  </button>

                  {isMenuOpen ? (
                    <div className="workspace-chat-plus-menu">
                      <button
                        className="workspace-chat-plus-menu-item"
                        disabled={disabled}
                        onClick={(event) => {
                          event.preventDefault();
                          onAddAttachment?.();
                          setIsMenuOpen(false);
                        }}
                        type="button"
                      >
                        <AttachmentButtonIcon />
                        <span>Add Attachments</span>
                      </button>
                      <button
                        className="workspace-chat-plus-menu-item workspace-chat-plus-menu-item-toggle"
                        disabled={!planModeAvailable}
                        onClick={(event) => {
                          event.preventDefault();
                          if (!planModeAvailable) {
                            return;
                          }
                          onPlanModeChange(!isPlanMode);
                        }}
                        type="button"
                      >
                        <span className="workspace-chat-plus-menu-map">⌘</span>
                        <span>Plan mode</span>
                        <span
                          aria-hidden="true"
                          className={
                            isPlanMode
                              ? "workspace-chat-plus-toggle active"
                              : "workspace-chat-plus-toggle"
                          }
                        >
                          <span />
                        </span>
                      </button>
                    </div>
                  ) : null}
                </div>

                {completionMetrics ? (
                  <span className="workspace-chat-composer-metrics">
                    {completionMetrics}
                  </span>
                ) : null}

                <span
                  aria-hidden="true"
                  className="workspace-chat-composer-grid-icon"
                >
                  ⌗
                </span>
              </div>
            </>
          )}
        </div>
        <button
          aria-label={
            isStreaming && !isAwaitingInput ? "Stop response" : "Send prompt"
          }
          className="workspace-chat-send-button"
          disabled={
            disabled ||
            (!(isStreaming && !isAwaitingInput) && trimmedValue.length === 0)
          }
          type="submit"
        >
          {isStreaming && !isAwaitingInput ? (
            <ComposerStopIcon />
          ) : (
            <ComposerSendIcon />
          )}
        </button>
      </div>
    </form>
  );
}

function WorkspaceChatComposerSelect({
  ariaLabel,
  children,
  disabled,
  onChange,
  value,
}: {
  ariaLabel: string;
  children: ReactNode;
  disabled: boolean;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <label className="workspace-chat-composer-select-shell">
      <select
        aria-label={ariaLabel}
        className="workspace-chat-composer-select"
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        {children}
      </select>
      <span aria-hidden="true" className="workspace-chat-composer-select-arrow">
        ▼
      </span>
    </label>
  );
}

function ComposerSendIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="14"
      viewBox="0 0 14 14"
      width="14"
    >
      <path
        d="M7 11V3.5"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.5"
      />
      <path
        d="M3.75 6.25L7 3l3.25 3.25"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
      />
    </svg>
  );
}

function ComposerStopIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="currentColor"
      height="12"
      viewBox="0 0 12 12"
      width="12"
    >
      <rect height="8" rx="1.6" width="8" x="2" y="2" />
    </svg>
  );
}

function formatSessionCompletionMetrics(
  summary: SessionCompletionSummary | null,
) {
  if (!summary) {
    return "";
  }

  const metrics: string[] = [];
  if (typeof summary.totalTokens === "number") {
    metrics.push(`${compactMetricNumber(summary.totalTokens)} tokens`);
  }
  if (typeof summary.totalCostUSD === "number") {
    metrics.push(`$${summary.totalCostUSD.toFixed(2)}`);
  }
  return metrics.join(" • ");
}

function compactMetricNumber(value: number) {
  if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1)}m`;
  }
  if (value >= 1000) {
    return `${(value / 1000).toFixed(1)}k`;
  }
  return `${value}`;
}

function SessionConversationCommandCard({
  block,
}: {
  block: SessionConversationCommandBlock;
}) {
  return (
    <div className="conversation-command-card">
      <div className="conversation-command-header">
        <span className="conversation-command-kicker">Command</span>
        <span
          className={`conversation-command-badge ${agentRunEventStateTone(block.status)}`}
        >
          {agentRunEventStateLabel(block.status)}
        </span>
      </div>
      {block.command ? <pre>{block.command}</pre> : null}
      {block.output ? (
        <pre className="conversation-command-output">{block.output}</pre>
      ) : null}
      {typeof block.exitCode === "number" ? (
        <div className="conversation-command-meta">
          Exit code {block.exitCode}
        </div>
      ) : null}
    </div>
  );
}

function SessionConversationNoteCard({
  block,
}: {
  block: SessionConversationNoteBlock;
}) {
  return (
    <div className={`conversation-note-card ${block.tone}`}>
      <div className="conversation-note-header">
        <span className="conversation-note-kicker">{block.kicker}</span>
        {block.meta.length ? (
          <span className="conversation-note-meta">
            {block.meta.join(" · ")}
          </span>
        ) : null}
      </div>
      <div className="conversation-note-copy">{block.text}</div>
    </div>
  );
}

function ConversationTimeline({
  onRespondToQuestion,
  rows,
}: {
  onRespondToQuestion: (response: string) => void;
  rows: ConversationRow[];
}) {
  return (
    <div className="conversation-timeline">
      {rows.map((row) => (
        <ConversationTimelineRowView
          key={row.id}
          onRespondToQuestion={onRespondToQuestion}
          row={row}
        />
      ))}
    </div>
  );
}

function ConversationTimelineRowView({
  onRespondToQuestion,
  row,
}: {
  onRespondToQuestion: (response: string) => void;
  row: ConversationRow;
}) {
  const isUser = row.role === "user";

  return (
    <article
      className={
        isUser
          ? "conversation-row conversation-row-user"
          : row.role === "system"
            ? "conversation-row conversation-row-system"
            : "conversation-row"
      }
    >
      <div className="conversation-row-meta">
        <span className="conversation-row-role">
          {conversationRoleLabel(row.role)}
        </span>
        <span className="conversation-row-sequence">#{row.sequenceNumber}</span>
      </div>
      <div className="conversation-row-content">
        {row.blocks.map((block) => {
          if (block.kind === "text") {
            return (
              <ConversationTextBlockView key={block.id} text={block.text} />
            );
          }
          if (block.kind === "error") {
            return (
              <div className="conversation-error-card" key={block.id}>
                {block.message}
              </div>
            );
          }
          if (block.kind === "todo") {
            return (
              <ConversationTodoListCard
                items={block.todoList.items}
                key={block.id}
              />
            );
          }
          if (block.kind === "tool") {
            return <ConversationToolCard key={block.id} tool={block.tool} />;
          }
          if (block.kind === "subagent") {
            return (
              <ConversationSubAgentCard
                activity={block.activity}
                key={block.id}
              />
            );
          }
          if (block.kind === "question") {
            return (
              <ConversationQuestionCard
                key={block.id}
                onSubmit={onRespondToQuestion}
                question={block.question}
              />
            );
          }
          return null;
        })}
      </div>
    </article>
  );
}

function ConversationTextBlockView({ text }: { text: string }) {
  const segments = useMemo(() => splitConversationTextSegments(text), [text]);

  return (
    <div className="conversation-text-card">
      {segments.map((segment) =>
        segment.kind === "code" ? (
          <div className="conversation-code-block" key={segment.id}>
            {segment.language ? (
              <span className="conversation-code-language">
                {segment.language}
              </span>
            ) : null}
            <pre>{segment.content}</pre>
          </div>
        ) : (
          <div className="conversation-text-block" key={segment.id}>
            {segment.content}
          </div>
        ),
      )}
    </div>
  );
}

function ConversationTodoListCard({
  items,
}: {
  items: ConversationTodoItem[];
}) {
  return (
    <div className="conversation-todo-card">
      {items.map((item) => (
        <div className="conversation-todo-row" key={item.id}>
          <span
            aria-hidden="true"
            className="conversation-todo-status"
            data-status={item.status}
          />
          <span
            className={
              item.status === "completed"
                ? "conversation-todo-text conversation-todo-text-complete"
                : "conversation-todo-text"
            }
          >
            {item.content}
          </span>
          <span className="conversation-todo-badge">
            {conversationTodoStatusLabel(item.status)}
          </span>
        </div>
      ))}
    </div>
  );
}

function ConversationQuestionCard({
  onSubmit,
  question,
}: {
  onSubmit: (response: string) => void;
  question: ConversationQuestion;
}) {
  const [selectedValues, setSelectedValues] = useState<string[]>([]);
  const [textResponse, setTextResponse] = useState("");

  useEffect(() => {
    setSelectedValues([]);
    setTextResponse("");
  }, [question.id]);

  const toggleValue = (value: string) => {
    setSelectedValues((current) => {
      if (question.allowsMultiSelect) {
        return current.includes(value)
          ? current.filter((entry) => entry !== value)
          : [...current, value];
      }
      return current.includes(value) ? [] : [value];
    });
  };

  const handleSubmit = () => {
    const response = [...selectedValues, textResponse.trim()]
      .filter((value) => value.length > 0)
      .join(", ");
    if (!response) {
      return;
    }
    onSubmit(response);
    setSelectedValues([]);
    setTextResponse("");
  };

  return (
    <div className="conversation-question-card">
      <div className="conversation-question-header">
        {question.header ? (
          <span className="conversation-question-chip">{question.header}</span>
        ) : null}
        <strong>{question.question}</strong>
      </div>
      {question.options.length ? (
        <div className="conversation-question-options">
          {question.options.map((option) => {
            const isSelected = selectedValues.includes(option.value);
            return (
              <button
                className={
                  isSelected
                    ? "conversation-question-option active"
                    : "conversation-question-option"
                }
                key={`${question.id}-${option.value}`}
                onClick={() => toggleValue(option.value)}
                type="button"
              >
                <span>{option.label}</span>
                {option.description ? (
                  <small>{option.description}</small>
                ) : null}
              </button>
            );
          })}
        </div>
      ) : null}
      {question.allowsTextInput ? (
        <textarea
          className="conversation-question-textarea"
          onChange={(event) => setTextResponse(event.target.value)}
          placeholder="Type your response…"
          rows={3}
          value={textResponse}
        />
      ) : null}
      <div className="conversation-question-footer">
        <span className="issues-detail-copy muted">
          Sending this answer continues the current daemon session.
        </span>
        <button
          className="primary-button compact-button"
          disabled={selectedValues.length === 0 && !textResponse.trim()}
          onClick={handleSubmit}
          type="button"
        >
          Submit answer
        </button>
      </div>
    </div>
  );
}

function ConversationToolCard({
  compact = false,
  tool,
}: {
  compact?: boolean;
  tool: ConversationTool;
}) {
  const [isExpanded, setIsExpanded] = useState(tool.status === "failed");
  const detail = tool.output ?? tool.detail;
  const hasDetail = Boolean(detail);

  useEffect(() => {
    if (tool.status === "failed") {
      setIsExpanded(true);
    }
  }, [tool.id, tool.status]);

  return (
    <div
      className={
        compact
          ? "conversation-tool-card conversation-tool-card-compact"
          : "conversation-tool-card"
      }
    >
      <button
        className="conversation-tool-header"
        onClick={() => {
          if (hasDetail) {
            setIsExpanded((current) => !current);
          }
        }}
        type="button"
      >
        <div className="conversation-tool-copy">
          <span className="conversation-tool-icon">
            {conversationToolGlyph(tool.toolName)}
          </span>
          <div>
            <strong>{tool.toolName}</strong>
            {tool.preview ? <small>{tool.preview}</small> : null}
          </div>
        </div>
        <div className="conversation-tool-status-shell">
          <span className="conversation-tool-status" data-status={tool.status}>
            {capitalize(tool.status.replace("_", " "))}
          </span>
          {hasDetail ? (
            <span className="conversation-tool-chevron">
              {isExpanded ? "v" : ">"}
            </span>
          ) : null}
        </div>
      </button>
      {hasDetail && isExpanded ? (
        <div className="conversation-tool-detail">
          <pre>{detail}</pre>
        </div>
      ) : null}
    </div>
  );
}

function ConversationSubAgentCard({
  activity,
}: {
  activity: ConversationSubAgent;
}) {
  const [isExpanded, setIsExpanded] = useState(true);

  useEffect(() => {
    if (activity.status === "running") {
      setIsExpanded(true);
    }
  }, [activity.id, activity.status]);

  return (
    <div className="conversation-subagent-card">
      <button
        className="conversation-subagent-header"
        onClick={() => setIsExpanded((current) => !current)}
        type="button"
      >
        <div className="conversation-subagent-copy">
          <span className="conversation-subagent-icon">
            {conversationSubAgentGlyph(activity.subagentType)}
          </span>
          <div>
            <strong>{conversationSubAgentLabel(activity.subagentType)}</strong>
            {activity.description ? (
              <small>{activity.description}</small>
            ) : null}
          </div>
        </div>
        <div className="conversation-tool-status-shell">
          <span
            className="conversation-tool-status"
            data-status={activity.status}
          >
            {capitalize(activity.status.replace("_", " "))}
          </span>
          <span className="conversation-tool-chevron">
            {isExpanded ? "v" : ">"}
          </span>
        </div>
      </button>
      {isExpanded ? (
        <div className="conversation-subagent-body">
          {activity.tools.length ? (
            <div className="conversation-subagent-tools">
              {activity.tools.map((tool) => (
                <ConversationToolCard compact key={tool.id} tool={tool} />
              ))}
            </div>
          ) : (
            <p className="issues-detail-copy muted">
              Waiting for child tool activity…
            </p>
          )}
          {activity.result ? (
            <div className="conversation-subagent-result">
              <pre>{activity.result}</pre>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

type ConversationTextSegment = {
  content: string;
  id: string;
  kind: "code" | "text";
  language: string | null;
};

function splitConversationTextSegments(
  text: string,
): ConversationTextSegment[] {
  const source = text.trim();
  if (!source.includes("```")) {
    return [
      {
        content: source,
        id: "text-0",
        kind: "text",
        language: null,
      },
    ];
  }

  const segments: ConversationTextSegment[] = [];
  const pattern = /```([^\n`]*)\n?([\s\S]*?)```/g;
  let match: RegExpExecArray | null;
  let index = 0;
  let lastIndex = 0;

  while ((match = pattern.exec(source)) !== null) {
    const preceding = source.slice(lastIndex, match.index).trim();
    if (preceding) {
      segments.push({
        content: preceding,
        id: `text-${index}`,
        kind: "text",
        language: null,
      });
      index += 1;
    }

    segments.push({
      content: match[2]?.trim() ?? "",
      id: `code-${index}`,
      kind: "code",
      language: match[1]?.trim() || null,
    });
    index += 1;
    lastIndex = match.index + match[0].length;
  }

  const trailing = source.slice(lastIndex).trim();
  if (trailing) {
    segments.push({
      content: trailing,
      id: `text-${index}`,
      kind: "text",
      language: null,
    });
  }

  return segments.length
    ? segments
    : [
        {
          content: source,
          id: "text-fallback",
          kind: "text",
          language: null,
        },
      ];
}

function conversationRoleLabel(role: ConversationRow["role"] | "result") {
  switch (role) {
    case "assistant":
      return "Assistant";
    case "result":
      return "Result";
    case "system":
      return "System";
    case "user":
      return "You";
  }
}

function conversationTodoStatusLabel(status: ConversationTodoItem["status"]) {
  switch (status) {
    case "completed":
      return "Done";
    case "in_progress":
      return "In Progress";
    case "pending":
      return "Pending";
  }
}

function conversationToolGlyph(toolName: string) {
  switch (toolName.toLowerCase()) {
    case "bash":
      return ">";
    case "read":
      return "R";
    case "write":
      return "W";
    case "edit":
      return "E";
    case "glob":
      return "G";
    case "grep":
      return "F";
    case "webfetch":
      return "U";
    case "websearch":
      return "S";
    case "todowrite":
      return "T";
    default:
      return toolName.slice(0, 1).toUpperCase();
  }
}

function conversationSubAgentLabel(subagentType: string) {
  switch (subagentType.toLowerCase()) {
    case "explore":
      return "Explore Agent";
    case "plan":
      return "Plan Agent";
    case "bash":
      return "Bash Agent";
    case "general-purpose":
    case "general purpose":
      return "General Agent";
    default:
      return `${subagentType} Agent`;
  }
}

function conversationSubAgentGlyph(subagentType: string) {
  switch (subagentType.toLowerCase()) {
    case "explore":
      return "E";
    case "plan":
      return "P";
    case "bash":
      return ">";
    default:
      return "A";
  }
}

function IssuePropertySelectRow({
  children,
  disabled,
  hint,
  label,
  onChange,
  tone,
  value,
}: {
  children: ReactNode;
  disabled?: boolean;
  hint?: string;
  label: string;
  onChange: (value: string) => void;
  tone?: string;
  value: string;
}) {
  return (
    <label className="issue-property-row issue-property-row-select">
      <span className="issue-property-label">{label}</span>
      <div className="issue-property-control">
        <IssuePropertyToneMarker tone={tone} />
        <div className="issue-property-select-shell">
          <select
            className="issue-property-select"
            disabled={disabled}
            onChange={(event) => onChange(event.target.value)}
            value={value}
          >
            {children}
          </select>
          <span aria-hidden="true" className="issue-property-select-arrow">
            v
          </span>
        </div>
      </div>
      {hint ? <small className="issue-property-hint">{hint}</small> : null}
    </label>
  );
}

function IssuePropertyStaticRow({
  label,
  tone,
  value,
}: {
  label: string;
  tone?: string;
  value: string;
}) {
  return (
    <div className="issue-property-row">
      <span className="issue-property-label">{label}</span>
      <div className="issue-property-control">
        <IssuePropertyToneMarker tone={tone} />
        <strong className="issue-property-value">{value}</strong>
      </div>
    </div>
  );
}

function IssuePropertyToneMarker({ tone }: { tone?: string }) {
  return (
    <span
      aria-hidden="true"
      className="issue-property-tone-marker"
      data-tone={tone ?? "neutral"}
    />
  );
}

function DashboardIssuePreviewDialogView({
  agents,
  attachments,
  comments,
  errorMessage,
  isLoading,
  issue,
  onClose,
  onOpenIssue,
  parentIssueLabel,
  projectLabel,
  runCardUpdate,
  statusLabel,
  subissueCount,
}: {
  agents: AgentRecord[];
  attachments: IssueAttachmentRecord[];
  comments: IssueCommentRecord[];
  errorMessage: string | null;
  isLoading: boolean;
  issue: IssueRecord;
  onClose: () => void;
  onOpenIssue: () => void;
  parentIssueLabel: (parentIssueId?: string | null) => string;
  projectLabel: (projectId?: string | null) => string;
  runCardUpdate: IssueRunCardUpdateRecord | null;
  statusLabel: (value: string) => string;
  subissueCount: number;
}) {
  const latestComments = [...comments].slice(-2).reverse();
  const previewAttachments = attachments.slice(0, 3);
  const issueDescription = issue.description?.trim() ?? "";

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  return (
    <div
      className="modal-backdrop modal-backdrop-sheet"
      onClick={onClose}
      role="presentation"
    >
      <div
        aria-labelledby="dashboard-issue-preview-title"
        aria-modal="true"
        className="issue-dialog dashboard-issue-preview-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="issue-dialog-header">
          <div className="issue-dialog-breadcrumbs">
            <span className="issue-dialog-badge">
              {issue.identifier ?? issue.id}
            </span>
            <span aria-hidden="true" className="issue-dialog-breadcrumb-sep">
              &gt;
            </span>
            <span>{projectLabel(issue.project_id)}</span>
          </div>
          <button
            aria-label="Close conversation preview"
            className="project-dialog-close issue-dialog-close"
            onClick={onClose}
            type="button"
          >
            x
          </button>
        </div>

        <div className="dashboard-issue-preview-body">
          <div className="dashboard-issue-preview-main">
            <div className="dashboard-issue-preview-identity">
              <h2 id="dashboard-issue-preview-title">{issue.title}</h2>
              <p>
                {issueDescription ||
                  "No description yet. Open the conversation detail view to add context, decisions, or notes."}
              </p>
            </div>

            <div className="dashboard-issue-preview-summary">
              <SummaryPill label="Status" value={statusLabel(issue.status)} />
              <SummaryPill
                label="Project"
                value={projectLabel(issue.project_id)}
              />
              <SummaryPill label="Messages" value={comments.length} />
              <SummaryPill label="Attachments" value={attachments.length} />
              <SummaryPill label="Queued" value={subissueCount} />
            </div>

            {runCardUpdate ? (
              <section className="dashboard-issue-preview-update">
                <div className="dashboard-issue-preview-update-header">
                  <strong>Latest model run</strong>
                  <RunStatusBadge status={runCardUpdate.run_status} />
                </div>
                <p>
                  {issueModelLabel(issue, agents)} ·{" "}
                  {issueRunCardUpdateSummary(runCardUpdate)}
                </p>
                <span>
                  Last activity{" "}
                  {formatRelativeIssueDate(runCardUpdate.last_activity_at)}
                </span>
              </section>
            ) : null}

            {errorMessage ? (
              <div className="issue-dialog-alert">{errorMessage}</div>
            ) : null}

            {isLoading ? (
              <p className="issues-detail-copy muted">
                Loading the latest conversation details...
              </p>
            ) : null}

            <div className="dashboard-issue-preview-sections">
              <section className="dashboard-issue-preview-section">
                <div className="issues-detail-subsection-header">
                  <div className="issues-detail-subsection-copy">
                    <h3>Recent messages</h3>
                    <p className="issues-detail-copy muted">
                      A quick snapshot from the conversation.
                    </p>
                  </div>
                </div>

                {latestComments.length ? (
                  <div className="issues-comment-list">
                    {latestComments.map((comment) => (
                      <article className="issues-comment-card" key={comment.id}>
                        <div className="issues-comment-card-target">
                          {issueCommentAuthorLabel(agents, comment)}
                        </div>
                        <p>{comment.body}</p>
                        <span>{formatIssueDate(comment.created_at)}</span>
                      </article>
                    ))}
                  </div>
                ) : (
                  <p className="issues-detail-copy muted">No messages yet.</p>
                )}
              </section>

              <section className="dashboard-issue-preview-section">
                <div className="issues-detail-subsection-header">
                  <div className="issues-detail-subsection-copy">
                    <h3>Attachments</h3>
                    <p className="issues-detail-copy muted">
                      Recent files linked to this conversation.
                    </p>
                  </div>
                </div>

                {previewAttachments.length ? (
                  <div className="issue-attachment-list">
                    {previewAttachments.map((attachment) => (
                      <div className="issue-attachment-row" key={attachment.id}>
                        <div className="issue-attachment-meta">
                          <strong>
                            {attachment.original_filename ??
                              fileName(attachment.local_path)}
                          </strong>
                          <span>
                            {formatFileSize(attachment.byte_size)} ·{" "}
                            {formatIssueDate(attachment.created_at)}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="issues-detail-copy muted">
                    No attachments yet.
                  </p>
                )}
              </section>
            </div>
          </div>

          <aside className="dashboard-issue-preview-sidebar">
            <section className="issues-properties-section">
              <IssuePropertyStaticRow
                label="Status"
                tone={normalizeBoardIssueValue(issue.status)}
                value={statusLabel(issue.status)}
              />
              <IssuePropertyStaticRow
                label="Project"
                tone="project"
                value={projectLabel(issue.project_id)}
              />
              <IssuePropertyStaticRow
                label="Parent Conversation"
                value={parentIssueLabel(issue.parent_id)}
              />
              <IssuePropertyStaticRow
                label="Created by"
                value={issueCreatorLabel(issue, agents)}
              />
              <IssuePropertyStaticRow
                label="Created"
                value={formatBoardDate(issue.created_at)}
              />
              <IssuePropertyStaticRow
                label="Updated"
                value={formatRelativeIssueDate(issue.updated_at)}
              />
            </section>
          </aside>
        </div>

        <div className="issue-dialog-footer dashboard-issue-preview-footer">
          <div className="issue-dialog-footer-tools">
            <span className="issues-detail-copy muted">
              Previewing the conversation from the dashboard board.
            </span>
          </div>
          <div className="issue-dialog-footer-actions">
            <button
              className="issue-dialog-discard-button"
              onClick={onClose}
              type="button"
            >
              Close
            </button>
            <button
              className="primary-button issue-dialog-create-button"
              onClick={onOpenIssue}
              type="button"
            >
              Open conversation
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function AgentHeaderBotIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="20"
      viewBox="0 0 24 24"
      width="20"
    >
      <path
        d="M12 4v3"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
      <path
        d="M7.5 7.5h9A3.5 3.5 0 0 1 20 11v4.5A3.5 3.5 0 0 1 16.5 19h-9A3.5 3.5 0 0 1 4 15.5V11a3.5 3.5 0 0 1 3.5-3.5Z"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path
        d="M9 12h.01M15 12h.01"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2.4"
      />
      <path
        d="M9.5 15.5h5"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
      <path
        d="M4 12H2.5M21.5 12H20M8 19v2M16 19v2"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function AgentHeaderPlusIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <path
        d="M12 5v14M5 12h14"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function AgentHeaderPauseIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <path
        d="M9 6v12M15 6v12"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function ChevronUpDownIcon() {
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 24 24">
      <path
        d="m8 10 4-4 4 4"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
      <path
        d="m16 14-4 4-4-4"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 24 24">
      <path
        d="m5 12.5 4.2 4.2L19 7"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.9"
      />
    </svg>
  );
}

function SlidersHorizontalIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <path
        d="M4 21v-7m0-4V3m8 18V11m0-4V3m8 18v-4m0-4V3M1 14h6m2-7h6m2 10h6"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
      <circle cx="4" cy="12" fill="currentColor" r="1.6" />
      <circle cx="12" cy="9" fill="currentColor" r="1.6" />
      <circle cx="20" cy="15" fill="currentColor" r="1.6" />
    </svg>
  );
}

function EllipsisHorizontalIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="currentColor"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <circle cx="5" cy="12" r="1.9" />
      <circle cx="12" cy="12" r="1.9" />
      <circle cx="19" cy="12" r="1.9" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <path
        d="M18 6 6 18M6 6l12 12"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function AttachmentButtonIcon() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="16"
      viewBox="0 0 24 24"
      width="16"
    >
      <path
        d="m21.44 11.05-8.49 8.49a5.5 5.5 0 0 1-7.78-7.78l9.19-9.19a3.5 3.5 0 1 1 4.95 4.95l-9.2 9.19a1.5 1.5 0 0 1-2.12-2.12l8.49-8.49"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function IssueListStatusIcon({ status }: { status: string }) {
  switch (normalizeBoardIssueValue(status)) {
    case "done":
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <circle cx="8" cy="8" fill="currentColor" r="6" />
          <path
            d="m5.4 8.1 1.55 1.55L10.7 5.9"
            stroke="#08090A"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.7"
          />
        </svg>
      );
    case "in_progress":
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <circle cx="8" cy="8" opacity="0.32" r="5.25" stroke="currentColor" />
          <path
            d="M8 2.75a5.25 5.25 0 1 1-4.37 2.35"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="2"
          />
        </svg>
      );
    case "blocked":
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <circle cx="8" cy="8" opacity="0.28" r="5.25" stroke="currentColor" />
          <path
            d="M5.05 10.95 10.95 5.05"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.8"
          />
        </svg>
      );
    case "cancelled":
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <circle cx="8" cy="8" opacity="0.28" r="5.25" stroke="currentColor" />
          <path
            d="M5.55 5.55 10.45 10.45M10.45 5.55l-4.9 4.9"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.5"
          />
        </svg>
      );
    case "backlog":
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <path
            d="M4.2 8h7.6"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.8"
          />
        </svg>
      );
    case "todo":
    default:
      return (
        <svg aria-hidden="true" fill="none" viewBox="0 0 16 16">
          <circle
            cx="8"
            cy="8"
            r="5.25"
            stroke="currentColor"
            strokeWidth="1.8"
          />
        </svg>
      );
  }
}

function CostsRouteView({
  company,
  agents,
}: {
  company: Company | null;
  agents: AgentRecord[];
}) {
  const sortedAgents = useMemo(
    () =>
      agents.slice().sort((left, right) => {
        const spendDelta = agentSpentCents(right) - agentSpentCents(left);
        if (spendDelta !== 0) {
          return spendDelta;
        }

        const budgetDelta = agentBudgetCents(right) - agentBudgetCents(left);
        if (budgetDelta !== 0) {
          return budgetDelta;
        }

        return (left.name || left.title || left.role || left.id).localeCompare(
          right.name || right.title || right.role || right.id,
        );
      }),
    [agents],
  );
  const companyBudget = companyBudgetCents(company);
  const companySpent = companySpentCents(company);
  const companyRemaining = companyBudget - companySpent;
  const agentTrackedSpend = sortedAgents.reduce(
    (total, agent) => total + agentSpentCents(agent),
    0,
  );
  const agentsWithSpendCount = sortedAgents.filter(
    (agent) => agentSpentCents(agent) > 0,
  ).length;
  const overBudgetAgentsCount = sortedAgents.filter(isAgentOverBudget).length;
  const companyUtilizationLabel = formatBudgetUtilization(
    companySpent,
    companyBudget,
  );
  const companyBudgetStatus = companyBudgetStatusLabel(
    companySpent,
    companyBudget,
  );
  const unattributedSpend = companySpent - agentTrackedSpend;

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: "Costs" }]} />
        <span className="route-kicker">Costs</span>
        <h1>Budget and spend</h1>
        <p>
          Space and agent spend from the daemon-backed board models, matching
          the cost data the Swift surfaces already exposed.
        </p>
      </div>

      <div className="metric-grid">
        <MetricCard label="Monthly Budget" value={formatCents(companyBudget)} />
        <MetricCard
          label="Spent This Month"
          value={formatCents(companySpent)}
        />
        <MetricCard label="Remaining" value={formatCents(companyRemaining)} />
        <MetricCard label="Utilization" value={companyUtilizationLabel} />
        <MetricCard label="Tracked Agents" value={agentsWithSpendCount} />
        <MetricCard label="Over Budget" value={overBudgetAgentsCount} />
      </div>

      <div className="surface-grid">
        <section className="surface-panel wide costs-overview-panel">
          <div className="surface-header">
            <h3>Space Budget</h3>
          </div>

          <div className="summary-grid">
            <SummaryPill label="Budget" value={formatCents(companyBudget)} />
            <SummaryPill label="Spent" value={formatCents(companySpent)} />
            <SummaryPill
              label="Tracked Agent Spend"
              value={formatCents(agentTrackedSpend)}
            />
            <SummaryPill label="Status" value={companyBudgetStatus} />
          </div>

          <div className="costs-progress-card">
            <div className="costs-progress-copy">
              <strong>{companyBudgetStatus}</strong>
              <span>
                {companyBudget > 0
                  ? `${formatCents(companySpent)} spent of ${formatCents(companyBudget)} this month`
                  : `${formatCents(companySpent)} spent this month with no space budget cap`}
              </span>
            </div>

            <div className="costs-progress-track" role="presentation">
              <div
                className="costs-progress-fill"
                style={{
                  width: `${budgetProgressPercent(companySpent, companyBudget)}%`,
                }}
              />
            </div>
          </div>

          <div className="surface-list costs-summary-list">
            <div className="surface-list-row">
              <span>Budget Utilization</span>
              <strong>{companyUtilizationLabel}</strong>
            </div>
            <div className="surface-list-row">
              <span>Budget Remaining</span>
              <strong>{formatCents(companyRemaining)}</strong>
            </div>
            <div className="surface-list-row">
              <span>Unattributed Spend</span>
              <strong>{formatCents(unattributedSpend)}</strong>
            </div>
          </div>
        </section>

        <section className="surface-panel costs-summary-panel">
          <div className="surface-header">
            <h3>Guardrails</h3>
          </div>

          <div className="surface-list costs-summary-list">
            <div className="surface-list-row">
              <span>Agents With Budget Caps</span>
              <strong>
                {
                  sortedAgents.filter((agent) => agentBudgetCents(agent) > 0)
                    .length
                }
              </strong>
            </div>
            <div className="surface-list-row">
              <span>Agents Over Budget</span>
              <strong>{overBudgetAgentsCount}</strong>
            </div>
            <div className="surface-list-row">
              <span>Total Agents</span>
              <strong>{sortedAgents.length}</strong>
            </div>
            <div className="surface-list-row">
              <span>Space Policy</span>
              <strong>
                {companyBudget > 0 ? "Budget capped" : "No space cap"}
              </strong>
            </div>
          </div>
        </section>
      </div>

      <section className="surface-panel costs-agents-panel">
        <div className="surface-header">
          <h3>Agent Spend</h3>
        </div>

        {sortedAgents.length ? (
          <div className="surface-list costs-agent-list">
            {sortedAgents.map((agent) => (
              <CostAgentRow agent={agent} key={agent.id} />
            ))}
          </div>
        ) : (
          <div className="workspace-empty-state">
            <h3>No agents yet</h3>
            <p>
              Agent spend will appear here once the space has active agents.
            </p>
          </div>
        )}
      </section>
    </section>
  );
}

function CostAgentRow({ agent }: { agent: AgentRecord }) {
  const budget = agentBudgetCents(agent);
  const spent = agentSpentCents(agent);
  const spendLabel =
    budget > 0
      ? `${formatCents(spent)} / ${formatCents(budget)}`
      : formatCents(spent);
  const spendStatus = agentBudgetStatusLabel(spent, budget);
  const secondaryMeta = [agent.title ?? agent.role, agent.status ?? "unknown"];

  return (
    <div className="cost-agent-row">
      <div className="cost-agent-row-top">
        <div className="cost-agent-row-copy">
          <strong>{agent.name || agent.title || agent.role || agent.id}</strong>
          <span>{secondaryMeta.filter(Boolean).join(" · ")}</span>
        </div>

        <div className="cost-agent-row-metrics">
          <strong>{spendLabel}</strong>
          <span>{spendStatus}</span>
        </div>
      </div>

      <div className="cost-agent-row-progress" role="presentation">
        <div
          className="cost-agent-row-progress-fill"
          style={{ width: `${budgetProgressPercent(spent, budget)}%` }}
        />
      </div>
    </div>
  );
}

function CreateCompanyDialogView({
  name,
  description,
  brandColor,
  errorMessage,
  isSaving,
  onNameChange,
  onDescriptionChange,
  onBrandColorChange,
  onCreate,
  onClose,
}: {
  name: string;
  description: string;
  brandColor: string;
  errorMessage: string | null;
  isSaving: boolean;
  onNameChange: (value: string) => void;
  onDescriptionChange: (value: string) => void;
  onBrandColorChange: (value: string) => void;
  onCreate: () => void;
  onClose: () => void;
}) {
  const canCreate = Boolean(name.trim()) && !isSaving;

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        aria-labelledby="create-company-dialog-title"
        aria-modal="true"
        className="project-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="create-company-dialog-title">New space</h2>
            <p>
              Create a space for projects and conversations. A default local
              executor will be prepared automatically.
            </p>
          </div>

          <button
            aria-label="Close create space dialog"
            className="project-dialog-close"
            onClick={onClose}
            type="button"
          >
            x
          </button>
        </div>

        <div className="project-dialog-body">
          <div className="project-dialog-divider" />

          {errorMessage ? (
            <div className="issue-dialog-alert">{errorMessage}</div>
          ) : null}

          <div className="project-dialog-stack">
            <label className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Space name</span>
              <input
                autoFocus
                className="issue-dialog-input"
                onChange={(event) => onNameChange(event.target.value)}
                placeholder="Acme Systems"
                type="text"
                value={name}
              />
              <small className="issue-dialog-hint">
                Shown in the spaces rail, dashboard, and space menus.
              </small>
            </label>

            <label className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Description</span>
              <textarea
                className="issue-dialog-input issue-dialog-textarea"
                onChange={(event) => onDescriptionChange(event.target.value)}
                placeholder="Optional context for what this space owns or how it should operate..."
                value={description}
              />
              <small className="issue-dialog-hint">
                Optional setup context you can refine later from space settings.
              </small>
            </label>

            <label className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Brand color</span>
              <input
                className="issue-dialog-input"
                onChange={(event) => onBrandColorChange(event.target.value)}
                placeholder={defaultCompanyBrandColor}
                type="text"
                value={brandColor}
              />
              <small className="issue-dialog-hint">
                Optional hex color used for the space badge in the rail.
              </small>
            </label>
          </div>
        </div>

        <div className="issue-dialog-footer project-dialog-footer">
          <button
            className="secondary-button"
            disabled={isSaving}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="primary-button"
            disabled={!canCreate}
            onClick={onCreate}
            type="button"
          >
            {isSaving ? "Creating space..." : "Create space"}
          </button>
        </div>
      </div>
    </div>
  );
}

function CreateIssueDialogView({
  companyPrefix,
  command,
  dependencyCheck,
  title,
  description,
  attachments,
  enableChrome,
  model,
  selectedProjectId,
  projects,
  isSaving,
  errorMessage,
  mode,
  planMode,
  parentConversationTitle,
  onAddAttachment,
  onCommandChange,
  onTitleChange,
  onDescriptionChange,
  onEnableChromeChange,
  onModelChange,
  onPlanModeChange,
  onProjectChange,
  onRemoveAttachment,
  onSkipPermissionsChange,
  onThinkingEffortChange,
  onWorkspaceTargetChange,
  onCreate,
  onClose,
  selectedWorkspaceTargetValue,
  skipPermissions,
  thinkingEffort,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  companyPrefix: string;
  command: string;
  dependencyCheck: RuntimeCapabilities | null;
  title: string;
  description: string;
  attachments: IssueAttachmentDraft[];
  enableChrome: boolean;
  model: string;
  selectedProjectId: string;
  projects: ProjectRecord[];
  isSaving: boolean;
  errorMessage: string | null;
  mode: IssueDialogMode;
  planMode: boolean;
  parentConversationTitle?: string | null;
  onAddAttachment: () => void;
  onCommandChange: (value: string) => void;
  onTitleChange: (value: string) => void;
  onDescriptionChange: (value: string) => void;
  onEnableChromeChange: (checked: boolean) => void;
  onModelChange: (value: string) => void;
  onPlanModeChange: (checked: boolean) => void;
  onProjectChange: (value: string) => void;
  onRemoveAttachment: (path: string) => void;
  onSkipPermissionsChange: (checked: boolean) => void;
  onThinkingEffortChange: (value: string) => void;
  onWorkspaceTargetChange: (value: string) => void;
  onCreate: () => void;
  onClose: () => void;
  selectedWorkspaceTargetValue: string;
  skipPermissions: boolean;
  thinkingEffort: string;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const issueCompanyPrefix = stringFromUnknown(companyPrefix, "ISS");
  const issueTitle = stringFromUnknown(title);
  const issueDescription = stringFromUnknown(description);
  const issueCommand = stringFromUnknown(command, "claude");
  const issueModel = stringFromUnknown(model, "default");
  const issueProjectId = stringFromUnknown(selectedProjectId);
  const issueThinkingEffort = stringFromUnknown(thinkingEffort, "auto");
  const issueWorkspaceTargetValue = stringFromUnknown(
    selectedWorkspaceTargetValue,
    "main",
  );
  const issueErrorMessage = errorMessage
    ? stringFromUnknown(errorMessage)
    : null;
  const issueWorkspaceTargetErrorMessage = workspaceTargetErrorMessage
    ? stringFromUnknown(workspaceTargetErrorMessage)
    : null;
  const isSavingIssue = booleanFromUnknown(isSaving);
  const isPlanMode = booleanFromUnknown(planMode);
  const isEnableChrome = booleanFromUnknown(enableChrome);
  const isSkipPermissions = booleanFromUnknown(skipPermissions);
  const attachmentDrafts = arrayFromUnknown(attachments).filter(
    (attachment): attachment is IssueAttachmentDraft =>
      Boolean(attachment) &&
      typeof attachment === "object" &&
      typeof (attachment as IssueAttachmentDraft).path === "string" &&
      typeof (attachment as IssueAttachmentDraft).name === "string",
  );
  const projectOptions = arrayFromUnknown(projects).filter(
    (project): project is ProjectRecord =>
      Boolean(project) &&
      typeof project === "object" &&
      typeof (project as ProjectRecord).id === "string",
  );
  const worktreeOptions = normalizeGitWorktreeRecords(workspaceTargetWorktrees);
  const dialogTitle =
    mode === "queuedMessage" ? "Queue message" : "New conversation";
  const issueProjectValidationMessage =
    projectOptions.length === 0
      ? mode === "queuedMessage"
        ? "Create a project before queueing messages."
        : "Create a project before creating a conversation."
      : null;
  const visibleIssueErrorMessage =
    issueErrorMessage ?? issueProjectValidationMessage;
  const canCreate =
    !isSavingIssue &&
    issueTitle.trim().length > 0 &&
    issueProjectId.trim().length > 0 &&
    issueProjectValidationMessage === null;
  const selectedProject =
    projectOptions.find((project) => project.id === issueProjectId) ?? null;
  const selectedProjectRepoPath =
    selectedProject?.primary_workspace?.cwd ?? null;
  const shouldShowWorktreeTarget = Boolean(selectedProject);
  const fallbackSelectedWorktree =
    issueWorkspaceTargetValue.startsWith("existing:") &&
    !worktreeOptions.some(
      (worktree) =>
        existingWorktreeTargetValue(worktree.path) ===
        issueWorkspaceTargetValue,
    )
      ? {
          name: fileName(issueWorkspaceTargetValue.slice("existing:".length)),
          path: issueWorkspaceTargetValue.slice("existing:".length),
        }
      : null;
  const workspaceTargetHint = issueWorkspaceTargetHint({
    errorMessage: issueWorkspaceTargetErrorMessage,
    hasProject: Boolean(selectedProject),
    hasRepoPath: Boolean(selectedProjectRepoPath),
    isLoading: workspaceTargetLoading,
    worktreeCount: worktreeOptions.length,
  });
  const runtimeProvider = detectAgentCliProvider(issueCommand, issueModel);
  const runtimeModelOptions = buildAgentModelOptions(
    { command: issueCommand, model: issueModel },
    dependencyCheck,
  );
  const runtimeThinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    issueThinkingEffort,
  );
  const runtimeProviderOptions = buildIssueRuntimeProviderOptions(
    dependencyCheck,
    issueCommand,
    issueModel,
  );
  const browserToggleLabel =
    runtimeProvider === "codex" ? "Enable web search" : "Enable Chrome";
  const browserToggleDescription =
    runtimeProvider === "codex"
      ? "Expose Codex web search during runs."
      : "Allow browser automation inside Claude runs.";

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        aria-labelledby="create-issue-dialog-title"
        aria-modal="true"
        className="issue-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="issue-dialog-header">
          <div className="issue-dialog-breadcrumbs">
            <span className="issue-dialog-badge">
              {issueCompanyPrefix.toUpperCase()}
            </span>
            <span aria-hidden="true" className="issue-dialog-breadcrumb-sep">
              &gt;
            </span>
            <span id="create-issue-dialog-title">{dialogTitle}</span>
          </div>
          <button
            aria-label={
              mode === "queuedMessage"
                ? "Close queue message dialog"
                : "Close create conversation dialog"
            }
            className="project-dialog-close issue-dialog-close"
            onClick={onClose}
            type="button"
          >
            x
          </button>
        </div>

        <div className="issue-dialog-body">
          {visibleIssueErrorMessage ? (
            <div className="issue-dialog-alert">{visibleIssueErrorMessage}</div>
          ) : null}

          <div className="issue-dialog-composer">
            <input
              autoFocus
              className="issue-dialog-title-input"
              onChange={(event) => onTitleChange(event.target.value)}
              placeholder={
                mode === "queuedMessage"
                  ? "Queued message title"
                  : "Conversation title"
              }
              value={issueTitle}
            />

            <p className="issue-dialog-inline-hint">
              {mode === "queuedMessage"
                ? `This follow-up will stay attached to ${parentConversationTitle ?? "the parent conversation"} until you open it.`
                : "Keep it lightweight: capture the context, attach files, and point the conversation at a project."}
            </p>

            <div className="issue-dialog-inline-row">
              <span className="issue-dialog-inline-copy">Project</span>
              <IssueDialogInlineSelect
                ariaLabel="Select project"
                className="issue-dialog-inline-select-project"
                onChange={onProjectChange}
                value={issueProjectId}
              >
                <option disabled value="">
                  {projectOptions.length ? "Select project" : "Create project"}
                </option>
                {projectOptions.map((project) => (
                  <option key={project.id} value={project.id}>
                    {project.name ?? project.title ?? project.id}
                  </option>
                ))}
              </IssueDialogInlineSelect>
            </div>

            {shouldShowWorktreeTarget ? (
              <div className="issue-dialog-worktree-block">
                <div className="issue-dialog-inline-row">
                  <span className="issue-dialog-inline-copy">Run in</span>
                  <IssueDialogInlineSelect
                    ariaLabel="Select worktree target"
                    className="issue-dialog-inline-select-worktree"
                    disabled={!selectedProjectRepoPath}
                    onChange={onWorkspaceTargetChange}
                    value={issueWorkspaceTargetValue}
                  >
                    <option value="main">Repo root</option>
                    <option
                      disabled={!selectedProjectRepoPath}
                      value="new_worktree"
                    >
                      New git worktree
                    </option>
                    {worktreeOptions.map((worktree) => (
                      <option
                        key={worktree.path}
                        value={existingWorktreeTargetValue(worktree.path)}
                      >
                        {worktree.branch
                          ? `${worktree.name} · ${worktree.branch}`
                          : worktree.name}
                      </option>
                    ))}
                    {fallbackSelectedWorktree ? (
                      <option
                        value={existingWorktreeTargetValue(
                          fallbackSelectedWorktree.path,
                        )}
                      >
                        {fallbackSelectedWorktree.name}
                      </option>
                    ) : null}
                  </IssueDialogInlineSelect>
                </div>
                <p className="issue-dialog-inline-hint">
                  {workspaceTargetHint}
                </p>
              </div>
            ) : null}

            <div className="agent-config-section issue-dialog-runtime-section">
              <div className="surface-header">
                <div>
                  <h3>Model configuration</h3>
                  <p className="issue-dialog-inline-hint">
                    Choose which local model runs this conversation and how much
                    autonomy it gets.
                  </p>
                </div>
              </div>
              <div className="agent-config-grid">
                <AgentConfigField
                  htmlFor="issue-dialog-command"
                  label="Provider"
                >
                  <AgentConfigSelect
                    ariaLabel="Conversation provider"
                    id="issue-dialog-command"
                    onChange={(value) => {
                      const patch = runtimeDraftPatchForProviderSelection(
                        value,
                        { model: issueModel, planMode: isPlanMode },
                        dependencyCheck,
                      );
                      onCommandChange(patch.command);
                      onModelChange(patch.model);
                      onPlanModeChange(patch.planMode);
                    }}
                    value={issueCommand}
                  >
                    {runtimeProviderOptions.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </AgentConfigSelect>
                </AgentConfigField>

                <AgentConfigField htmlFor="issue-dialog-model" label="Model">
                  <AgentConfigSelect
                    ariaLabel="Conversation model"
                    id="issue-dialog-model"
                    onChange={onModelChange}
                    value={issueModel}
                  >
                    {runtimeModelOptions.map((option) => (
                      <option key={option} value={option}>
                        {option === "default" ? "Default" : option}
                      </option>
                    ))}
                  </AgentConfigSelect>
                </AgentConfigField>

                <AgentConfigField
                  htmlFor="issue-dialog-thinking"
                  label="Thinking effort"
                >
                  <AgentConfigSelect
                    ariaLabel="Conversation thinking effort"
                    id="issue-dialog-thinking"
                    onChange={onThinkingEffortChange}
                    value={issueThinkingEffort}
                  >
                    {runtimeThinkingEffortOptions.map((option) => (
                      <option key={option} value={option}>
                        {capitalize(option)}
                      </option>
                    ))}
                  </AgentConfigSelect>
                </AgentConfigField>

                <AgentConfigField
                  htmlFor="issue-dialog-plan-mode"
                  label="Plan mode"
                >
                  <AgentConfigSelect
                    ariaLabel="Conversation plan mode"
                    id="issue-dialog-plan-mode"
                    onChange={(value) => onPlanModeChange(value === "plan")}
                    value={isPlanMode ? "plan" : "default"}
                  >
                    <option value="default">Off</option>
                    <option
                      disabled={runtimeProvider !== "claude"}
                      value="plan"
                    >
                      Claude plan mode
                    </option>
                  </AgentConfigSelect>
                </AgentConfigField>
              </div>

              <div className="agent-config-toggle-grid">
                <AgentConfigToggleField
                  checked={isEnableChrome}
                  description={browserToggleDescription}
                  label={browserToggleLabel}
                  onChange={onEnableChromeChange}
                />
                <AgentConfigToggleField
                  checked={isSkipPermissions}
                  description="Let the model run without daemon approval prompts."
                  label="Skip permissions"
                  onChange={onSkipPermissionsChange}
                />
              </div>
            </div>
          </div>

          <div className="issue-dialog-divider" />

          <div className="issue-dialog-description-panel">
            <textarea
              className="issue-dialog-description-input"
              onChange={(event) => onDescriptionChange(event.target.value)}
              placeholder={
                mode === "queuedMessage"
                  ? "Add the message or follow-up you want to queue for later..."
                  : "Add context, goals, or the next thing a model should pick up..."
              }
              value={issueDescription}
            />

            {attachmentDrafts.length ? (
              <div className="issue-dialog-attachments">
                <div className="issues-detail-subsection-header">
                  <div className="issues-detail-subsection-copy">
                    <h3>Attachments</h3>
                    <p className="issues-detail-copy muted">
                      These files will be copied into the board storage and
                      linked to the conversation when it is created.
                    </p>
                  </div>
                </div>

                <div className="issue-attachment-list">
                  {attachmentDrafts.map((attachment) => (
                    <div className="issue-attachment-row" key={attachment.path}>
                      <div className="issue-attachment-meta">
                        <strong>{attachment.name}</strong>
                        <span>{attachment.path}</span>
                      </div>
                      <div className="issue-attachment-actions">
                        <button
                          className="secondary-button compact-button"
                          disabled={isSavingIssue}
                          onClick={() => onRemoveAttachment(attachment.path)}
                          type="button"
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : null}
          </div>
        </div>

        <div className="issue-dialog-footer">
          <div className="issue-dialog-footer-tools">
            <button
              className="issue-dialog-footer-chip issue-dialog-footer-chip-button"
              disabled={isSavingIssue}
              onClick={onAddAttachment}
              type="button"
            >
              <AttachmentButtonIcon />
              Attachment
            </button>
          </div>

          <div className="issue-dialog-footer-actions">
            <button
              className="issue-dialog-discard-button"
              disabled={isSavingIssue}
              onClick={onClose}
              type="button"
            >
              Discard Draft
            </button>
            <button
              className="primary-button issue-dialog-create-button"
              disabled={!canCreate}
              onClick={onCreate}
              type="button"
            >
              {isSavingIssue
                ? mode === "queuedMessage"
                  ? "Queueing..."
                  : "Creating..."
                : mode === "queuedMessage"
                  ? "Queue Message"
                  : "Create Conversation"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function IssueDialogInlineSelect({
  children,
  ariaLabel,
  className,
  disabled,
  onChange,
  value,
}: {
  children: ReactNode;
  ariaLabel: string;
  className?: string;
  disabled?: boolean;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <div
      className={[
        "issue-dialog-inline-select",
        disabled ? "is-disabled" : "",
        className ?? "",
      ]
        .join(" ")
        .trim()}
    >
      <select
        aria-label={ariaLabel}
        className="issue-dialog-inline-select-control"
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        {children}
      </select>
      <span aria-hidden="true" className="issue-dialog-inline-select-arrow">
        ▼
      </span>
    </div>
  );
}

function IssueDialogSelectField({
  children,
  hint,
  label,
  onChange,
  value,
}: {
  children: ReactNode;
  hint: string;
  label: string;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <label className="issue-dialog-field">
      <span className="issue-dialog-label">{label}</span>
      <div className="issue-dialog-select-shell">
        <select
          className="issue-dialog-select"
          onChange={(event) => onChange(event.target.value)}
          value={value}
        >
          {children}
        </select>
        <span aria-hidden="true" className="issue-dialog-select-arrow">
          v
        </span>
      </div>
      <small className="issue-dialog-hint">{hint}</small>
    </label>
  );
}

function SettingsSidebarItem({
  icon,
  isSelected,
  label,
  onClick,
}: {
  icon: string;
  isSelected: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className={isSelected ? "settings-nav-item active" : "settings-nav-item"}
      onClick={onClick}
      type="button"
    >
      <span className="settings-nav-icon">{symbolForSettingsIcon(icon)}</span>
      <span>{label}</span>
    </button>
  );
}

function SettingsPageShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  return (
    <section className="settings-page-shell">
      <div className="settings-page-header">
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      <div className="settings-page-divider" />
      <div className="settings-page-body">{children}</div>
    </section>
  );
}

function SettingsSectionBlock({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <section className="settings-section-block">
      <div className="settings-section-header">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
      {children}
    </section>
  );
}

function SettingsToggleField({
  checked,
  description,
  label,
  onChange,
}: {
  checked: boolean;
  description: string;
  label: string;
  onChange: (checked: boolean) => void;
}) {
  return (
    <div className="settings-shadcn-field">
      <div className="settings-shadcn-field-copy">
        <strong>{label}</strong>
        <p>{description}</p>
      </div>
      <button
        aria-checked={checked}
        aria-label={label}
        className={
          checked ? "settings-shadcn-switch active" : "settings-shadcn-switch"
        }
        onClick={() => onChange(checked ? false : true)}
        role="switch"
        type="button"
      >
        <span />
      </button>
    </div>
  );
}

function SettingsSelectField<T extends string>({
  ariaLabel,
  description,
  label,
  onChange,
  options,
  value,
}: {
  ariaLabel: string;
  description: string;
  label: string;
  onChange: (value: T) => void;
  options: Array<SelectOption<T>>;
  value: T;
}) {
  return (
    <div className="settings-shadcn-field settings-shadcn-field-select">
      <div className="settings-shadcn-field-copy">
        <strong>{label}</strong>
        <p>{description}</p>
      </div>
      <div className="settings-shadcn-field-control">
        <ShadcnSelect
          ariaLabel={ariaLabel}
          onChange={onChange}
          options={options}
          value={value}
        />
      </div>
    </div>
  );
}

function ThemeModeCard({
  mode,
  isSelected,
  isAvailable,
  onSelect,
}: {
  mode: ThemeMode;
  isSelected: boolean;
  isAvailable: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      className={isSelected ? "theme-card active" : "theme-card"}
      disabled={!isAvailable}
      onClick={onSelect}
      type="button"
    >
      <ThemePreview
        isAvailable={isAvailable}
        isSelected={isSelected}
        mode={mode}
      />
      <div className="theme-card-label">
        <span className="theme-card-icon">{themeModeSymbol(mode)}</span>
        <span>{capitalize(mode)}</span>
      </div>
      {isAvailable ? (
        isSelected ? (
          <span className="theme-card-check">✓</span>
        ) : (
          <span className="theme-card-empty" />
        )
      ) : (
        <small className="theme-card-meta">Coming soon</small>
      )}
    </button>
  );
}

function ThemePreview({
  mode,
  isSelected,
  isAvailable,
}: {
  mode: ThemeMode;
  isSelected: boolean;
  isAvailable: boolean;
}) {
  const previewMode = mode === "light" ? "light" : "dark";

  return (
    <div
      className={[
        "theme-preview",
        `theme-preview-${previewMode}`,
        isSelected ? "selected" : "",
        isAvailable ? "" : "unavailable",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <div className="theme-preview-sidebar">
        <div />
        <div />
        <div />
      </div>
      <div className="theme-preview-main">
        <div />
        <div />
        <div />
      </div>
    </div>
  );
}

function FontSizePresetCard({
  preset,
  isSelected,
  onSelect,
}: {
  preset: FontSizePreset;
  isSelected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      className={
        isSelected ? "settings-option-card active" : "settings-option-card"
      }
      onClick={onSelect}
      type="button"
    >
      <FontSizePreview preset={preset} />
      <div className="settings-option-label">
        <span className="settings-option-icon">
          {fontSizePresetSymbol(preset)}
        </span>
        <span>{capitalize(preset)}</span>
      </div>
      <small>{fontSizePresetDescription(preset)}</small>
      {isSelected ? (
        <span className="settings-option-check">✓</span>
      ) : (
        <span className="settings-option-empty" />
      )}
    </button>
  );
}

function FontSizePreview({ preset }: { preset: FontSizePreset }) {
  return (
    <div className={`font-preview font-preview-${preset}`}>
      <div />
      <div />
      <div />
      <div />
    </div>
  );
}

function CompanyBrandColorField({
  errorMessage,
  isSaving,
  label,
  onChange,
  value,
}: {
  errorMessage: string | null;
  isSaving: boolean;
  label: string;
  onChange: (nextColor: string) => void;
  value: string;
}) {
  return (
    <div className="company-brand-color-field">
      <div className="detail-row">
        <span>{label}</span>
        <div className="company-brand-color-control">
          <label
            className={
              isSaving
                ? "company-brand-color-trigger is-saving"
                : "company-brand-color-trigger"
            }
          >
            <input
              className="company-brand-color-input"
              disabled={isSaving}
              onChange={(event) => onChange(event.target.value)}
              type="color"
              value={value}
            />
            <span
              aria-hidden="true"
              className="company-brand-color-swatch"
              style={{ backgroundColor: value }}
            />
          </label>
          <div className="company-brand-color-copy">
            <strong>{value}</strong>
            <small>
              {isSaving ? "Saving color..." : "Click the swatch to edit"}
            </small>
          </div>
        </div>
      </div>
      {errorMessage ? (
        <p className="company-brand-color-error">{errorMessage}</p>
      ) : null}
    </div>
  );
}

function WorkspaceCenterTabButton({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className={active ? "workspace-tab active" : "workspace-tab"}
      onClick={onClick}
      type="button"
    >
      {label}
    </button>
  );
}

function IssueWorkspaceInspectorMeta({
  agents,
  availableStatusOptions,
  issue,
  issueDraft,
  issueEditorError,
  isSavingIssue,
  onCommitIssuePatch,
  onIssueDraftChange,
  projects,
  selectableParentIssues,
  statusLabel,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  agents: AgentRecord[];
  availableStatusOptions: string[];
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  issueEditorError: string | null;
  isSavingIssue: boolean;
  onCommitIssuePatch: (patch: Partial<IssueEditDraft>) => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  projects: ProjectRecord[];
  selectableParentIssues: IssueRecord[];
  statusLabel: (value: string) => string;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const issueValidationMessage = issueStatusAssigneeValidationMessage(
    issueDraft.status,
    issueDraft.assigneeAgentId,
    agents,
  );
  const visibleIssueEditorError = issueValidationMessage ?? issueEditorError;
  const selectedProject =
    projects.find((project) => project.id === issueDraft.projectId) ?? null;
  const selectedProjectRepoPath =
    selectedProject?.primary_workspace?.cwd ?? null;
  const selectedWorkspaceTargetValue = issueWorkspaceTargetSelectValue(
    issueDraft.workspaceTargetMode,
    issueDraft.workspaceWorktreePath,
  );
  const workspaceTargetHint = issueWorkspaceTargetHint({
    errorMessage: workspaceTargetErrorMessage,
    hasProject: Boolean(selectedProject),
    hasRepoPath: Boolean(selectedProjectRepoPath),
    isLoading: workspaceTargetLoading,
    worktreeCount: workspaceTargetWorktrees.length,
  });
  const fallbackSelectedWorktree =
    selectedWorkspaceTargetValue.startsWith("existing:") &&
    !workspaceTargetWorktrees.some(
      (worktree) =>
        existingWorktreeTargetValue(worktree.path) ===
        selectedWorkspaceTargetValue,
    )
      ? {
          name:
            issueDraft.workspaceWorktreeName ||
            fileName(issueDraft.workspaceWorktreePath),
          path: issueDraft.workspaceWorktreePath,
        }
      : null;

  const commitPropertyPatch = (patch: Partial<IssueEditDraft>) => {
    onIssueDraftChange(patch);
    onCommitIssuePatch(patch);
  };

  return (
    <div className="workspace-issue-sidebar">
      {visibleIssueEditorError ? (
        <div className="issue-dialog-alert">{visibleIssueEditorError}</div>
      ) : null}

      <section className="workspace-issue-sidebar-section">
        <div className="workspace-issue-sidebar-header">
          <span className="route-kicker">Issue</span>
          <h3>{issue.identifier ?? issue.id}</h3>
          <p>{issueDraft.title.trim() || issue.title}</p>
        </div>

        <IssuePropertySelectRow
          disabled={isSavingIssue}
          label="Status"
          onChange={(value) => commitPropertyPatch({ status: value })}
          tone={normalizeBoardIssueValue(issueDraft.status)}
          value={issueDraft.status}
        >
          {availableStatusOptions.map((status) => (
            <option key={status} value={status}>
              {statusLabel(status)}
            </option>
          ))}
        </IssuePropertySelectRow>

        <IssuePropertySelectRow
          disabled={isSavingIssue}
          label="Assignee"
          onChange={(value) =>
            commitPropertyPatch({
              assigneeAgentId: value,
            })
          }
          tone="neutral"
          value={issueDraft.assigneeAgentId}
        >
          <option value="">Unassigned</option>
          {agents.map((agent) => (
            <option key={agent.id} value={agent.id}>
              {agent.name || agent.title || agent.role || agent.id}
            </option>
          ))}
        </IssuePropertySelectRow>

        <IssuePropertySelectRow
          disabled={isSavingIssue}
          label="Project"
          onChange={(value) =>
            commitPropertyPatch({
              projectId: value,
              workspaceTargetMode: "main",
              workspaceWorktreePath: "",
              workspaceWorktreeBranch: "",
              workspaceWorktreeName: "",
            })
          }
          tone="project"
          value={issueDraft.projectId}
        >
          <option disabled value="">
            {projects.length ? "Select project" : "Create project"}
          </option>
          {projects.map((project) => (
            <option key={project.id} value={project.id}>
              {project.name ?? project.title ?? project.id}
            </option>
          ))}
        </IssuePropertySelectRow>

        <IssuePropertySelectRow
          disabled={isSavingIssue || !selectedProjectRepoPath}
          hint={workspaceTargetHint}
          label="Worktree target"
          onChange={(value) =>
            commitPropertyPatch(
              issueWorkspaceDraftPatchFromSelection(
                value,
                workspaceTargetWorktrees,
                issueDraft,
              ),
            )
          }
          tone="neutral"
          value={selectedWorkspaceTargetValue}
        >
          <option value="main">Repo root</option>
          <option value="new_worktree">New git worktree</option>
          {workspaceTargetWorktrees.map((worktree) => (
            <option
              key={worktree.path}
              value={existingWorktreeTargetValue(worktree.path)}
            >
              {worktree.branch
                ? `${worktree.name} · ${worktree.branch}`
                : worktree.name}
            </option>
          ))}
          {fallbackSelectedWorktree ? (
            <option
              value={existingWorktreeTargetValue(fallbackSelectedWorktree.path)}
            >
              {fallbackSelectedWorktree.name}
            </option>
          ) : null}
        </IssuePropertySelectRow>

        <IssuePropertySelectRow
          disabled={isSavingIssue}
          label="Parent"
          onChange={(value) => commitPropertyPatch({ parentId: value })}
          tone="neutral"
          value={issueDraft.parentId}
        >
          <option value="">No parent conversation</option>
          {selectableParentIssues.map((parentIssue) => (
            <option key={parentIssue.id} value={parentIssue.id}>
              {parentIssue.identifier ?? parentIssue.title}
            </option>
          ))}
        </IssuePropertySelectRow>
      </section>

      <section className="workspace-issue-sidebar-section">
        <IssuePropertyStaticRow
          label="Provider"
          value={providerLabelForRuntimeConfig(
            issueDraft.command,
            issueDraft.model,
          )}
        />
        <IssuePropertyStaticRow
          label="Model"
          value={issueDraft.model === "default" ? "Default" : issueDraft.model}
        />
        <IssuePropertyStaticRow
          label="Started"
          value={
            issue.started_at ? formatBoardDate(issue.started_at) : "Not started"
          }
        />
        <IssuePropertyStaticRow
          label="Completed"
          value={
            issue.completed_at
              ? formatBoardDate(issue.completed_at)
              : "Not completed"
          }
        />
        <IssuePropertyStaticRow
          label="Created"
          value={formatBoardDate(issue.created_at)}
        />
        <IssuePropertyStaticRow
          label="Updated"
          value={formatRelativeIssueDate(issue.updated_at)}
        />
      </section>
    </div>
  );
}

function IssueWorkspaceSummaryMeta({
  agents,
  issue,
  projects,
  statusLabel,
}: {
  agents: AgentRecord[];
  issue: IssueRecord;
  projects: ProjectRecord[];
  statusLabel: (value: string) => string;
}) {
  return (
    <div className="workspace-issue-sidebar">
      <section className="workspace-issue-sidebar-section">
        <div className="workspace-issue-sidebar-header">
          <span className="route-kicker">Issue</span>
          <h3>{issue.identifier ?? issue.id}</h3>
          <p>{issue.title}</p>
        </div>
        <IssuePropertyStaticRow
          label="Status"
          value={statusLabel(issue.status)}
        />
        <IssuePropertyStaticRow
          label="Assignee"
          value={issueAssigneeLabel(agents, issue.assignee_agent_id)}
        />
        <IssuePropertyStaticRow
          label="Project"
          value={issueProjectLabel(projects, issue.project_id)}
        />
        <IssuePropertyStaticRow
          label="Updated"
          value={formatRelativeIssueDate(issue.updated_at)}
        />
      </section>
    </div>
  );
}

function WorkspaceSidebarTabButton({
  active,
  count,
  label,
  onClick,
}: {
  active: boolean;
  count?: number;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className={
        active ? "workspace-sidebar-tab active" : "workspace-sidebar-tab"
      }
      onClick={onClick}
      type="button"
    >
      <span>{label}</span>
      {count ? <small>{count}</small> : null}
    </button>
  );
}

export function WorkspaceInspectorSidebar({
  currentBranch,
  currentBranchName,
  currentDirectory,
  fileEntries,
  gitCommitMessage,
  gitHistory,
  gitState,
  hasUncommittedChanges,
  issueMeta,
  hasUnpushedCommits,
  isWorking,
  selectedDiff,
  selectedFilePath,
  workspace,
  workspaceSidebarTab,
  onDiscardFile,
  onGitCommit,
  onGitCommitMessageChange,
  onGitPush,
  onOpenDiff,
  onOpenDirectory,
  onOpenFile,
  onSelectSidebarTab,
  onStageFile,
  onUnstageFile,
}: {
  currentBranch: GitBranchesResult["local"][number] | null;
  currentBranchName: string;
  currentDirectory: string | null;
  fileEntries: FileEntry[];
  gitCommitMessage: string;
  gitHistory: GitLogResult | null;
  gitState: GitStatusResult | null;
  hasUncommittedChanges: boolean;
  issueMeta?: ReactNode;
  hasUnpushedCommits: boolean;
  isWorking: boolean;
  selectedDiff: GitDiffResult | null;
  selectedFilePath: string | null;
  workspace: WorkspaceRecord | null;
  workspaceSidebarTab: WorkspaceSidebarTab;
  onDiscardFile: (file: GitStatusFile) => void;
  onGitCommit: (push: boolean) => void;
  onGitCommitMessageChange: (value: string) => void;
  onGitPush: () => void;
  onOpenDiff: (path: string) => void;
  onOpenDirectory: (path: string) => void;
  onOpenFile: (path: string) => void;
  onSelectSidebarTab: (tab: WorkspaceSidebarTab) => void;
  onStageFile: (file: GitStatusFile) => void;
  onUnstageFile: (file: GitStatusFile) => void;
}) {
  const [isActionMenuOpen, setIsActionMenuOpen] = useState(false);
  const showWorkspaceDetails = Boolean(workspace && !issueMeta);
  const workspaceDetails = showWorkspaceDetails ? workspace : null;
  const headerActionMode = hasUncommittedChanges
    ? ("commit" as const)
    : hasUnpushedCommits
      ? ("push" as const)
      : ("disabledCommit" as const);
  const canCommit = !isWorking && gitCommitMessage.trim().length > 0;
  const canPush = !isWorking && hasUnpushedCommits;

  useEffect(() => {
    setIsActionMenuOpen(false);
  }, [headerActionMode]);

  useEffect(() => {
    if (!isActionMenuOpen) {
      return;
    }

    const closeMenu = () => {
      setIsActionMenuOpen(false);
    };

    window.addEventListener("pointerdown", closeMenu);
    return () => {
      window.removeEventListener("pointerdown", closeMenu);
    };
  }, [isActionMenuOpen]);

  return (
    <aside className="workspace-inspector">
      {workspaceDetails ? (
        <section className="inspector-panel workspace-details-panel">
          <h3>Workspace Details</h3>
          <div className="workspace-detail-grid">
            <DetailRow
              label="Conversation"
              value={
                workspaceDetails.issue_identifier ??
                workspaceDetails.issue_id ??
                "Missing"
              }
            />
            <DetailRow
              label="Agent"
              value={
                workspaceDetails.agent_name ??
                workspaceDetails.agent_id ??
                "Missing"
              }
            />
            <DetailRow
              label="Project"
              value={
                workspaceDetails.project_name ??
                workspaceDetails.project_id ??
                "Missing"
              }
            />
            <DetailRow
              label="Branch"
              value={workspaceDetails.workspace_branch ?? "main"}
            />
            <DetailRow
              label="Repo"
              value={workspaceDetails.workspace_repo_path ?? "Missing"}
            />
          </div>
        </section>
      ) : null}

      {workspaceDetails ? <div className="workspace-sidebar-divider" /> : null}

      <section className="inspector-panel workspace-git-panel">
        <div className="git-sidebar-header">
          <div className="git-branch-pill">
            <span>{currentBranchName}</span>
            {currentBranch ? (
              <small>
                {currentBranch.ahead > 0 ? `+${currentBranch.ahead}` : ""}
                {currentBranch.ahead > 0 && currentBranch.behind > 0 ? " " : ""}
                {currentBranch.behind > 0 ? `-${currentBranch.behind}` : ""}
              </small>
            ) : null}
          </div>

          <div
            className="git-sidebar-actions"
            onPointerDown={(event) => event.stopPropagation()}
          >
            {headerActionMode === "commit" ? (
              <div className="git-header-split-button-shell">
                <div
                  className={
                    canCommit
                      ? "git-header-split-button"
                      : "git-header-split-button disabled"
                  }
                >
                  <button
                    className="git-header-split-button-primary"
                    disabled={!canCommit}
                    onClick={() => onGitCommit(false)}
                    type="button"
                  >
                    Commit
                  </button>
                  <button
                    aria-expanded={isActionMenuOpen}
                    aria-label="Commit actions"
                    className="git-header-split-button-toggle"
                    disabled={!canCommit}
                    onClick={() => setIsActionMenuOpen((current) => !current)}
                    type="button"
                  >
                    ▾
                  </button>
                </div>
                {isActionMenuOpen ? (
                  <div className="git-header-dropdown-menu">
                    <button
                      className="git-header-dropdown-item"
                      disabled={!canCommit}
                      onClick={() => {
                        setIsActionMenuOpen(false);
                        onGitCommit(true);
                      }}
                      type="button"
                    >
                      Commit + Push
                    </button>
                  </div>
                ) : null}
              </div>
            ) : headerActionMode === "push" ? (
              <button
                aria-label="Push changes"
                className="git-header-push-button"
                disabled={!canPush}
                onClick={onGitPush}
                type="button"
              >
                Push
              </button>
            ) : (
              <div className="git-header-split-button disabled">
                <button
                  className="git-header-split-button-primary"
                  disabled
                  type="button"
                >
                  Commit
                </button>
                <button
                  className="git-header-split-button-toggle"
                  disabled
                  type="button"
                >
                  ▾
                </button>
              </div>
            )}
          </div>
        </div>

        <div className="workspace-sidebar-tabs">
          <WorkspaceSidebarTabButton
            active={workspaceSidebarTab === "changes"}
            count={gitState?.files.length ?? 0}
            label="Changes"
            onClick={() => onSelectSidebarTab("changes")}
          />
          <WorkspaceSidebarTabButton
            active={workspaceSidebarTab === "files"}
            label="Files"
            onClick={() => onSelectSidebarTab("files")}
          />
          <WorkspaceSidebarTabButton
            active={workspaceSidebarTab === "commits"}
            label="Commits"
            onClick={() => onSelectSidebarTab("commits")}
          />
          {issueMeta ? (
            <WorkspaceSidebarTabButton
              active={workspaceSidebarTab === "issue"}
              label="Issue"
              onClick={() => onSelectSidebarTab("issue")}
            />
          ) : null}
        </div>

        {workspaceSidebarTab === "changes" ? (
          <div className="workspace-sidebar-content">
            <label className="git-commit-field">
              <span>Commit message</span>
              <input
                onChange={(event) =>
                  onGitCommitMessageChange(event.target.value)
                }
                placeholder="Describe this change"
                value={gitCommitMessage}
              />
            </label>

            <GitChangeSection
              activePath={selectedDiff ? selectedFilePath : null}
              files={(gitState?.files ?? []).filter((file) => file.staged)}
              onDiscard={(file) => onDiscardFile(file)}
              onOpen={(file) => onOpenDiff(file.path)}
              onPrimaryAction={(file) => onUnstageFile(file)}
              primaryActionLabel="Unstage"
              title="Staged"
            />
            <GitChangeSection
              activePath={selectedDiff ? selectedFilePath : null}
              files={(gitState?.files ?? []).filter((file) => !file.staged)}
              onDiscard={(file) => onDiscardFile(file)}
              onOpen={(file) => onOpenDiff(file.path)}
              onPrimaryAction={(file) => onStageFile(file)}
              primaryActionLabel="Stage"
              title="Working Tree"
            />
          </div>
        ) : null}

        {workspaceSidebarTab === "files" ? (
          <div className="workspace-sidebar-content">
            <div className="inspector-header">
              <h3>Repository Files</h3>
              {currentDirectory ? (
                <button
                  className="secondary-button compact-button"
                  onClick={() => {
                    const parent = currentDirectory
                      .split("/")
                      .slice(0, -1)
                      .join("/");
                    onOpenDirectory(parent);
                  }}
                  type="button"
                >
                  Up
                </button>
              ) : null}
            </div>
            <div className="surface-list dense">
              {fileEntries.map((entry) => (
                <button
                  className="file-list-button"
                  key={entry.path}
                  onClick={() =>
                    entry.is_dir
                      ? onOpenDirectory(entry.path)
                      : onOpenFile(entry.path)
                  }
                  type="button"
                >
                  <strong>
                    {entry.is_dir ? `${entry.name}/` : entry.name}
                  </strong>
                  <span>{entry.path}</span>
                </button>
              ))}
            </div>
          </div>
        ) : null}

        {workspaceSidebarTab === "commits" ? (
          <div className="workspace-sidebar-content">
            <div className="summary-grid">
              <SummaryPill label="Branch" value={currentBranchName} />
              <SummaryPill
                label="Changed"
                value={gitState?.files.length ?? 0}
              />
              <SummaryPill
                label="Clean"
                value={gitState?.is_clean ? "yes" : "no"}
              />
            </div>
            <div className="surface-list dense">
              {(gitHistory?.commits ?? []).map((commit) => (
                <article className="commit-row" key={commit.oid}>
                  <div>
                    <strong>{commit.summary}</strong>
                    <span>
                      {commit.short_oid} · {commit.author_name} ·{" "}
                      {formatRelativeTimestamp(commit.author_time)}
                    </span>
                  </div>
                </article>
              ))}
            </div>
          </div>
        ) : null}

        {workspaceSidebarTab === "issue" && issueMeta ? (
          <div className="workspace-sidebar-content workspace-sidebar-issue-content">
            {issueMeta}
          </div>
        ) : null}
      </section>
    </aside>
  );
}

function CompanyContextMenuIcon({
  className = "company-context-menu-icon",
  icon,
}: {
  className?: string;
  icon: CompanyContextMenuIconKey;
}) {
  switch (icon) {
    case "dashboard":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M2.5 3.25h11v9.5h-11z"
            rx="2"
            stroke="currentColor"
            strokeWidth="1.4"
          />
          <path
            d="M2.75 6.25h10.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.4"
          />
          <path
            d="M5.25 2.5v1.5M10.75 2.5v1.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.4"
          />
        </svg>
      );
    case "issues":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M4 3.25h8A1.75 1.75 0 0 1 13.75 5v6A1.75 1.75 0 0 1 12 12.75H4A1.75 1.75 0 0 1 2.25 11V5A1.75 1.75 0 0 1 4 3.25Z"
            stroke="currentColor"
            strokeWidth="1.4"
          />
          <path
            d="M5.25 6h5.5M5.25 8.5h5.5M5.25 11h3"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.4"
          />
        </svg>
      );
    case "approvals":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M8 2.5 12 4v3.6c0 2.1-1.1 4.04-4 5.9-2.9-1.86-4-3.8-4-5.9V4Z"
            stroke="currentColor"
            strokeLinejoin="round"
            strokeWidth="1.3"
          />
          <path
            d="m6.3 7.95 1.15 1.15 2.35-2.45"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.3"
          />
        </svg>
      );
    case "agents":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M8 3.25a2.25 2.25 0 1 1 0 4.5a2.25 2.25 0 0 1 0-4.5ZM4.25 12.25c.35-1.67 1.88-2.75 3.75-2.75s3.4 1.08 3.75 2.75"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.4"
          />
          <path
            d="M2.75 6.25a1.75 1.75 0 1 1 0 3.5M13.25 6.25a1.75 1.75 0 1 0 0 3.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.2"
          />
        </svg>
      );
    case "stats":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M3 12.75V8.5M8 12.75V3.75M13 12.75V6.25"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.5"
          />
          <path
            d="M2.25 12.75h11.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.3"
          />
        </svg>
      );
    case "activity":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M2 9h2l1.4-3.25L8.1 11l1.85-4L11 9h3"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.35"
          />
        </svg>
      );
    case "costs":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M8 2.5c2.1 0 3.75.87 3.75 2s-1.65 2-3.75 2-3.75-.87-3.75-2 1.65-2 3.75-2Z"
            stroke="currentColor"
            strokeWidth="1.3"
          />
          <path
            d="M4.25 4.5v2.5c0 1.1 1.65 2 3.75 2s3.75-.9 3.75-2V4.5"
            stroke="currentColor"
            strokeWidth="1.3"
          />
          <path
            d="M4.25 7v2.5c0 1.1 1.65 2 3.75 2s3.75-.9 3.75-2V7"
            stroke="currentColor"
            strokeWidth="1.3"
          />
        </svg>
      );
    case "companySettings":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M8 4.75a3.25 3.25 0 1 1 0 6.5a3.25 3.25 0 0 1 0-6.5Z"
            stroke="currentColor"
            strokeWidth="1.4"
          />
          <path
            d="M8 1.75v1.5M8 12.75v1.5M13.25 8h1.5M1.25 8h1.5M11.72 4.28l1.06-1.06M3.22 12.78l1.06-1.06M11.72 11.72l1.06 1.06M3.22 3.22l1.06 1.06"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.4"
          />
        </svg>
      );
  }
}

function GitChangeSection({
  title,
  files,
  activePath,
  primaryActionLabel,
  onOpen,
  onPrimaryAction,
  onDiscard,
}: {
  title: string;
  files: GitStatusFile[];
  activePath: string | null;
  primaryActionLabel: string;
  onOpen: (file: GitStatusFile) => void;
  onPrimaryAction: (file: GitStatusFile) => void;
  onDiscard: (file: GitStatusFile) => void;
}) {
  if (!files.length) {
    return null;
  }

  return (
    <section className="git-change-group">
      <div className="git-change-group-header">
        <h3>{title}</h3>
        <span>{files.length}</span>
      </div>
      <div className="surface-list dense">
        {files.map((file) => (
          <div
            className={
              activePath === file.path
                ? "git-change-row active"
                : "git-change-row"
            }
            key={`${title}:${file.path}`}
            onClick={() => onOpen(file)}
            onKeyDown={(event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onOpen(file);
              }
            }}
            role="button"
            tabIndex={0}
          >
            <div className="git-change-row-main">
              <span
                className={`git-status-badge ${file.status ? `status-${file.status}` : ""}`}
              >
                {gitStatusBadge(file.status)}
              </span>
              <div>
                <strong>{fileName(file.path)}</strong>
                <span>{parentPath(file.path)}</span>
              </div>
            </div>
            <div
              className="git-change-actions"
              onClick={(event) => event.stopPropagation()}
            >
              <button
                className="secondary-button compact-button"
                onClick={() => onPrimaryAction(file)}
                type="button"
              >
                {primaryActionLabel}
              </button>
              {file.staged ? null : (
                <button
                  className="secondary-button compact-button destructive-button"
                  onClick={() => onDiscard(file)}
                  type="button"
                >
                  Discard
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function screenLabel(screen: AppScreen): string {
  switch (screen) {
    case "dashboard":
      return "Dashboard";
    case "stats":
      return "Stats";
    case "agents":
      return "Agents";
    case "issues":
      return "Conversations";
    case "approvals":
      return "Approvals";
    case "projects":
      return "Projects";
    case "activity":
      return "Activity";
    case "costs":
      return "Costs";
    case "companySettings":
    case "appSettings":
      return "Settings";
  }

  return "Dashboard";
}

function sidebarScreenIcon(
  screen: AppScreen,
): CompanyContextMenuIconKey | null {
  switch (screen) {
    case "dashboard":
      return "dashboard";
    case "issues":
      return "issues";
    case "approvals":
      return "approvals";
    case "stats":
      return "stats";
    case "activity":
      return "activity";
    case "costs":
      return "costs";
    case "companySettings":
      return "companySettings";
    default:
      return null;
  }
}

function sidebarAgentAvatarLabel(agent: AgentRecord) {
  const parts = orgChartAgentName(agent).split(/\s+/).filter(Boolean);
  if (parts.length === 0) {
    return "A";
  }

  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }

  return `${parts[0][0] ?? ""}${parts[1][0] ?? ""}`.toUpperCase();
}

function boardRootLayout(screen: AppScreen): BoardRootLayout {
  if (screen === "appSettings") {
    return "settings";
  }

  return "companyDashboard";
}

function preferredViewForScreen(screen: AppScreen) {
  if (screen === "activity") {
    return "activity";
  }

  if (screen === "costs") {
    return "costs";
  }

  if (screen === "appSettings") {
    return "settings";
  }

  if (screen === "companySettings") {
    return "company_settings";
  }

  if (screen === "stats") {
    return "stats";
  }

  return "dashboard";
}

function normalizeScreen(view: string | null | undefined): AppScreen {
  if (view === "settings") {
    return "appSettings";
  }

  if (view === "org") {
    return "dashboard";
  }

  if (view === "activity") {
    return "activity";
  }

  if (view === "costs") {
    return "costs";
  }

  if (view === "company_settings") {
    return "companySettings";
  }

  if (view === "stats") {
    return "stats";
  }

  if (view === "workspace" || view === "workspaces") {
    return "dashboard";
  }

  return "dashboard";
}

function preferredViewSelectValue(
  view: string | null | undefined,
): DesktopPreferredViewValue {
  if (view === "settings") {
    return "settings";
  }

  if (view === "org") {
    return "dashboard";
  }

  if (view === "activity") {
    return "activity";
  }

  if (view === "costs") {
    return "costs";
  }

  if (view === "stats") {
    return "stats";
  }

  if (view === "workspace" || view === "workspaces") {
    return "dashboard";
  }

  return "dashboard";
}

function mergeDesktopSettings(settings: DesktopSettings): DesktopSettings {
  return {
    ...defaultSettings,
    ...settings,
    dashboard_project_views: settings.dashboard_project_views ?? {},
    birds_eye_canvas: settings.birds_eye_canvas ?? {},
  };
}

function settingsSectionIcon(section: SettingsSection) {
  switch (section) {
    case "general":
      return "gear";
    case "appearance":
      return "paintbrush";
    case "notifications":
      return "bell";
    case "privacy":
      return "shield";
  }
}

function symbolForSettingsIcon(icon: string) {
  switch (icon) {
    case "house":
      return "⌂";
    case "gear":
      return "⚙";
    case "folder":
      return "▣";
    case "paintbrush":
      return "◐";
    case "bell":
      return "◔";
    case "shield":
      return "⛨";
    default:
      return "•";
  }
}

function themeModeSymbol(mode: ThemeMode) {
  switch (mode) {
    case "system":
      return "◐";
    case "light":
      return "☀";
    case "dark":
      return "☾";
  }
}

function fontSizePresetSymbol(preset: FontSizePreset) {
  switch (preset) {
    case "small":
      return "A−";
    case "medium":
      return "A";
    case "large":
      return "A+";
  }
}

function fontSizePresetDescription(preset: FontSizePreset) {
  switch (preset) {
    case "small":
      return "Compact interface";
    case "medium":
      return "Default size";
    case "large":
      return "Larger text and UI";
  }
}

function capitalize(value: string) {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}

function createEmptyIssueDraft(): IssueEditDraft {
  const runtimeDraft = createDefaultIssueRuntimeDraft(null);
  return {
    ...runtimeDraft,
    title: "",
    description: "",
    status: "todo",
    priority: "medium",
    projectId: "",
    assigneeAgentId: "",
    parentId: "",
    workspaceTargetMode: "main",
    workspaceWorktreePath: "",
    workspaceWorktreeBranch: "",
    workspaceWorktreeName: "",
  };
}

function createIssueDraft(issue: IssueRecord): IssueEditDraft {
  const workspaceDraft = parseIssueExecutionWorkspaceSettings(
    issue.execution_workspace_settings,
  );
  const runtimeDraft = parseIssueAdapterOverrides(
    issue.assignee_adapter_overrides,
  );

  return {
    ...runtimeDraft,
    title: issue.title,
    description: issue.description ?? "",
    status: normalizeBoardIssueValue(issue.status),
    priority: issue.priority,
    projectId: issue.project_id ?? "",
    assigneeAgentId: issue.assignee_agent_id ?? "",
    parentId: issue.parent_id ?? "",
    ...workspaceDraft,
  };
}

function createEmptyAgentConfigDraft(): AgentConfigDraft {
  return {
    name: "",
    title: "",
    capabilities: "",
    promptTemplate: "",
    adapterType: "process",
    workingDirectory: "",
    instructionsPath: "",
    command: "claude",
    model: "default",
    thinkingEffort: "auto",
    bootstrapPrompt: "",
    enableChrome: false,
    skipPermissions: false,
    maxTurns: "",
    extraArgs: "",
    envVars: [],
    timeoutSec: "",
    interruptGraceSec: "",
    canCreateAgents: false,
    monthlyBudget: "",
  };
}

function createAgentConfigDraft(agent: AgentRecord): AgentConfigDraft {
  const adapterConfig = objectFromUnknown(agent.adapter_config);
  const runtimeConfig = objectFromUnknown(agent.runtime_config);
  const permissions = objectFromUnknown(agent.permissions);
  const metadata = objectFromUnknown(agent.metadata);

  return {
    name: agent.name ?? "",
    title: agent.title ?? "",
    capabilities: agent.capabilities ?? "",
    promptTemplate: stringFromUnknown(metadata.promptTemplate),
    adapterType: stringFromUnknown(agent.adapter_type, "process"),
    workingDirectory: agent.home_path ?? "",
    instructionsPath: agent.instructions_path ?? "",
    command: stringFromUnknown(adapterConfig.command, "claude"),
    model: stringFromUnknown(adapterConfig.model, "default"),
    thinkingEffort: stringFromUnknown(
      adapterConfig.thinkingEffort ?? adapterConfig.reasoningEffort,
      "auto",
    ),
    bootstrapPrompt: stringFromUnknown(runtimeConfig.bootstrapPrompt),
    enableChrome: booleanFromUnknown(adapterConfig.enableChrome),
    skipPermissions: booleanFromUnknown(adapterConfig.skipPermissions),
    maxTurns: numericInputValue(runtimeConfig.maxTurns),
    extraArgs: arrayFromUnknown(adapterConfig.extraArgs)
      .map((value) => stringFromUnknown(value))
      .filter(Boolean)
      .join(", "),
    envVars: parseAgentConfigEnvVars(
      adapterConfig.environmentVariables ?? adapterConfig.envVars,
    ),
    timeoutSec: numericInputValue(runtimeConfig.timeoutSec),
    interruptGraceSec: numericInputValue(runtimeConfig.interruptGraceSec),
    canCreateAgents: booleanFromUnknown(permissions.canCreateAgents),
    monthlyBudget: budgetInputValue(agent.budget_monthly_cents),
  };
}

function createAgentConfigEnvVarDraft(
  value?: Partial<AgentConfigEnvVarDraft>,
): AgentConfigEnvVarDraft {
  return {
    id:
      value?.id ??
      (typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : `env-${Math.random().toString(36).slice(2, 10)}`),
    key: value?.key ?? "",
    value: value?.value ?? "",
    mode: value?.mode ?? "plain",
  };
}

function buildAgentConfigUpdateParams(
  agent: AgentRecord,
  draft: AgentConfigDraft,
) {
  const adapterConfig = {
    ...objectFromUnknown(agent.adapter_config),
    command: normalizeOptionalDraftString(draft.command) ?? "claude",
    model: normalizeOptionalDraftString(draft.model) ?? "default",
    thinkingEffort:
      normalizeOptionalDraftString(draft.thinkingEffort) ?? "auto",
    reasoningEffort:
      normalizeOptionalDraftString(draft.thinkingEffort) ?? "auto",
    enableChrome: draft.enableChrome,
    skipPermissions: draft.skipPermissions,
  } as Record<string, unknown>;
  const extraArgs = commaSeparatedValues(draft.extraArgs);
  if (extraArgs.length) {
    adapterConfig.extraArgs = extraArgs;
  } else {
    delete adapterConfig.extraArgs;
  }
  const envVars = serializeAgentConfigEnvVars(draft.envVars);
  if (envVars.length) {
    adapterConfig.environmentVariables = envVars;
  } else {
    delete adapterConfig.environmentVariables;
  }

  const runtimeConfig = {
    ...objectFromUnknown(agent.runtime_config),
  } as Record<string, unknown>;
  delete runtimeConfig.heartbeat;
  delete runtimeConfig.heartbeatConfig;
  delete runtimeConfig.intervalSec;
  delete runtimeConfig.maxTurns;
  const timeoutSec = integerFromDraft(draft.timeoutSec);
  if (timeoutSec !== undefined) {
    runtimeConfig.timeoutSec = timeoutSec;
  } else {
    delete runtimeConfig.timeoutSec;
  }
  const interruptGraceSec = integerFromDraft(draft.interruptGraceSec);
  if (interruptGraceSec !== undefined) {
    runtimeConfig.interruptGraceSec = interruptGraceSec;
  } else {
    delete runtimeConfig.interruptGraceSec;
  }
  const bootstrapPrompt = normalizeOptionalDraftString(draft.bootstrapPrompt);
  if (bootstrapPrompt) {
    runtimeConfig.bootstrapPrompt = bootstrapPrompt;
  } else {
    delete runtimeConfig.bootstrapPrompt;
  }

  const permissions = {
    ...objectFromUnknown(agent.permissions),
    canCreateAgents: draft.canCreateAgents,
  };

  const metadata = {
    ...objectFromUnknown(agent.metadata),
  } as Record<string, unknown>;
  const promptTemplate = normalizeOptionalDraftString(draft.promptTemplate);
  if (promptTemplate) {
    metadata.promptTemplate = promptTemplate;
  } else {
    delete metadata.promptTemplate;
  }

  return {
    agent_id: agent.id,
    name: draft.name.trim(),
    title: normalizeOptionalDraftString(draft.title),
    capabilities: normalizeOptionalDraftString(draft.capabilities),
    adapter_type: normalizeOptionalDraftString(draft.adapterType) ?? "process",
    adapter_config: adapterConfig,
    runtime_config: runtimeConfig,
    budget_monthly_cents: budgetInputToCents(draft.monthlyBudget),
    permissions,
    metadata: Object.keys(metadata).length ? metadata : null,
    home_path: normalizeOptionalDraftString(draft.workingDirectory),
    instructions_path: normalizeOptionalDraftString(draft.instructionsPath),
  };
}

function parseAgentConfigEnvVars(value: unknown): AgentConfigEnvVarDraft[] {
  return arrayFromUnknown(value)
    .map((entry) => {
      const record = objectFromUnknown(entry);
      const key = stringFromUnknown(record.key);
      const envValue = stringFromUnknown(record.value);
      if (!(key || envValue)) {
        return null;
      }
      return createAgentConfigEnvVarDraft({
        key,
        value: envValue,
        mode:
          booleanFromUnknown(record.secret) ||
          stringFromUnknown(record.mode) === "secret"
            ? "secret"
            : "plain",
      });
    })
    .filter((entry): entry is AgentConfigEnvVarDraft => entry !== null);
}

function serializeAgentConfigEnvVars(envVars: AgentConfigEnvVarDraft[]) {
  return envVars
    .map((envVar) => ({
      key: envVar.key.trim(),
      value: envVar.value,
      mode: envVar.mode,
      secret: envVar.mode === "secret",
    }))
    .filter((envVar) => envVar.key.length > 0 || envVar.value.length > 0);
}

function objectFromUnknown(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return value as Record<string, unknown>;
}

function arrayFromUnknown(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringFromUnknown(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function booleanFromUnknown(value: unknown) {
  return value === true;
}

function numberFromUnknown(value: unknown) {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

function normalizeProjectDefaultNewChatArea(
  value: unknown,
): ProjectDefaultNewChatArea {
  return value === "new_worktree" ? "new_worktree" : "repo_root";
}

function projectExecutionWorkspacePolicy(
  project: ProjectRecord | null | undefined,
) {
  return objectFromUnknown(project?.execution_workspace_policy);
}

function projectDefaultNewChatArea(
  project: ProjectRecord | null | undefined,
): ProjectDefaultNewChatArea {
  return normalizeProjectDefaultNewChatArea(
    projectExecutionWorkspacePolicy(project).default_new_chat_area,
  );
}

function projectDefaultNewChatAreaLabel(value: ProjectDefaultNewChatArea) {
  return value === "new_worktree" ? "New worktree" : "Repo root";
}

function projectDefaultNewChatWorkspaceDefaults(
  project: ProjectRecord | null | undefined,
): Pick<
  IssueEditDraft,
  | "workspaceTargetMode"
  | "workspaceWorktreePath"
  | "workspaceWorktreeBranch"
  | "workspaceWorktreeName"
> {
  const defaultArea = projectDefaultNewChatArea(project);
  return {
    workspaceTargetMode:
      defaultArea === "new_worktree" ? "new_worktree" : "main",
    workspaceWorktreePath: "",
    workspaceWorktreeBranch: "",
    workspaceWorktreeName: "",
  };
}

function projectExecutionWorkspacePolicyWithDefaultNewChatArea(
  project: ProjectRecord | null | undefined,
  defaultNewChatArea: ProjectDefaultNewChatArea,
) {
  return {
    ...projectExecutionWorkspacePolicy(project),
    default_new_chat_area: defaultNewChatArea,
  };
}

function numericInputValue(value: unknown) {
  return typeof value === "number" && Number.isFinite(value)
    ? String(value)
    : "";
}

function budgetInputValue(value: number | null | undefined) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return "";
  }

  const dollars = value / 100;
  return Number.isInteger(dollars) ? String(dollars) : dollars.toFixed(2);
}

function budgetInputToCents(value: string) {
  const amount = Number.parseFloat(value.trim());
  if (!Number.isFinite(amount) || amount <= 0) {
    return 0;
  }

  return Math.round(amount * 100);
}

function integerFromDraft(value: string) {
  const parsed = Number.parseInt(value.trim(), 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : undefined;
}

function commaSeparatedValues(value: string) {
  return value
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function normalizeOptionalDraftString(value: string) {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function issuesListTabTitle(tab: IssuesListTab) {
  return tab === "new" ? "New" : "All";
}

function mergeIssueOptions(defaults: string[], selected: string) {
  const trimmedSelected = selected.trim();
  const options = trimmedSelected ? [trimmedSelected] : [];
  for (const value of defaults) {
    if (!options.includes(value)) {
      options.push(value);
    }
  }
  return options;
}

type AgentCliProvider = "claude" | "codex" | "custom";

const fallbackClaudeModelOptions = ["sonnet", "opus", "haiku"];
const fallbackCodexModelOptions = [
  "gpt-5.3-codex",
  "gpt-5.2-codex",
  "gpt-5.1-codex-max",
  "gpt-5.1-codex",
  "gpt-5.1-codex-mini",
  "gpt-5-codex",
  "codex-mini-latest",
];

function detectAgentCliProvider(
  command: string | null | undefined,
  model?: string | null,
): AgentCliProvider {
  const normalizedCommand = normalizeAgentCommand(command);
  const normalizedModel = (model ?? "").trim().toLowerCase();

  if (
    normalizedCommand.includes("codex") ||
    normalizedModel.includes("codex")
  ) {
    return "codex";
  }

  if (
    !normalizedCommand ||
    normalizedCommand.includes("claude") ||
    normalizedModel.includes("claude")
  ) {
    return "claude";
  }

  return "custom";
}

function normalizeAgentCommand(value: string | null | undefined) {
  const trimmed = value?.trim().toLowerCase() ?? "";
  if (!trimmed) {
    return "";
  }

  return trimmed.split(/[\\/]/).pop() ?? trimmed;
}

function buildAgentCommandOptions(
  dependencyCheck: RuntimeCapabilities | null,
  selectedCommand: string,
) {
  const options: string[] = [];

  const pushOption = (value: string | null | undefined) => {
    const trimmed = value?.trim();
    if (trimmed && !options.includes(trimmed)) {
      options.push(trimmed);
    }
  };

  pushOption(selectedCommand);
  pushOption("claude");
  pushOption(dependencyCheck?.cli.claude.path);
  pushOption("codex");
  pushOption(dependencyCheck?.cli.codex.path);

  return options;
}

function buildIssueRuntimeProviderOptions(
  dependencyCheck: RuntimeCapabilities | null,
  command: string,
  model: string,
) {
  const options: Array<{ label: string; value: string }> = [];
  const seen = new Set<string>();

  const pushOption = (provider: AgentCliProvider) => {
    if (provider !== "claude" && provider !== "codex") {
      return;
    }
    const value = defaultIssueRuntimeCommandForProvider(
      provider,
      dependencyCheck,
    );
    if (seen.has(value)) {
      return;
    }
    seen.add(value);
    options.push({
      label: provider === "codex" ? "Codex" : "Claude",
      value,
    });
  };

  pushOption(detectAgentCliProvider(command, model));
  pushOption("claude");
  pushOption("codex");

  return options;
}

function buildProviderModelCatalog(
  provider: AgentCliProvider,
  dependencyCheck: RuntimeCapabilities | null,
) {
  const discoveredModels =
    provider === "codex"
      ? dependencyCheck?.cli.codex.installed
        ? (dependencyCheck?.cli.codex.models ?? [])
        : []
      : provider === "claude"
        ? dependencyCheck?.cli.claude.installed
          ? (dependencyCheck?.cli.claude.models ?? [])
          : []
        : [];
  const fallbackModels =
    provider === "codex"
      ? fallbackCodexModelOptions
      : provider === "claude"
        ? fallbackClaudeModelOptions
        : [];

  return [
    "default",
    ...(discoveredModels.length ? discoveredModels : fallbackModels),
  ];
}

function runtimeDraftPatchForProviderSelection(
  command: string,
  draft: Pick<IssueRuntimeDraft, "model" | "planMode">,
  dependencyCheck: RuntimeCapabilities | null,
) {
  const provider = detectAgentCliProvider(command);
  const availableModels = buildProviderModelCatalog(provider, dependencyCheck);
  const model = availableModels.includes(draft.model) ? draft.model : "default";

  return {
    command,
    model,
    planMode: provider === "claude" ? draft.planMode : false,
  };
}

function buildAgentModelOptions(
  draft: Pick<IssueRuntimeDraft, "command" | "model">,
  dependencyCheck: RuntimeCapabilities | null,
) {
  const provider = detectAgentCliProvider(draft.command, draft.model);

  return mergeIssueOptions(
    buildProviderModelCatalog(provider, dependencyCheck),
    draft.model,
  );
}

function detectWorkspaceAgentProvider(
  session: SessionRecord | null,
  agent: AgentRecord | null,
): AgentCliProvider {
  if (session?.provider) {
    return session.provider === "codex" ? "codex" : "claude";
  }

  if (agent) {
    const adapterConfig = objectFromUnknown(agent.adapter_config);
    return detectAgentCliProvider(
      stringFromUnknown(adapterConfig.command),
      stringFromUnknown(adapterConfig.model),
    );
  }

  return "claude";
}

const canonicalIssueStatuses = [
  "backlog",
  "blocked",
  "todo",
  "in_progress",
  "done",
  "cancelled",
];

function issueStatusAssigneeValidationMessage(
  status: string | null | undefined,
  assigneeAgentId: string | null | undefined,
  agents: AgentRecord[],
) {
  void status;
  void assigneeAgentId;
  void agents;
  return null;
}

function normalizeHexColor(
  value: string | null | undefined,
  fallback = defaultCompanyBrandColor,
) {
  const trimmed = value?.trim() ?? "";
  const candidate = trimmed.startsWith("#") ? trimmed : `#${trimmed}`;
  if (/^#[0-9a-fA-F]{6}$/.test(candidate)) {
    return candidate.toUpperCase();
  }

  return fallback;
}

function companyRailForegroundColor(value: string | null | undefined) {
  const normalized = normalizeHexColor(value);
  const red = Number.parseInt(normalized.slice(1, 3), 16);
  const green = Number.parseInt(normalized.slice(3, 5), 16);
  const blue = Number.parseInt(normalized.slice(5, 7), 16);
  const perceivedBrightness = (red * 299 + green * 587 + blue * 114) / 1000;

  return perceivedBrightness >= 170 ? "#081018" : "#FFFFFF";
}

function normalizeBoardIssueValue(value: string | null | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) {
    return "backlog";
  }

  const normalized = trimmed.toLowerCase().replaceAll(" ", "_");
  if (normalized === "canceled") {
    return "cancelled";
  }

  return normalized;
}

function normalizeDashboardProjectGrouping(
  value: string | null | undefined,
): DashboardProjectGrouping {
  void value;
  return "status";
}

function useBirdsEyeCodeImpact(sessionIds: string[]) {
  const [summaries, setSummaries] = useState<
    Record<string, BirdsEyeCodeImpactSummary>
  >({});
  const sortedSessionIds = useMemo(
    () =>
      [...new Set(sessionIds)].sort((left, right) => left.localeCompare(right)),
    [sessionIds],
  );
  const missingSessionIds = useMemo(
    () =>
      sortedSessionIds.filter(
        (sessionId) => summaries[sessionId] === undefined,
      ),
    [sortedSessionIds, summaries],
  );
  const missingSessionKey = missingSessionIds.join("|");

  useEffect(() => {
    if (missingSessionIds.length === 0) {
      return;
    }

    let cancelled = false;
    setSummaries((current) => {
      const next = { ...current };
      for (const sessionId of missingSessionIds) {
        next[sessionId] = {
          additions: 0,
          deletions: 0,
          filesChanged: 0,
          state: "loading",
        };
      }
      return next;
    });

    void Promise.all(
      missingSessionIds.map(async (sessionId) => {
        try {
          return {
            impact: aggregateBirdsEyeCodeImpact(await gitStatus(sessionId)),
            sessionId,
            state: "ready" as const,
          };
        } catch {
          return {
            impact: {
              additions: 0,
              deletions: 0,
              filesChanged: 0,
            },
            sessionId,
            state: "error" as const,
          };
        }
      }),
    ).then((results) => {
      if (cancelled) {
        return;
      }

      setSummaries((current) => {
        const next = { ...current };

        for (const result of results) {
          next[result.sessionId] = {
            ...result.impact,
            state: result.state,
          };
        }

        return next;
      });
    });

    return () => {
      cancelled = true;
    };
  }, [missingSessionIds, missingSessionKey]);

  return summaries;
}

function aggregateBirdsEyeCodeImpact(status: GitStatusResult) {
  return (status.files ?? []).reduce(
    (summary, file) => ({
      additions: summary.additions + (file.additions ?? 0),
      deletions: summary.deletions + (file.deletions ?? 0),
      filesChanged: summary.filesChanged + 1,
    }),
    {
      additions: 0,
      deletions: 0,
      filesChanged: 0,
    },
  );
}

function buildBirdsEyeTree({
  agents,
  chats,
  dependencyCheck,
  projectWorktreesByProjectId,
  projects,
  workspaces,
}: {
  agents: AgentRecord[];
  chats: DashboardOverviewChatRecord[];
  dependencyCheck: RuntimeCapabilities | null;
  projectWorktreesByProjectId: Record<string, ProjectWorktreeState>;
  projects: ProjectRecord[];
  workspaces: WorkspaceRecord[];
}): BirdsEyeTreeModel {
  const defaultRuntimeDraft = createDefaultIssueRuntimeDraft(dependencyCheck);
  const workspaceByIssueId = new Map<string, WorkspaceRecord>();
  for (const workspace of workspaces) {
    if (workspace.issue_id && !workspaceByIssueId.has(workspace.issue_id)) {
      workspaceByIssueId.set(workspace.issue_id, workspace);
    }
  }

  const projectNodes = projects
    .map((project) => {
      const repoPath = project.primary_workspace?.cwd?.trim() ?? null;
      const projectChats = chats.filter(
        (chat) => chat.project_id === project.id,
      );
      const folderMap = new Map<
        string,
        BirdsEyeFolderNode & {
          secondaryLabel: string | null;
        }
      >();

      const ensureFolder = (folder: BirdsEyeFolderNode) => {
        const existing = folderMap.get(folder.rowId);
        if (existing) {
          return existing;
        }
        const next = {
          ...folder,
          chats: [],
          chatCount: 0,
          lastActivityAt: null,
          liveRunCount: 0,
        };
        folderMap.set(folder.rowId, next);
        return next;
      };

      ensureFolder(
        birdsEyeFolderNode({
          folderType: "repo_root",
          label: "Repo root",
          path: repoPath,
          projectId: project.id,
          runtimeDraft: defaultRuntimeDraft,
          secondaryLabel: repoPath ?? "No repository folder",
        }),
      );

      for (const worktree of projectWorktreesByProjectId[project.id]
        ?.worktrees ?? []) {
        ensureFolder(
          birdsEyeFolderNode({
            branch: worktree.branch ?? null,
            label: worktree.name || fileName(worktree.path),
            path: worktree.path,
            projectId: project.id,
            runtimeDraft: defaultRuntimeDraft,
            secondaryLabel: birdsEyeFolderSecondaryLabel(
              worktree.path,
              worktree.branch,
            ),
          }),
        );
      }

      for (const workspace of workspaces) {
        if (
          workspace.project_id !== project.id ||
          !workspace.workspace_repo_path?.trim() ||
          workspace.workspace_repo_path.trim() === repoPath
        ) {
          continue;
        }

        ensureFolder(
          birdsEyeFolderNode({
            branch: workspace.workspace_branch ?? null,
            label:
              workspace.workspace_branch?.trim() ||
              fileName(workspace.workspace_repo_path),
            path: workspace.workspace_repo_path,
            projectId: project.id,
            runtimeDraft: defaultRuntimeDraft,
            secondaryLabel: birdsEyeFolderSecondaryLabel(
              workspace.workspace_repo_path,
              workspace.workspace_branch ?? null,
            ),
          }),
        );
      }

      for (const chat of projectChats) {
        const runUpdate = chat.run_update ?? null;
        const workspace = workspaceByIssueId.get(chat.id) ?? null;
        const folder = ensureFolder(
          birdsEyeFolderForIssue(chat, project, workspace, defaultRuntimeDraft),
        );
        const chatNode: BirdsEyeChatNode = {
          agentLabel: issueModelLabel(chat, agents),
          chat,
          createDefaults: birdsEyeCreateDefaultsFromIssue(chat),
          folderRowId: folder.rowId,
          kind: "chat",
          lastActivityAt: birdsEyeActivityTimestamp(chat, runUpdate, workspace),
          projectId: project.id,
          rowId: `chat:${chat.id}`,
          runStatus: runUpdate?.run_status ?? null,
          runSummary: runUpdate ? issueRunCardUpdateSummary(runUpdate) : null,
          sessionId: workspace?.session_id ?? null,
          title: chat.title,
        };
        folder.chats.push(chatNode);
      }

      const folders = Array.from(folderMap.values())
        .map((folder) => {
          const chats = folder.chats.slice().sort((left, right) => {
            const leftTime =
              parseIssueDate(left.lastActivityAt)?.getTime() ?? 0;
            const rightTime =
              parseIssueDate(right.lastActivityAt)?.getTime() ?? 0;
            return rightTime - leftTime;
          });
          const latestChat = chats[0] ?? null;

          return {
            ...folder,
            chats,
            chatCount: chats.length,
            createDefaults: latestChat
              ? latestChat.createDefaults
              : folder.createDefaults,
            lastActivityAt: latestChat?.lastActivityAt ?? null,
            liveRunCount: chats.filter(
              (chat) =>
                chat.runStatus === "queued" || chat.runStatus === "running",
            ).length,
          };
        })
        .sort((left, right) => {
          if (left.folderType !== right.folderType) {
            return left.folderType === "repo_root" ? -1 : 1;
          }
          if (right.liveRunCount !== left.liveRunCount) {
            return right.liveRunCount - left.liveRunCount;
          }

          const leftTime = parseIssueDate(left.lastActivityAt)?.getTime() ?? 0;
          const rightTime =
            parseIssueDate(right.lastActivityAt)?.getTime() ?? 0;
          if (rightTime !== leftTime) {
            return rightTime - leftTime;
          }

          return left.label.localeCompare(right.label);
        });
      const allChats = folders.flatMap((folder) => folder.chats);
      const latestChat = allChats.slice().sort((left, right) => {
        const leftTime = parseIssueDate(left.lastActivityAt)?.getTime() ?? 0;
        const rightTime = parseIssueDate(right.lastActivityAt)?.getTime() ?? 0;
        return rightTime - leftTime;
      })[0];

      return {
        chatCount: allChats.length,
        createDefaults: {
          ...issueDialogDefaultsFromRuntimeDraft(defaultRuntimeDraft),
          ...projectDefaultNewChatWorkspaceDefaults(project),
          priority: "medium",
          projectId: project.id,
          status: "backlog",
        },
        folderCount: folders.length,
        folders,
        kind: "project" as const,
        label: project.name ?? project.title ?? "Untitled project",
        lastActivityAt: latestChat?.lastActivityAt ?? null,
        liveRunCount: folders.reduce(
          (count, folder) => count + folder.liveRunCount,
          0,
        ),
        project,
        repoPath,
        rowId: `project:${project.id}`,
      };
    })
    .sort((left, right) => {
      if (right.liveRunCount !== left.liveRunCount) {
        return right.liveRunCount - left.liveRunCount;
      }

      const leftTime = parseIssueDate(left.lastActivityAt)?.getTime() ?? 0;
      const rightTime = parseIssueDate(right.lastActivityAt)?.getTime() ?? 0;
      if (rightTime !== leftTime) {
        return rightTime - leftTime;
      }

      return left.label.localeCompare(right.label);
    });

  const rowById = new Map<string, BirdsEyeTreeNode>();
  const chatByIssueId = new Map<string, BirdsEyeChatNode>();
  const rowIds = new Set<string>();

  for (const project of projectNodes) {
    rowById.set(project.rowId, project);
    rowIds.add(project.rowId);
    for (const folder of project.folders) {
      rowById.set(folder.rowId, folder);
      rowIds.add(folder.rowId);
      for (const chat of folder.chats) {
        rowById.set(chat.rowId, chat);
        chatByIssueId.set(chat.chat.id, chat);
        rowIds.add(chat.rowId);
      }
    }
  }

  return {
    chatByIssueId,
    projects: projectNodes,
    rowById,
    rowIds,
  };
}

function birdsEyeWorktreeGridDimensions(count: number) {
  const safeCount = Math.max(count, 1);
  if (safeCount <= 2) {
    return { columns: safeCount, rows: 1 };
  }
  if (safeCount <= 4) {
    return { columns: 2, rows: 2 };
  }
  if (safeCount <= 6) {
    return { columns: 3, rows: 2 };
  }
  return { columns: 4, rows: Math.ceil(safeCount / 4) };
}

function defaultBirdsEyeRepoRegionState(index: number) {
  return {
    page: 0,
    x:
      defaultBirdsEyeCanvasOffset.x +
      index * (birdsEyeRepoRegionMinWidth + birdsEyeRepoRegionGapX),
    y: birdsEyeRepoRegionDefaultY,
  };
}

function normalizeBirdsEyeWorktreeTileState(
  tileState: BirdsEyeWorktreeTileState | undefined,
  availableIssueIds: string[],
) {
  const issueIdSet = new Set(availableIssueIds);
  const issueIds = (tileState?.issueIds ?? [])
    .filter((issueId) => issueIdSet.has(issueId))
    .slice(0, 4);
  const lruIssueIds = (tileState?.lruIssueIds ?? [])
    .filter((issueId) => issueIds.includes(issueId))
    .concat(
      issueIds.filter(
        (issueId) => !(tileState?.lruIssueIds ?? []).includes(issueId),
      ),
    );
  const activeIssueId =
    tileState?.activeIssueId && issueIds.includes(tileState.activeIssueId)
      ? tileState.activeIssueId
      : (issueIds[0] ?? null);

  return {
    activeIssueId,
    issueIds,
    lruIssueIds,
  };
}

function buildBirdsEyeCanvasModel(
  treeModel: BirdsEyeTreeModel,
  canvasState: BirdsEyeCanvasState,
  measuredWorktreeHeights: Record<string, number>,
) {
  const normalizedState: BirdsEyeCanvasState = {
    focusedTarget: canvasState.focusedTarget,
    repoRegions: { ...canvasState.repoRegions },
    viewport: {
      x: canvasState.viewport.x,
      y: canvasState.viewport.y,
      zoomIndex: clampNumber(
        canvasState.viewport.zoomIndex,
        0,
        birdsEyeCanvasZoomLevels.length - 1,
      ),
    },
    worktreeTiles: { ...canvasState.worktreeTiles },
  };

  const repoRegions = treeModel.projects.map((project, index) => {
    const persistedRegion =
      normalizedState.repoRegions[project.project.id] ??
      defaultBirdsEyeRepoRegionState(index);
    normalizedState.repoRegions[project.project.id] = persistedRegion;

    const totalPages = 1;
    const page = 0;
    normalizedState.repoRegions[project.project.id] = {
      ...persistedRegion,
      page,
    };

    const visibleWorktrees = project.folders;
    const grid = birdsEyeWorktreeGridDimensions(visibleWorktrees.length);
    const boardWidth =
      visibleWorktrees.length <= 2
        ? birdsEyeWorktreeBoardWidthWide
        : birdsEyeWorktreeBoardWidthCompact;
    const boardHeights = visibleWorktrees.map((folder) =>
      Math.max(
        birdsEyeWorktreeBoardHeight,
        Math.ceil(measuredWorktreeHeights[folder.folderKey] ?? 0),
      ),
    );
    const rowHeights = Array.from({ length: grid.rows }, (_, rowIndex) =>
      boardHeights.reduce((maxHeight, boardHeight, worktreeIndex) => {
        if (Math.floor(worktreeIndex / grid.columns) !== rowIndex) {
          return maxHeight;
        }
        return Math.max(maxHeight, boardHeight);
      }, 0),
    );
    const rowOffsets = rowHeights.reduce<number[]>(
      (offsets, rowHeight, rowIndex) => {
        if (rowIndex === 0) {
          offsets.push(0);
          return offsets;
        }
        offsets.push(
          offsets[rowIndex - 1]! +
            rowHeights[rowIndex - 1]! +
            birdsEyeWorktreeBoardGap,
        );
        return offsets;
      },
      [],
    );
    const regionWidth = Math.max(
      birdsEyeRepoRegionMinWidth,
      birdsEyeRepoRegionPadding * 2 +
        grid.columns * boardWidth +
        Math.max(grid.columns - 1, 0) * birdsEyeWorktreeBoardGap,
    );
    const regionHeight =
      birdsEyeRepoRegionPadding * 2 +
      birdsEyeRepoRegionLabelOffsetY +
      rowHeights.reduce((total, rowHeight) => total + rowHeight, 0) +
      Math.max(grid.rows - 1, 0) * birdsEyeWorktreeBoardGap;

    const boardModels = visibleWorktrees.map((folder, worktreeIndex) => {
      const column = worktreeIndex % grid.columns;
      const row = Math.floor(worktreeIndex / grid.columns);
      const key = folder.folderKey;
      const tileState = normalizeBirdsEyeWorktreeTileState(
        normalizedState.worktreeTiles[key],
        folder.chats.map((chat) => chat.chat.id),
      );
      normalizedState.worktreeTiles[key] = tileState;

      return {
        folder,
        chats: folder.chats,
        height: boardHeights[worktreeIndex] ?? birdsEyeWorktreeBoardHeight,
        key,
        pageIndex: page,
        tileState,
        width: boardWidth,
        x:
          birdsEyeRepoRegionPadding +
          column * (boardWidth + birdsEyeWorktreeBoardGap),
        y:
          birdsEyeRepoRegionPadding +
          birdsEyeRepoRegionLabelOffsetY +
          (rowOffsets[row] ?? 0),
      };
    });

    return {
      height: regionHeight,
      page,
      project,
      totalPages,
      visibleWorktrees: boardModels,
      width: regionWidth,
      x: persistedRegion.x,
      y: persistedRegion.y,
    };
  });

  for (const worktreeKey of Object.keys(normalizedState.worktreeTiles)) {
    if (
      !treeModel.projects.some((project) =>
        project.folders.some((folder) => folder.folderKey === worktreeKey),
      )
    ) {
      delete normalizedState.worktreeTiles[worktreeKey];
    }
  }

  const bounds = repoRegions.length
    ? {
        height:
          Math.max(...repoRegions.map((region) => region.y + region.height)) +
          220,
        width:
          Math.max(...repoRegions.map((region) => region.x + region.width)) +
          220,
      }
    : { width: 2200, height: 1600 };

  const isFocusTargetValid = (() => {
    const target = normalizedState.focusedTarget;
    if (!target) {
      return false;
    }

    const project = treeModel.projects.find(
      (entry) => entry.project.id === target.projectId,
    );
    if (!project) {
      return false;
    }
    if (target.kind === "repo") {
      return true;
    }

    const folder = project.folders.find(
      (entry) => entry.folderKey === target.worktreeKey,
    );
    if (!folder) {
      return false;
    }

    if (target.kind === "worktree") {
      return true;
    }

    if (!target.issueId) {
      return false;
    }

    if (target.kind === "chat") {
      return folder.chats.some((chat) => chat.chat.id === target.issueId);
    }

    return (
      normalizedState.worktreeTiles[
        target.worktreeKey ?? ""
      ]?.issueIds.includes(target.issueId) ?? false
    );
  })();

  if (!isFocusTargetValid) {
    const firstProject = treeModel.projects[0] ?? null;
    normalizedState.focusedTarget = firstProject
      ? {
          kind: "repo",
          issueId: null,
          projectId: firstProject.project.id,
          worktreeKey: null,
        }
      : null;
  }

  return {
    bounds,
    normalizedState,
    repoRegions,
  };
}

function birdsEyeFolderNode({
  branch,
  folderType = "worktree",
  label,
  path,
  projectId,
  runtimeDraft,
  secondaryLabel,
}: {
  branch?: string | null;
  folderType?: BirdsEyeFolderNode["folderType"];
  label: string;
  path: string | null;
  projectId: string;
  runtimeDraft: IssueRuntimeDraft;
  secondaryLabel: string | null;
}): BirdsEyeFolderNode {
  const folderKey =
    folderType === "repo_root"
      ? `repo_root:${projectId}`
      : folderType === "pending_worktree"
        ? `pending:${projectId}`
        : path
          ? `worktree:${path}`
          : `folder:${projectId}:${label}`;

  return {
    chatCount: 0,
    chats: [],
    createDefaults:
      folderType === "repo_root"
        ? {
            ...issueDialogDefaultsFromRuntimeDraft(runtimeDraft),
            priority: "medium",
            projectId,
            status: "backlog",
            workspaceTargetMode: "main",
          }
        : folderType === "pending_worktree"
          ? {
              ...issueDialogDefaultsFromRuntimeDraft(runtimeDraft),
              priority: "medium",
              projectId,
              status: "backlog",
              workspaceTargetMode: "new_worktree",
            }
          : {
              ...issueDialogDefaultsFromRuntimeDraft(runtimeDraft),
              priority: "medium",
              projectId,
              status: "backlog",
              workspaceTargetMode: "existing_worktree",
              workspaceWorktreeBranch: branch ?? "",
              workspaceWorktreeName: label,
              workspaceWorktreePath: path ?? "",
            },
    folderKey,
    folderType,
    kind: "folder",
    label,
    lastActivityAt: null,
    liveRunCount: 0,
    path,
    projectId,
    rowId: `folder:${projectId}:${folderKey}`,
    secondaryLabel,
  };
}

function birdsEyeFolderForIssue(
  issue: BirdsEyeIssueLike,
  project: ProjectRecord,
  workspace: WorkspaceRecord | null,
  defaultRuntimeDraft: IssueRuntimeDraft,
) {
  const repoPath = project.primary_workspace?.cwd?.trim() ?? null;
  if (workspace?.workspace_repo_path?.trim()) {
    const workspacePath = workspace.workspace_repo_path.trim();
    if (repoPath && workspacePath === repoPath) {
      return birdsEyeFolderNode({
        folderType: "repo_root",
        label: "Repo root",
        path: repoPath,
        projectId: project.id,
        runtimeDraft: defaultRuntimeDraft,
        secondaryLabel: repoPath,
      });
    }

    return birdsEyeFolderNode({
      branch: workspace.workspace_branch ?? null,
      label:
        workspace.workspace_branch?.trim() ||
        fileName(workspace.workspace_repo_path),
      path: workspace.workspace_repo_path,
      projectId: project.id,
      runtimeDraft: defaultRuntimeDraft,
      secondaryLabel: birdsEyeFolderSecondaryLabel(
        workspace.workspace_repo_path,
        workspace.workspace_branch ?? null,
      ),
    });
  }

  const workspaceSettings = parseIssueExecutionWorkspaceSettings(
    issue.execution_workspace_settings,
  );
  if (
    workspaceSettings.workspaceTargetMode === "existing_worktree" &&
    workspaceSettings.workspaceWorktreePath
  ) {
    return birdsEyeFolderNode({
      branch: workspaceSettings.workspaceWorktreeBranch || null,
      label:
        workspaceSettings.workspaceWorktreeName ||
        fileName(workspaceSettings.workspaceWorktreePath),
      path: workspaceSettings.workspaceWorktreePath,
      projectId: project.id,
      runtimeDraft: defaultRuntimeDraft,
      secondaryLabel: birdsEyeFolderSecondaryLabel(
        workspaceSettings.workspaceWorktreePath,
        workspaceSettings.workspaceWorktreeBranch || null,
      ),
    });
  }

  if (workspaceSettings.workspaceTargetMode === "new_worktree") {
    return birdsEyeFolderNode({
      folderType: "pending_worktree",
      label: "New worktree",
      path: null,
      projectId: project.id,
      runtimeDraft: defaultRuntimeDraft,
      secondaryLabel: "Created on first run",
    });
  }

  return birdsEyeFolderNode({
    folderType: "repo_root",
    label: "Repo root",
    path: repoPath,
    projectId: project.id,
    runtimeDraft: defaultRuntimeDraft,
    secondaryLabel: repoPath ?? "No repository folder",
  });
}

function birdsEyeCreateDefaultsFromIssue(
  issue: BirdsEyeIssueLike,
): CreateIssueDialogDefaults {
  const runtime = parseIssueAdapterOverrides(issue.assignee_adapter_overrides);
  const workspace = parseIssueExecutionWorkspaceSettings(
    issue.execution_workspace_settings,
  );

  return {
    ...issueDialogDefaultsFromRuntimeDraft(runtime),
    priority: issue.priority || "medium",
    projectId: issue.project_id ?? "",
    status: "backlog",
    workspaceTargetMode: workspace.workspaceTargetMode,
    workspaceWorktreeBranch: workspace.workspaceWorktreeBranch,
    workspaceWorktreeName: workspace.workspaceWorktreeName,
    workspaceWorktreePath: workspace.workspaceWorktreePath,
  };
}

function birdsEyeActivityTimestamp(
  issue: BirdsEyeIssueLike,
  update: IssueRunCardUpdateRecord | null,
  workspace: WorkspaceRecord | null,
) {
  return (
    [
      update?.last_activity_at,
      workspace?.last_accessed_at,
      workspace?.updated_at,
      issue.updated_at,
      issue.created_at,
    ]
      .filter((value): value is string => Boolean(value))
      .sort((left, right) => {
        const leftTime = parseIssueDate(left)?.getTime() ?? 0;
        const rightTime = parseIssueDate(right)?.getTime() ?? 0;
        return rightTime - leftTime;
      })[0] ?? null
  );
}

function dashboardOverviewChatToIssueRecord(
  chat: DashboardOverviewChatRecord,
  companyId: string | null,
): IssueRecord {
  return {
    id: chat.id,
    company_id: companyId ?? "",
    project_id: chat.project_id,
    title: chat.title,
    status: chat.status,
    priority: chat.priority,
    assignee_agent_id: chat.assignee_agent_id ?? null,
    assignee_adapter_overrides: chat.assignee_adapter_overrides ?? null,
    execution_workspace_settings: chat.execution_workspace_settings ?? null,
    identifier: chat.identifier ?? null,
    request_depth: 0,
    created_at: chat.created_at,
    updated_at: chat.updated_at,
  };
}

function birdsEyeFolderSecondaryLabel(
  path: string | null | undefined,
  branch: string | null | undefined,
) {
  return [branch?.trim() || null, path?.trim() || null]
    .filter(Boolean)
    .join(" · ");
}

function flattenBirdsEyeTree(
  projects: BirdsEyeProjectNode[],
  expandedRowIds: Record<string, boolean>,
) {
  const rows: BirdsEyeVisibleRow[] = [];

  for (const project of projects) {
    const isProjectExpanded = expandedRowIds[project.rowId] ?? false;
    rows.push({
      depth: 0,
      hasChildren: project.folders.length > 0,
      isExpanded: isProjectExpanded,
      node: project,
      parentRowId: null,
      rowId: project.rowId,
    });

    if (!isProjectExpanded) {
      continue;
    }

    for (const folder of project.folders) {
      const isFolderExpanded = expandedRowIds[folder.rowId] ?? false;
      rows.push({
        depth: 1,
        hasChildren: folder.chats.length > 0,
        isExpanded: isFolderExpanded,
        node: folder,
        parentRowId: project.rowId,
        rowId: folder.rowId,
      });

      if (!isFolderExpanded) {
        continue;
      }

      for (const chat of folder.chats) {
        rows.push({
          depth: 2,
          hasChildren: false,
          isExpanded: false,
          node: chat,
          parentRowId: folder.rowId,
          rowId: chat.rowId,
        });
      }
    }
  }

  return rows;
}

function birdsEyeSuggestedTitle(node: BirdsEyeTreeNode | null) {
  if (!node) {
    return "New conversation";
  }

  if (node.kind === "chat") {
    return `Follow up: ${node.title.slice(0, 56)}`;
  }

  if (node.kind === "folder") {
    return `New chat in ${node.label}`;
  }

  return `New chat in ${node.label}`;
}

function describeBirdsEyeNodeContext(node: BirdsEyeTreeNode | null) {
  if (!node) {
    return "current context";
  }

  if (node.kind === "chat") {
    return `same folder as ${node.title}`;
  }

  if (node.kind === "folder") {
    return node.label;
  }

  return node.label;
}

function birdsEyeImpactLabel(summary: BirdsEyeCodeImpactSummary | null) {
  if (!summary) {
    return "No code";
  }

  if (summary.state === "loading") {
    return "Scanning";
  }

  if (summary.state === "error") {
    return "Code n/a";
  }

  if (
    summary.filesChanged === 0 &&
    summary.additions === 0 &&
    summary.deletions === 0
  ) {
    return "No code";
  }

  return `${summary.filesChanged} files · +${summary.additions} -${summary.deletions}`;
}

function isEditableEventTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  return Boolean(
    target.closest(
      "input, textarea, select, [contenteditable='true'], [contenteditable='']",
    ),
  );
}

function projectBoardColumnStatuses(issues: IssueRecord[]) {
  const statuses = [...canonicalIssueStatuses];
  for (const issue of issues) {
    const normalizedStatus = normalizeBoardIssueValue(issue.status);
    if (!statuses.includes(normalizedStatus)) {
      statuses.push(normalizedStatus);
    }
  }
  return statuses;
}

function projectBoardColumnsByStatus(
  project: ProjectRecord,
  issues: IssueRecord[],
): DashboardProjectColumn[] {
  const projectWorkspaceDefaults =
    projectDefaultNewChatWorkspaceDefaults(project);
  return projectBoardColumnStatuses(issues).map((status) => ({
    createDefaults: {
      ...projectWorkspaceDefaults,
      status,
    },
    id: `status:${status}`,
    issues: issues.filter(
      (issue) => normalizeBoardIssueValue(issue.status) === status,
    ),
    label: issueStatusLabel(status),
  }));
}

function projectBoardColumns(
  project: ProjectRecord,
  issues: IssueRecord[],
  agents: AgentRecord[],
  grouping: DashboardProjectGrouping,
): DashboardProjectColumn[] {
  void agents;
  void grouping;
  return projectBoardColumnsByStatus(project, issues);
}

function buildDashboardProjectColumns(
  projects: ProjectRecord[],
  issues: IssueRecord[],
  agents: AgentRecord[],
  projectViews: NonNullable<DesktopSettings["dashboard_project_views"]>,
): DashboardProjectColumnLayout[] {
  const gridColumnCount = projects.length <= 1 ? 1 : 2;
  const projectColumnDrafts = projects.map((project) => {
    const projectViewSettings = projectViews[project.id] ?? {};
    const projectIssues = issues.filter(
      (issue) => issue.project_id === project.id,
    );
    const boards = buildDashboardProjectColumnBoards(
      project,
      projectIssues,
      agents,
      projectViewSettings,
    );
    const width = Math.max(
      ...boards.map((board) => board.width),
      dashboardProjectBoardMinWidth,
    );

    return {
      project,
      boards,
      height:
        boards.length * dashboardProjectBoardHeight +
        Math.max(boards.length - 1, 0) * dashboardProjectBoardStackGap +
        dashboardProjectAddViewSlotHeight,
      width,
    };
  });
  const rowCount = Math.ceil(projectColumnDrafts.length / gridColumnCount);
  const columnWidths = Array.from(
    { length: gridColumnCount },
    (_, columnIndex) =>
      projectColumnDrafts.reduce(
        (maxWidth, projectColumn, columnIndexInDraft) => {
          if (columnIndexInDraft % gridColumnCount !== columnIndex) {
            return maxWidth;
          }

          return Math.max(maxWidth, projectColumn.width);
        },
        dashboardProjectBoardMinWidth,
      ),
  );
  const rowHeights = Array.from({ length: rowCount }, (_, rowIndex) =>
    projectColumnDrafts.reduce(
      (maxHeight, projectColumn, columnIndexInDraft) => {
        if (Math.floor(columnIndexInDraft / gridColumnCount) !== rowIndex) {
          return maxHeight;
        }

        return Math.max(maxHeight, projectColumn.height);
      },
      dashboardProjectBoardHeight + dashboardProjectAddViewSlotHeight,
    ),
  );
  const columnOffsets = columnWidths.map((_, columnIndex) => {
    if (columnIndex === 0) {
      return 120;
    }

    return columnWidths
      .slice(0, columnIndex)
      .reduce((total, width) => total + width + dashboardProjectBoardGapX, 120);
  });
  const rowOffsets = rowHeights.map((_, rowIndex) => {
    if (rowIndex === 0) {
      return 104;
    }

    return rowHeights
      .slice(0, rowIndex)
      .reduce(
        (total, height) => total + height + dashboardProjectBoardGapY,
        104,
      );
  });

  return projectColumnDrafts.map((projectColumn, index) => {
    const col = index % gridColumnCount;
    const row = Math.floor(index / gridColumnCount);

    return {
      ...projectColumn,
      left: columnOffsets[col] ?? 120,
      top: rowOffsets[row] ?? 104,
    };
  });
}

function buildDashboardCanvasBounds(
  projectColumns: DashboardProjectColumnLayout[],
) {
  if (!projectColumns.length) {
    return { width: 2200, height: 1600 };
  }

  const maxRight = Math.max(
    ...projectColumns.map(
      (projectColumn) => projectColumn.left + projectColumn.width,
    ),
  );
  const maxBottom = Math.max(
    ...projectColumns.map(
      (projectColumn) => projectColumn.top + projectColumn.height,
    ),
  );

  return {
    width: Math.max(maxRight + 160, 2200),
    height: Math.max(maxBottom + 180, 1600),
  };
}

function clampDashboardCanvasOffset(
  next: DashboardCanvasOffset,
  viewportWidth: number,
  viewportHeight: number,
  canvasBounds: { height: number; width: number },
  canvasZoomScale: number,
) {
  const edgePadding = 120;
  const scaledCanvasWidth = canvasBounds.width * canvasZoomScale;
  const scaledCanvasHeight = canvasBounds.height * canvasZoomScale;
  const minX = Math.min(
    edgePadding,
    viewportWidth - scaledCanvasWidth + edgePadding,
  );
  const minY = Math.min(
    edgePadding,
    viewportHeight - scaledCanvasHeight + edgePadding,
  );

  return {
    x: clampNumber(next.x, minX, edgePadding),
    y: clampNumber(next.y, minY, edgePadding),
  };
}

function dashboardProjectBoardWidth(columnCount: number) {
  const safeColumnCount = Math.max(columnCount, 1);
  const columnsWidth =
    safeColumnCount * dashboardProjectBoardColumnWidth +
    Math.max(safeColumnCount - 1, 0) * dashboardProjectBoardColumnGap;
  const chromeWidth =
    dashboardProjectBoardPadding * 2 + dashboardProjectBoardBorderWidth * 2;

  return Math.max(dashboardProjectBoardMinWidth, columnsWidth + chromeWidth);
}

function dashboardCanvasZoomLabel(zoomLevel: number) {
  return `${Math.round(zoomLevel * 100)}%`;
}

function buildDashboardProjectColumnBoards(
  project: ProjectRecord,
  issues: IssueRecord[],
  agents: AgentRecord[],
  viewSettings: NonNullable<DesktopSettings["dashboard_project_views"]>[string],
) {
  const savedViews = dashboardProjectSavedViews(viewSettings?.saved_views);

  return [
    createDashboardProjectBoardLayout({
      agents,
      grouping: normalizeDashboardProjectGrouping(viewSettings?.group_by),
      isDefaultView: true,
      issues,
      project,
      viewId: dashboardDefaultProjectViewId,
      viewName: "Default view",
    }),
    ...savedViews.map((savedView, index) =>
      createDashboardProjectBoardLayout({
        agents,
        grouping: normalizeDashboardProjectGrouping(savedView.group_by),
        isDefaultView: false,
        issues,
        project,
        viewId: savedView.id,
        viewName: dashboardProjectViewName(savedView.name, index),
      }),
    ),
  ];
}

function createDashboardProjectBoardLayout({
  agents,
  grouping,
  isDefaultView,
  issues,
  project,
  viewId,
  viewName,
}: {
  agents: AgentRecord[];
  grouping: DashboardProjectGrouping;
  isDefaultView: boolean;
  issues: IssueRecord[];
  project: ProjectRecord;
  viewId: string;
  viewName: string;
}): DashboardProjectBoardLayout {
  const columns = projectBoardColumns(project, issues, agents, grouping);

  return {
    boardId: `${project.id}:${viewId}`,
    columns,
    grouping,
    isDefaultView,
    issueCount: issues.length,
    project,
    viewId,
    viewName,
    width: dashboardProjectBoardWidth(columns.length),
  };
}

function dashboardProjectSavedViews(
  views:
    | NonNullable<
        NonNullable<DesktopSettings["dashboard_project_views"]>[string]
      >["saved_views"]
    | undefined,
) {
  return (views ?? []).filter(
    (
      view,
    ): view is {
      group_by?: DashboardProjectGrouping | null;
      id: string;
      name?: string | null;
    } => Boolean(view?.id),
  );
}

function dashboardProjectViewName(
  value: string | null | undefined,
  index: number,
) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : `View ${index + 1}`;
}

function nextDashboardProjectViewName(boards: DashboardProjectBoardLayout[]) {
  return `View ${boards.filter((board) => !board.isDefaultView).length + 1}`;
}

function nextDashboardProjectViewGrouping(
  boards: DashboardProjectBoardLayout[],
): DashboardProjectGrouping {
  const usedGroupings = new Set(boards.map((board) => board.grouping));

  return (
    dashboardProjectGroupingOptions.find(
      (grouping) => !usedGroupings.has(grouping),
    ) ?? "status"
  );
}

function createDashboardProjectViewId() {
  if (
    typeof crypto !== "undefined" &&
    typeof crypto.randomUUID === "function"
  ) {
    return crypto.randomUUID();
  }

  return `dashboard-view-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`;
}

function clampNumber(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function humanizeIssueValue(value: string) {
  const normalized = value.replaceAll("_", " ");
  switch (normalized.toLowerCase()) {
    case "issue":
      return "Conversation";
    case "issues":
      return "Conversations";
    case "sub issue":
      return "Queued Message";
    case "sub issues":
      return "Queued Messages";
    case "company":
      return "Space";
    case "companies":
      return "Spaces";
    case "company settings":
      return "Space Settings";
    default:
      return normalized.replace(/\b\w/g, (match) => match.toUpperCase());
  }
}

function issueStatusLabel(value: string) {
  switch (normalizeBoardIssueValue(value)) {
    case "todo":
      return "To Do";
    case "in_progress":
      return "In Progress";
    case "cancelled":
      return "Canceled";
    default:
      return humanizeIssueValue(value);
  }
}

function issueProjectLabel(
  projects: ProjectRecord[],
  projectId?: string | null,
) {
  if (!projectId) {
    return "No project";
  }

  const project = projects.find((entry) => entry.id === projectId);
  return project?.name ?? project?.title ?? projectId;
}

function goalTitleForProject(goals: GoalRecord[], goalId?: string | null) {
  if (!goalId) {
    return "None";
  }

  const goal = goals.find((entry) => entry.id === goalId);
  return goal?.title ?? goalId;
}

function issueAssigneeLabel(
  agents: AgentRecord[],
  assigneeAgentId?: string | null,
) {
  if (!assigneeAgentId) {
    return "Unassigned";
  }

  const agent = agents.find((entry) => entry.id === assigneeAgentId);
  return agent?.name || agent?.title || agent?.role || assigneeAgentId;
}

function providerLabelForRuntimeConfig(
  command: string | null | undefined,
  model: string | null | undefined,
) {
  const provider = detectAgentCliProvider(command, model);
  if (provider === "codex") {
    return "Codex";
  }
  if (provider === "claude") {
    return "Claude";
  }
  return "Default model";
}

function runtimeModelLabel(
  runtimeConfig: Record<string, unknown> | null | undefined,
) {
  const configuredModel = stringFromUnknown(runtimeConfig?.model).trim();
  if (configuredModel && configuredModel.toLowerCase() !== "default") {
    return configuredModel;
  }

  return providerLabelForRuntimeConfig(
    stringFromUnknown(runtimeConfig?.command),
    configuredModel,
  );
}

function agentModelLabel(agent: AgentRecord) {
  const mergedRuntimeConfig = {
    ...objectFromUnknown(agent.adapter_config),
    ...objectFromUnknown(agent.runtime_config),
  };
  return runtimeModelLabel(mergedRuntimeConfig);
}

function agentModelLabelById(agents: AgentRecord[], agentId?: string | null) {
  if (!agentId) {
    return "Unknown model";
  }

  const agent = agents.find((entry) => entry.id === agentId);
  return agent ? agentModelLabel(agent) : agentId;
}

function issueModelLabel(
  issue: BirdsEyeIssueLike | null | undefined,
  agents: AgentRecord[],
) {
  const runtimeOverrides = objectFromUnknown(issue?.assignee_adapter_overrides);
  if (Object.keys(runtimeOverrides).length > 0) {
    return runtimeModelLabel(runtimeOverrides);
  }

  if (!issue) {
    return "Claude";
  }

  return agentModelLabelById(agents, issue.assignee_agent_id);
}

function agentInitials(value: string) {
  const parts = value.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) {
    return "?";
  }
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return `${parts[0].slice(0, 1)}${parts[1].slice(0, 1)}`.toUpperCase();
}

function goalOwnerLabel(agents: AgentRecord[], ownerAgentId?: string | null) {
  if (!ownerAgentId) {
    return "Unassigned";
  }

  const agent = agents.find((entry) => entry.id === ownerAgentId);
  return agent?.name || agent?.title || agent?.role || ownerAgentId;
}

function sameAgentIdList(left: AgentRecord[], right: AgentRecord[]) {
  if (left.length !== right.length) {
    return false;
  }

  return left.every((agent, index) => agent.id === right[index]?.id);
}

function issueParentLabel(
  issues: IssueRecord[],
  parentIssueId?: string | null,
) {
  if (!parentIssueId) {
    return "No parent conversation";
  }

  const issue = issues.find((entry) => entry.id === parentIssueId);
  return issue?.identifier ?? issue?.title ?? parentIssueId;
}

function formatCents(value: number | null | undefined) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return "n/a";
  }

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  }).format(value / 100);
}

function formatTimestamp(value: string | null | undefined) {
  if (!value) {
    return "n/a";
  }

  const date = parseIssueDate(value);
  if (!date) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function formatShortDate(value: string | null | undefined) {
  if (!value) {
    return "n/a";
  }

  const date = parseIssueDate(value);
  if (!date) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
  }).format(date);
}

function formatIssueDate(value: string | null | undefined) {
  if (!value) {
    return "Unknown";
  }

  const date = parseIssueDate(value);
  if (!date) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function formatBoardDate(value: string | null | undefined) {
  return formatIssueDate(value);
}

function formatRelativeIssueDate(value: string | null | undefined) {
  const date = parseIssueDate(value);
  if (!date) {
    return "Unknown";
  }

  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const deltaSeconds = Math.round((date.getTime() - Date.now()) / 1000);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["day", 86_400],
    ["hour", 3600],
    ["minute", 60],
  ];

  for (const [unit, secondsPerUnit] of units) {
    if (Math.abs(deltaSeconds) >= secondsPerUnit) {
      return formatter.format(Math.round(deltaSeconds / secondsPerUnit), unit);
    }
  }

  return formatter.format(deltaSeconds, "second");
}

function shortAgentRunTitle(runId: string) {
  return `Run ${runId.slice(0, 8)}`;
}

function agentRunSummary(run: AgentRunRecord) {
  if (run.error) {
    return run.error;
  }

  if (run.stdout_excerpt) {
    return run.stdout_excerpt;
  }

  if (run.stderr_excerpt) {
    return run.stderr_excerpt;
  }

  if (run.wake_reason) {
    return agentRunWakeReasonLabel(run.wake_reason);
  }

  if (run.trigger_detail) {
    return agentRunTriggerDetailLabel(run.trigger_detail);
  }

  return "Waiting for run output.";
}

function issueLinkedRunLabel(issue: IssueRecord, run: AgentRunRecord) {
  const labels: string[] = [];

  if (run.id === issue.execution_run_id) {
    labels.push("Current execution");
  }

  if (run.id === issue.checkout_run_id) {
    labels.push("Checkout");
  }

  return labels.length ? labels.join(" / ") : null;
}

function agentRunStatusLabel(status: string) {
  switch (status) {
    case "queued":
      return "Queued";
    case "running":
      return "Running";
    case "succeeded":
      return "Succeeded";
    case "failed":
      return "Failed";
    case "cancelled":
      return "Cancelled";
    case "timed_out":
      return "Timed out";
    default:
      return humanizeIssueValue(status);
  }
}

function formatLiveRunCountLabel(count: number) {
  return `${count} live`;
}

function agentRunStatusTone(status: string) {
  switch (status) {
    case "queued":
      return "queued";
    case "running":
      return "running";
    case "succeeded":
      return "succeeded";
    case "failed":
    case "timed_out":
      return "failed";
    case "cancelled":
      return "cancelled";
    default:
      return "neutral";
  }
}

function issueRunCardUpdateSummary(update: IssueRunCardUpdateRecord) {
  const summary = update.summary?.trim();
  if (summary) {
    return summary;
  }

  switch (update.run_status) {
    case "queued":
      return "Waiting to start";
    case "running":
      return "Working on the conversation";
    case "succeeded":
      return "Run finished";
    case "failed":
      return "Run failed";
    case "cancelled":
      return "Run cancelled";
    case "timed_out":
      return "Run timed out";
    default:
      return "Run updated";
  }
}

function normalizeAgentStatusTone(status: string | null | undefined) {
  switch (status) {
    case "idle":
      return "idle";
    case "running":
      return "running";
    case "active":
      return "succeeded";
    case "pending_approval":
      return "queued";
    case "failed":
    case "error":
      return "failed";
    case "disabled":
      return "cancelled";
    default:
      return "neutral";
  }
}

function agentAdapterTypeLabel(value: string | null | undefined) {
  if (!value) {
    return "Not configured";
  }

  if (value === "process") {
    return "Local CLI agent";
  }

  return humanizeIssueValue(value);
}

function agentRunInvocationSourceLabel(source: string) {
  switch (source) {
    case "timer":
      return "Timer";
    case "assignment":
      return "Assignment";
    case "on_demand":
      return "On Demand";
    case "automation":
      return "Automation";
    default:
      return humanizeIssueValue(source);
  }
}

function agentRunTriggerDetailLabel(triggerDetail: string | null | undefined) {
  if (!triggerDetail) {
    return "None";
  }

  switch (triggerDetail) {
    case "manual":
      return "Manual";
    case "system":
      return "System";
    case "ping":
      return "Ping";
    case "callback":
      return "Callback";
    default:
      return humanizeIssueValue(triggerDetail);
  }
}

function agentRunWakeReasonLabel(wakeReason: string | null | undefined) {
  if (!wakeReason) {
    return "None";
  }

  switch (wakeReason) {
    case "heartbeat_timer":
      return "Scheduled";
    case "issue_assigned":
      return "Conversation Routed";
    case "issue_status_changed":
      return "Conversation Status Changed";
    case "issue_checked_out":
      return "Conversation Checked Out";
    case "issue_commented":
      return "Conversation Messaged";
    case "issue_comment_mentioned":
      return "Message Mentioned";
    case "issue_reopened_via_comment":
      return "Conversation Reopened";
    case "approval_approved":
      return "Approval Approved";
    case "issue_execution_promoted":
      return "Execution Promoted";
    case "stale_checkout_run":
      return "Stale Checkout Run";
    default:
      return humanizeIssueValue(wakeReason);
  }
}

function issueCreatorLabel(issue: IssueRecord, agents: AgentRecord[]) {
  if (issue.created_by_agent_id) {
    return agentModelLabelById(agents, issue.created_by_agent_id);
  }

  if (issue.created_by_user_id) {
    return issue.created_by_user_id === "local-board"
      ? "Board"
      : issue.created_by_user_id;
  }

  return "Board";
}

function issueCommentAuthorLabel(
  agents: AgentRecord[],
  comment: IssueCommentRecord,
) {
  if (comment.author_agent_id) {
    return agentModelLabelById(agents, comment.author_agent_id);
  }

  if (comment.author_user_id) {
    return comment.author_user_id === "local-board" ? "Board" : "You";
  }

  return "Board";
}

function isRootConversationIssue(issue: IssueRecord) {
  return (issue.parent_id?.trim() ?? "").length === 0;
}

function agentRunEventLabel(eventType: string) {
  switch (eventType) {
    case "item.completed.agent_message":
      return "Agent Update";
    case "item.started.command_execution":
      return "Command Started";
    case "item.completed.command_execution":
      return "Command Finished";
    case "thread.started":
      return "Thread Started";
    case "turn.started":
      return "Turn Started";
    case "turn.completed":
      return "Turn Completed";
    case "run_started":
      return "Run Started";
    case "finished":
      return "Run Finished";
    case "stopped":
      return "Run Cancelled";
    case "timed_out":
      return "Run Timed Out";
    case "stderr":
      return "Warning";
    default:
      return humanizeIssueValue(eventType);
  }
}

function formatRelativeAgentRunDate(value: string | null | undefined) {
  const date = parseIssueDate(value);
  if (!date) {
    return "Unknown";
  }

  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const deltaSeconds = Math.round((date.getTime() - Date.now()) / 1000);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["day", 86_400],
    ["hour", 3600],
    ["minute", 60],
  ];

  for (const [unit, secondsPerUnit] of units) {
    if (Math.abs(deltaSeconds) >= secondsPerUnit) {
      return formatter.format(Math.round(deltaSeconds / secondsPerUnit), unit);
    }
  }

  return formatter.format(deltaSeconds, "second");
}

function formatJsonBlock(value: unknown) {
  if (typeof value === "string") {
    return value;
  }

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function cleanedAgentRunEventMessage(message: string | null | undefined) {
  const trimmed = message?.trim();
  if (!trimmed) {
    return "";
  }

  if (
    (trimmed.startsWith("{") && trimmed.endsWith("}")) ||
    (trimmed.startsWith("[") && trimmed.endsWith("]"))
  ) {
    return "";
  }

  return trimmed;
}

function agentRunEventStateLabel(value: string) {
  switch (value) {
    case "in_progress":
      return "Running";
    case "completed":
      return "Completed";
    case "timed_out":
      return "Timed out";
    case "stopped":
      return "Cancelled";
    default:
      return humanizeIssueValue(value);
  }
}

function agentRunEventStateTone(value: string) {
  switch (value) {
    case "in_progress":
    case "running":
      return "running";
    case "completed":
    case "succeeded":
      return "succeeded";
    case "timed_out":
    case "failed":
    case "stderr":
      return "failed";
    case "stopped":
    case "cancelled":
      return "cancelled";
    default:
      return "neutral";
  }
}

function formatAgentRunMetricLabel(label: string, value: number) {
  return `${label} ${value.toLocaleString("en-US")}`;
}

function companyBudgetCents(company: Company | null) {
  return typeof company?.budget_monthly_cents === "number"
    ? company.budget_monthly_cents
    : 0;
}

function companySpentCents(company: Company | null) {
  return typeof company?.spent_monthly_cents === "number"
    ? company.spent_monthly_cents
    : 0;
}

function agentBudgetCents(agent: AgentRecord) {
  return typeof agent.budget_monthly_cents === "number"
    ? agent.budget_monthly_cents
    : 0;
}

function agentSpentCents(agent: AgentRecord) {
  return typeof agent.spent_monthly_cents === "number"
    ? agent.spent_monthly_cents
    : 0;
}

function formatBudgetUtilization(spentCents: number, budgetCents: number) {
  if (budgetCents <= 0) {
    return "No cap";
  }

  return `${Math.round((spentCents / budgetCents) * 100)}%`;
}

function budgetProgressPercent(spentCents: number, budgetCents: number) {
  if (budgetCents <= 0) {
    return spentCents > 0 ? 100 : 0;
  }

  return clampNumber((spentCents / budgetCents) * 100, 0, 100);
}

function companyBudgetStatusLabel(spentCents: number, budgetCents: number) {
  if (budgetCents <= 0) {
    return "No space cap";
  }

  if (spentCents > budgetCents) {
    return `Over by ${formatCents(spentCents - budgetCents)}`;
  }

  return `${formatCents(budgetCents - spentCents)} remaining`;
}

function agentBudgetStatusLabel(spentCents: number, budgetCents: number) {
  if (budgetCents <= 0) {
    return spentCents > 0 ? "Tracked spend" : "No spend yet";
  }

  if (spentCents > budgetCents) {
    return `Over by ${formatCents(spentCents - budgetCents)}`;
  }

  return `${formatBudgetUtilization(spentCents, budgetCents)} used`;
}

function isAgentOverBudget(agent: AgentRecord) {
  const budget = agentBudgetCents(agent);
  return budget > 0 && agentSpentCents(agent) > budget;
}

function formatApprovalPayload(payload: Record<string, unknown>) {
  return Object.entries(payload)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}: ${formatApprovalPayloadValue(value)}`)
    .join("\n");
}

function formatApprovalPayloadValue(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    value === null ||
    value === undefined
  ) {
    return String(value);
  }

  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function findCompanyCeo<T extends { id: string; role?: string | null }>(
  agents: T[],
  ceoAgentId: string | null,
) {
  if (ceoAgentId) {
    const ceoAgent = agents.find((agent) => agent.id === ceoAgentId);
    if (ceoAgent) {
      return ceoAgent;
    }
  }

  return agents.find((agent) => agent.role?.toLowerCase() === "ceo") ?? null;
}

function orderSidebarAgents<T extends { id: string; role?: string | null }>(
  agents: T[],
  ceoAgentId: string | null,
) {
  if (ceoAgentId) {
    const ceoAgent = agents.find((agent) => agent.id === ceoAgentId);
    if (ceoAgent) {
      return [ceoAgent, ...agents.filter((agent) => agent.id !== ceoAgentId)];
    }
  }

  const ceoAgent = agents.find((agent) => agent.role?.toLowerCase() === "ceo");
  if (ceoAgent) {
    return [ceoAgent, ...agents.filter((agent) => agent.id !== ceoAgent.id)];
  }

  return agents;
}

function buildOrgHierarchy(
  agents: AgentRecord[],
  projects: ProjectRecord[],
  ceoAgentId: string | null,
): OrgHierarchyNode[] {
  const agentMap = new Map(agents.map((agent) => [agent.id, agent]));
  const childrenByManagerId = new Map<string, AgentRecord[]>();
  const leadProjectsByAgentId = new Map<string, ProjectRecord[]>();
  const roots: AgentRecord[] = [];

  for (const project of projects) {
    if (!project.lead_agent_id) {
      continue;
    }
    const existing = leadProjectsByAgentId.get(project.lead_agent_id) ?? [];
    existing.push(project);
    leadProjectsByAgentId.set(project.lead_agent_id, existing);
  }

  for (const agent of agents) {
    const managerId =
      typeof agent.reports_to === "string" && agent.reports_to.trim().length > 0
        ? agent.reports_to
        : null;

    if (
      isOrgRootAgent(agent, agentMap, ceoAgentId) ||
      !managerId ||
      !agentMap.has(managerId)
    ) {
      roots.push(agent);
      continue;
    }

    const existing = childrenByManagerId.get(managerId) ?? [];
    existing.push(agent);
    childrenByManagerId.set(managerId, existing);
  }

  const buildNode = (
    agent: AgentRecord,
    lineage: Set<string>,
  ): OrgHierarchyNode => {
    if (lineage.has(agent.id)) {
      return {
        agent,
        leadProjects: sortProjectsForOrg(
          leadProjectsByAgentId.get(agent.id) ?? [],
        ),
        reports: [],
        totalReports: 0,
      };
    }

    const nextLineage = new Set(lineage);
    nextLineage.add(agent.id);
    const reports = sortAgentsForOrg(
      childrenByManagerId.get(agent.id) ?? [],
      ceoAgentId,
    ).map((child) => buildNode(child, nextLineage));

    return {
      agent,
      leadProjects: sortProjectsForOrg(
        leadProjectsByAgentId.get(agent.id) ?? [],
      ),
      reports,
      totalReports: reports.reduce(
        (count, child) => count + 1 + child.totalReports,
        0,
      ),
    };
  };

  return sortAgentsForOrg(roots, ceoAgentId).map((agent) =>
    buildNode(agent, new Set<string>()),
  );
}

function flattenOrgHierarchy(nodes: OrgHierarchyNode[]): OrgHierarchyNode[] {
  const flattened: OrgHierarchyNode[] = [];
  for (const node of nodes) {
    flattened.push(node);
    flattened.push(...flattenOrgHierarchy(node.reports));
  }
  return flattened;
}

function buildProjectLeadAssignments(
  agents: AgentRecord[],
  projects: ProjectRecord[],
) {
  const agentMap = new Map(agents.map((agent) => [agent.id, agent]));
  const assignments = new Map<string, ProjectRecord[]>();

  for (const project of projects) {
    if (!(project.lead_agent_id && agentMap.has(project.lead_agent_id))) {
      continue;
    }

    const existing = assignments.get(project.lead_agent_id) ?? [];
    existing.push(project);
    assignments.set(project.lead_agent_id, existing);
  }

  return Array.from(assignments.entries())
    .map(([agentId, ownedProjects]) => ({
      agent: agentMap.get(agentId)!,
      projects: sortProjectsForOrg(ownedProjects),
    }))
    .sort((left, right) => {
      if (right.projects.length !== left.projects.length) {
        return right.projects.length - left.projects.length;
      }

      return compareAgentRecordsForOrg(left.agent, right.agent, null);
    });
}

function sortAgentsForOrg(agents: AgentRecord[], ceoAgentId: string | null) {
  return [...agents].sort((left, right) =>
    compareAgentRecordsForOrg(left, right, ceoAgentId),
  );
}

function compareAgentRecordsForOrg(
  left: AgentRecord,
  right: AgentRecord,
  ceoAgentId: string | null,
) {
  const leftIsCeo = isCeoAgent(left, ceoAgentId);
  const rightIsCeo = isCeoAgent(right, ceoAgentId);
  if (leftIsCeo !== rightIsCeo) {
    return leftIsCeo ? -1 : 1;
  }

  const leftLabel = (
    left.name ||
    left.title ||
    left.role ||
    left.id
  ).toLowerCase();
  const rightLabel = (
    right.name ||
    right.title ||
    right.role ||
    right.id
  ).toLowerCase();

  return leftLabel.localeCompare(rightLabel);
}

function sortProjectsForOrg(projects: ProjectRecord[]) {
  return [...projects].sort((left, right) =>
    (left.name || left.title || left.id).localeCompare(
      right.name || right.title || right.id,
    ),
  );
}

function isCeoAgent(
  agent: Pick<AgentRecord, "id" | "role">,
  ceoAgentId: string | null,
) {
  if (ceoAgentId) {
    return agent.id === ceoAgentId;
  }

  return agent.role?.toLowerCase() === "ceo";
}

function isOrgRootAgent(
  agent: AgentRecord,
  agentMap: Map<string, AgentRecord>,
  ceoAgentId: string | null,
) {
  if (isCeoAgent(agent, ceoAgentId)) {
    return true;
  }

  if (!(agent.reports_to && agentMap.has(agent.reports_to))) {
    return true;
  }

  return agent.reports_to === agent.id;
}

function orgChartAgentName(agent: AgentRecord) {
  const label = agent.name?.trim() || agent.title?.trim() || agent.role?.trim();
  if (!label || label.length === 0) {
    return "Agent";
  }

  return /[A-Z]/.test(label) ? label : humanizeIssueValue(label);
}

function orgChartAgentRoleLabel(agent: AgentRecord) {
  const rawLabel = agent.title?.trim() || agent.role?.trim() || "Agent";
  return /[A-Z]/.test(rawLabel) ? rawLabel : humanizeIssueValue(rawLabel);
}

function orgChartAgentProviderLabel(agent: AgentRecord) {
  const adapterConfig = objectFromUnknown(agent.adapter_config);
  const runtimeConfig = objectFromUnknown(agent.runtime_config);
  const commandValue = stringFromUnknown(adapterConfig.command);
  const providerValue =
    stringFromUnknown(runtimeConfig.model) ||
    stringFromUnknown(adapterConfig.model) ||
    stringFromUnknown(runtimeConfig.provider) ||
    stringFromUnknown(adapterConfig.provider) ||
    stringFromUnknown(agent.adapter_type);
  const provider = detectAgentCliProvider(commandValue, providerValue);
  if (provider === "codex") {
    return "Codex";
  }

  if (
    provider === "claude" &&
    (!providerValue.trim() || providerValue.trim().toLowerCase() === "process")
  ) {
    return "Claude";
  }

  const normalized = `${providerValue} ${commandValue}`.trim().toLowerCase();

  if (normalized.includes("claude")) {
    return "Claude";
  }

  if (normalized.includes("codex")) {
    return "Codex";
  }

  if (normalized.includes("gpt") || normalized.includes("openai")) {
    return "OpenAI";
  }

  if (normalized.includes("gemini")) {
    return "Gemini";
  }

  if (normalized.includes("cursor")) {
    return "Cursor";
  }

  return humanizeIssueValue(providerValue.replaceAll("-", " "));
}

function orgChartAgentIconKind(
  agent: AgentRecord,
  isRoot: boolean,
): "communication" | "engineering" | "finance" | "leadership" | "operations" {
  if (isRoot) {
    return "leadership";
  }

  const iconSource = [
    agent.icon,
    agent.title,
    agent.role,
    agent.name,
    agent.capabilities,
  ]
    .filter((value): value is string => typeof value === "string")
    .join(" ")
    .toLowerCase();

  if (
    iconSource.includes("account") ||
    iconSource.includes("finance") ||
    iconSource.includes("bookkeep") ||
    iconSource.includes("revenue")
  ) {
    return "finance";
  }

  if (
    iconSource.includes("social") ||
    iconSource.includes("marketing") ||
    iconSource.includes("content") ||
    iconSource.includes("community") ||
    iconSource.includes("sales")
  ) {
    return "communication";
  }

  if (
    iconSource.includes("engineer") ||
    iconSource.includes("developer") ||
    iconSource.includes("code") ||
    iconSource.includes("technical")
  ) {
    return "engineering";
  }

  if (
    iconSource.includes("manager") ||
    iconSource.includes("lead") ||
    iconSource.includes("founder") ||
    iconSource.includes("chief")
  ) {
    return "leadership";
  }

  return "operations";
}

function gitStatusBadge(status: string | null | undefined) {
  switch (status) {
    case "modified":
      return "M";
    case "added":
      return "A";
    case "deleted":
      return "D";
    case "renamed":
      return "R";
    case "copied":
      return "C";
    case "untracked":
      return "U";
    case "conflicted":
      return "!";
    default:
      return "•";
  }
}

function fileName(path: string) {
  return path.split("/").filter(Boolean).at(-1) ?? path;
}

function formatFileSize(bytes: number | null | undefined) {
  if (typeof bytes !== "number" || Number.isNaN(bytes) || bytes < 0) {
    return "Unknown size";
  }

  if (bytes < 1024) {
    return `${bytes} B`;
  }

  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  const decimals = value >= 10 ? 0 : 1;
  return `${value.toFixed(decimals)} ${units[unitIndex]}`;
}

function parentPath(path: string) {
  const parts = path.split("/").filter(Boolean);
  if (parts.length <= 1) {
    return "Repository root";
  }
  return parts.slice(0, -1).join("/");
}

function formatRelativeTimestamp(timestamp: number) {
  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const deltaSeconds = Math.round((timestamp * 1000 - Date.now()) / 1000);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["day", 86_400],
    ["hour", 3600],
    ["minute", 60],
  ];

  for (const [unit, secondsPerUnit] of units) {
    if (Math.abs(deltaSeconds) >= secondsPerUnit) {
      return formatter.format(Math.round(deltaSeconds / secondsPerUnit), unit);
    }
  }

  return formatter.format(deltaSeconds, "second");
}

function issuesVisible(
  issues: IssueRecord[],
  tab: IssuesListTab,
  now = new Date(),
) {
  const visibleIssues = issues.filter(
    (issue) => !issue.hidden_at && isRootConversationIssue(issue),
  );
  if (tab === "all") {
    return visibleIssues;
  }

  const threshold = new Date(now);
  threshold.setDate(threshold.getDate() - 7);

  return visibleIssues.filter((issue) => {
    const createdAt = parseIssueDate(issue.created_at);
    return createdAt ? createdAt >= threshold : false;
  });
}

function formatCompactIssueTimestamp(
  value: string | null | undefined,
  now = new Date(),
) {
  const date = parseIssueDate(value);
  if (!date) {
    return "Unknown";
  }

  const seconds = (now.getTime() - date.getTime()) / 1000;
  if (seconds < 60) {
    return "Just now";
  }
  if (seconds < 3600) {
    return `${Math.max(Math.floor(seconds / 60), 1)}m`;
  }
  if (seconds < 86_400) {
    return `${Math.max(Math.floor(seconds / 3600), 1)}h`;
  }

  const startOfNow = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
  );
  const dayDelta = Math.round(
    (startOfNow.getTime() - startOfDate.getTime()) / (24 * 60 * 60 * 1000),
  );

  if (dayDelta === 1) {
    return "Yesterday";
  }
  if (dayDelta < 7) {
    return new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(date);
  }

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
  }).format(date);
}

function parseIssueDate(value: string | null | undefined) {
  if (!value) {
    return null;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date;
}

function buildActivityFeedItems(
  issues: IssueRecord[],
  issueCommentsByIssueId: Record<string, IssueCommentRecord[]>,
  issueRunCardUpdatesByIssueId: Record<string, IssueRunCardUpdateRecord>,
  agents: AgentRecord[],
) {
  const visibleIssues = issues.filter((issue) => !issue.hidden_at);
  const issueById = new Map(visibleIssues.map((issue) => [issue.id, issue]));

  const messageItems: ActivityFeedItem[] = visibleIssues.flatMap((issue) => {
    const issueTitle = issue.identifier ?? issue.title;
    const comments = issueCommentsByIssueId[issue.id] ?? [];
    return comments.map((comment) => ({
      id: `comment-${comment.id}`,
      timestamp: parseIssueDate(comment.created_at) ?? new Date(0),
      title: issueCommentAuthorLabel(agents, comment),
      subtitle: `${issueTitle} · ${comment.body.trim() || "Message sent"}`,
      trailingLabel: "message",
      target: { kind: "issue", issueId: issue.id },
    }));
  });

  const runItems: ActivityFeedItem[] = Object.values(
    issueRunCardUpdatesByIssueId,
  ).flatMap((update) => {
    const issue = issueById.get(update.issue_id);
    if (!issue) {
      return [];
    }

    return [
      {
        id: `run-${update.run_id}`,
        timestamp: parseIssueDate(update.last_activity_at) ?? new Date(0),
        title: issueModelLabel(issue, agents),
        subtitle: `${issue.identifier ?? issue.title} · ${issueRunCardUpdateSummary(update)}`,
        trailingLabel: update.run_status,
        target: { kind: "issue", issueId: issue.id },
      },
    ];
  });

  return [...runItems, ...messageItems]
    .sort((left, right) => right.timestamp.getTime() - left.timestamp.getTime())
    .slice(0, 50);
}

function buildTerminalTranscript(messages: SessionMessage[]) {
  const lines = messages.flatMap((message) => {
    const content = normalizeMessageContent(message.content);
    if (typeof content !== "object" || content === null) {
      return [];
    }

    if (
      content.type === "terminal_output" &&
      typeof content.content === "string"
    ) {
      return [`[${String(content.stream ?? "stdout")}] ${content.content}`];
    }

    if (content.type === "terminal_finished") {
      return [`[exit ${String(content.exit_code ?? "unknown")}]`];
    }

    return [];
  });

  return lines.join("\n");
}

function normalizeMessageContent(
  value: unknown,
): Record<string, unknown> | string {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (typeof parsed === "object" && parsed !== null) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      return value;
    }
    return value;
  }

  if (typeof value === "object" && value !== null) {
    return value as Record<string, unknown>;
  }

  return String(value ?? "");
}

function describeMessageKind(value: unknown) {
  const content = normalizeMessageContent(value);
  if (typeof content === "string") {
    return "text";
  }
  return String(content.type ?? "json");
}

function renderMessageContent(value: unknown, showRaw: boolean) {
  const content = normalizeMessageContent(value);
  if (typeof content === "string") {
    return content;
  }

  if (showRaw) {
    return JSON.stringify(content, null, 2);
  }

  if (content.type === "terminal_output") {
    return String(content.content ?? "");
  }

  if (content.type === "terminal_finished") {
    return `Terminal finished with exit code ${String(content.exit_code ?? "unknown")}`;
  }

  if (content.type === "assistant" && content.message) {
    return JSON.stringify(content.message, null, 2);
  }

  if (content.type === "result" && typeof content.result === "string") {
    return content.result;
  }

  return JSON.stringify(content, null, 2);
}

function stringifyStatus(value: Record<string, unknown> | null) {
  if (!value) {
    return "unknown";
  }

  if (typeof value.status === "string") {
    return value.status;
  }

  if (typeof value.is_running === "boolean") {
    return value.is_running ? "running" : "idle";
  }

  return "ready";
}

function workspaceRuntimeTone(
  status: string,
  errorMessage?: string | null,
): "error" | "idle" | "running" | "waiting" {
  if (errorMessage && errorMessage.trim().length > 0) {
    return "error";
  }

  const normalized = status.trim().toLowerCase();
  if (normalized === "running" || normalized === "connected") {
    return "running";
  }
  if (normalized === "waiting" || normalized === "queued") {
    return "waiting";
  }
  if (normalized === "error" || normalized === "failed") {
    return "error";
  }
  return "idle";
}
