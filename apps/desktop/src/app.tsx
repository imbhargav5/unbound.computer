import { Terminal } from "@xterm/xterm";
import {
  type FormEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent,
  type PointerEvent,
  type RefObject,
  type ReactNode,
  type WheelEvent,
  startTransition,
  useDeferredValue,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  boardAddIssueComment,
  boardAddIssueAttachment,
  boardCancelAgentRun,
  boardApproveApproval,
  boardCompanySnapshot,
  boardCreateCompany,
  boardCreateIssue,
  boardCreateProject,
  boardDeleteProject,
  boardGetAgentRun,
  boardGetIssue,
  boardListIssueAttachments,
  boardListAgentRunEvents,
  boardListAgentRuns,
  boardListCompanies,
  boardListIssueComments,
  boardListIssueRunCardUpdates,
  boardListIssueRuns,
  boardReadAgentRunLog,
  boardResumeAgentRun,
  boardRetryAgentRun,
  boardUpdateAgent,
  boardUpdateCompany,
  boardUpdateIssue,
  agentSend,
  agentStatus,
  agentStop,
  desktopBootstrap,
  desktopOpenExternal,
  desktopPickFile,
  desktopPickRepositoryDirectory,
  desktopRevealInFinder,
  gitCommit,
  gitBranches,
  gitDiffFile,
  gitDiscard,
  gitLog,
  gitPush,
  gitStage,
  gitStatus,
  gitWorktrees,
  gitUnstage,
  listenToSessionEvents,
  listenToSessionStreamErrors,
  messageList,
  repositoryList,
  repositoryListFiles,
  repositoryReadFile,
  sessionList,
  sessionSubscribe,
  sessionUnsubscribe,
  settingsGet,
  settingsUpdate,
  systemCheckDependencies,
  terminalRun,
  terminalStatus,
  terminalStop,
} from "./lib/api";
import type {
  AgentRunEventRecord,
  AgentRunRecord,
  AgentRecord,
  ApprovalRecord,
  Company,
  CompanySnapshot,
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
  IssueAttachmentRecord,
  GoalRecord,
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
} from "./lib/types";

type AppScreen =
  | "dashboard"
  | "inbox"
  | "workspaces"
  | "org"
  | "agents"
  | "issues"
  | "approvals"
  | "projects"
  | "goals"
  | "stats"
  | "activity"
  | "costs"
  | "companySettings"
  | "appSettings";

type SettingsSection =
  | "general"
  | "appearance"
  | "notifications"
  | "privacy";

type ThemeMode = "system" | "light" | "dark";
type FontSizePreset = "small" | "medium" | "large";
type DesktopPreferredViewValue =
  | "dashboard"
  | "org"
  | "stats"
  | "activity"
  | "costs"
  | "workspaces"
  | "settings";
type IssuesListTab = "new" | "all";
type IssuesRouteMode = "list" | "detail";
type IssueDetailTab = "conversation" | "runs" | "subissues";
type AgentsRouteMode = "dashboard" | "configuration" | "runs";

interface IssueLinkedRun {
  label: string | null;
  run: AgentRunRecord;
}

type BoardRootLayout = "companyDashboard" | "workspace" | "settings";
type WorkspaceCenterTab = "conversation" | "terminal" | "preview";
type WorkspaceSidebarTab = "changes" | "files" | "commits";
type CompanyContextMenuScreen =
  | "dashboard"
  | "workspaces"
  | "org"
  | "issues"
  | "companySettings";
type CompanyContextMenuIconKey =
  | CompanyContextMenuScreen
  | "activity"
  | "agents"
  | "approvals"
  | "costs"
  | "goals"
  | "inbox"
  | "stats";

interface CompanyContextMenuState {
  companyId: string;
  companyName: string;
  agents: AgentRecord[];
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

interface DashboardProjectColumn {
  createDefaults: CreateIssueDialogDefaults;
  id: string;
  issues: IssueRecord[];
  label: string;
}

interface DashboardProjectBoardLayout {
  boardId: string;
  grouping: DashboardProjectGrouping;
  isDefaultView: boolean;
  project: ProjectRecord;
  columns: DashboardProjectColumn[];
  viewId: string;
  viewName: string;
  width: number;
  issueCount: number;
}

interface DashboardProjectColumnLayout {
  project: ProjectRecord;
  boards: DashboardProjectBoardLayout[];
  height: number;
  left: number;
  top: number;
  width: number;
}

interface SelectOption<T extends string> {
  label: string;
  value: T;
}

interface CreateIssueDialogDefaults {
  assigneeAgentId?: string;
  projectId?: string;
  priority?: string;
  status?: string;
}

interface DashboardProjectViewDraft {
  grouping: DashboardProjectGrouping;
  name: string;
}

interface IssueEditDraft {
  title: string;
  description: string;
  status: string;
  priority: string;
  projectId: string;
  assigneeAgentId: string;
  parentId: string;
  workspaceTargetMode: IssueWorkspaceTargetMode;
  workspaceWorktreePath: string;
  workspaceWorktreeBranch: string;
  workspaceWorktreeName: string;
}

interface ProjectWorktreeState {
  worktrees: GitWorktreeRecord[];
  isLoading: boolean;
  errorMessage: string | null;
}

interface IssueAttachmentDraft {
  path: string;
  name: string;
}

interface AgentConfigEnvVarDraft {
  id: string;
  key: string;
  value: string;
  mode: "plain" | "secret";
}

interface AgentConfigDraft {
  name: string;
  title: string;
  capabilities: string;
  promptTemplate: string;
  adapterType: string;
  workingDirectory: string;
  instructionsPath: string;
  command: string;
  model: string;
  thinkingEffort: string;
  bootstrapPrompt: string;
  enableChrome: boolean;
  skipPermissions: boolean;
  maxTurns: string;
  extraArgs: string;
  envVars: AgentConfigEnvVarDraft[];
  timeoutSec: string;
  interruptGraceSec: string;
  canCreateAgents: boolean;
  monthlyBudget: string;
}

type ActivityFeedTarget =
  | { kind: "approval"; approvalId: string }
  | { kind: "issue"; issueId: string };

interface ActivityFeedItem {
  id: string;
  timestamp: Date;
  title: string;
  subtitle: string;
  trailingLabel: string;
  target: ActivityFeedTarget;
}

interface DashboardBreadcrumbItem {
  label: string;
  onClick?: () => void;
}

function normalizeGitWorktreeRecords(value: unknown): GitWorktreeRecord[] {
  if (Array.isArray(value)) {
    return value.filter(
      (entry): entry is GitWorktreeRecord =>
        Boolean(entry) &&
        typeof entry === "object" &&
        typeof (entry as GitWorktreeRecord).path === "string" &&
        typeof (entry as GitWorktreeRecord).name === "string"
    );
  }

  if (value && typeof value === "object" && Array.isArray((value as { worktrees?: unknown }).worktrees)) {
    return normalizeGitWorktreeRecords((value as { worktrees: unknown }).worktrees);
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

function issueExecutionWorkspaceSettingsFromDraft(
  draft: Pick<
    IssueEditDraft,
    | "workspaceTargetMode"
    | "workspaceWorktreePath"
    | "workspaceWorktreeBranch"
    | "workspaceWorktreeName"
  >,
  projectId?: string | null
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
  worktreePath: string
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
  >
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
      (worktree) => worktree.path === selectedPath
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
    return "Link the issue to a project first.";
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

  return "Run in the repo root or create a fresh git worktree for this issue.";
}

const primaryBoardSections: Array<{ title: string; screens: AppScreen[] }> = [
  { title: "Work", screens: ["issues", "approvals", "workspaces"] },
  { title: "Planning", screens: ["goals"] },
];

const companyBoardSection: { title: string; screens: AppScreen[] } = {
  title: "Company",
  screens: ["org", "stats", "activity", "costs", "companySettings"],
};

const settingsSections: Array<{ id: SettingsSection; label: string }> = [
  { id: "general", label: "General" },
  { id: "appearance", label: "Appearance" },
  { id: "notifications", label: "Notifications" },
  { id: "privacy", label: "Privacy" },
];

const themeModes: ThemeMode[] = ["system", "light", "dark"];
const fontSizePresets: FontSizePreset[] = ["small", "medium", "large"];
const dashboardProjectGroupingOptions: DashboardProjectGrouping[] = [
  "status",
  "priority",
  "assignee",
];
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
  { label: "Org", value: "org" },
  { label: "Stats", value: "stats" },
  { label: "Activity", value: "activity" },
  { label: "Costs", value: "costs" },
  { label: "Worktrees", value: "workspaces" },
  { label: "Settings", value: "settings" },
];

const defaultSettings: DesktopSettings = {
  preferred_company_id: null,
  preferred_repository_id: null,
  preferred_view: "dashboard",
  show_raw_message_json: false,
  last_repository_path: null,
  theme_mode: "dark",
  font_size_preset: "medium",
  dashboard_project_views: {},
};

const companyContextMenuItems: Array<{
  icon: CompanyContextMenuIconKey;
  label: string;
  screen: CompanyContextMenuScreen;
}> = [
  { icon: "dashboard", label: "Dashboard", screen: "dashboard" },
  { icon: "workspaces", label: "Worktrees", screen: "workspaces" },
  { icon: "org", label: "Org", screen: "org" },
  { icon: "issues", label: "Issues", screen: "issues" },
  { icon: "companySettings", label: "Settings", screen: "companySettings" },
];

const defaultDashboardCanvasOffset: DashboardCanvasOffset = {
  x: 96,
  y: 88,
};

const dashboardProjectBoardMinWidth = 920;
const dashboardProjectBoardHeight = 540;
const dashboardProjectBoardGapX = 88;
const dashboardProjectBoardGapY = 80;
const dashboardProjectBoardStackGap = dashboardProjectBoardGapY;
const dashboardProjectBoardPadding = 18;
const dashboardProjectBoardBorderWidth = 1;
const dashboardProjectBoardColumnWidth = 170;
const dashboardProjectBoardColumnGap = 14;
const dashboardProjectAddViewSlotHeight = 126;
const dashboardDefaultProjectViewId = "default";

const defaultCompanyBrandColor = "#0F766E";

export function App() {
  const [bootstrap, setBootstrap] = useState<DesktopBootstrapStatus | null>(
    null
  );
  const [settings, setSettings] = useState<DesktopSettings>(defaultSettings);
  const [selectedScreen, setSelectedScreen] = useState<AppScreen>("dashboard");
  const [selectedSettingsSection, setSelectedSettingsSection] =
    useState<SettingsSection>("appearance");
  const [companies, setCompanies] = useState<Company[]>([]);
  const [repositories, setRepositories] = useState<RepositoryRecord[]>([]);
  const [selectedCompanyId, setSelectedCompanyId] = useState<string | null>(
    null
  );
  const [selectedRepositoryId, setSelectedRepositoryId] = useState<
    string | null
  >(null);
  const [selectedBoardWorkspaceId, setSelectedBoardWorkspaceId] = useState<
    string | null
  >(null);
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [selectedApprovalId, setSelectedApprovalId] = useState<string | null>(
    null
  );
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(
    null
  );
  const [selectedGoalId, setSelectedGoalId] = useState<string | null>(null);
  const [selectedIssueId, setSelectedIssueId] = useState<string | null>(null);
  const [selectedIssuesListTab, setSelectedIssuesListTab] =
    useState<IssuesListTab>("new");
  const [issuesRouteMode, setIssuesRouteMode] =
    useState<IssuesRouteMode>("list");
  const [agentsRouteMode, setAgentsRouteMode] =
    useState<AgentsRouteMode>("dashboard");
  const [companySnapshot, setCompanySnapshot] =
    useState<CompanySnapshot | null>(null);
  const [agentRuns, setAgentRuns] = useState<AgentRunRecord[]>([]);
  const [selectedAgentRunId, setSelectedAgentRunId] = useState<string | null>(
    null
  );
  const [selectedAgentRun, setSelectedAgentRun] =
    useState<AgentRunRecord | null>(null);
  const [agentRunEvents, setAgentRunEvents] = useState<AgentRunEventRecord[]>(
    []
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
  const [issueAttachmentsByIssueId, setIssueAttachmentsByIssueId] = useState<
    Record<string, IssueAttachmentRecord[]>
  >({});
  const [sessions, setSessions] = useState<SessionRecord[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(
    null
  );
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  const [gitState, setGitState] = useState<GitStatusResult | null>(null);
  const [gitHistory, setGitHistory] = useState<GitLogResult | null>(null);
  const [branchState, setBranchState] = useState<GitBranchesResult | null>(
    null
  );
  const [fileEntries, setFileEntries] = useState<FileEntry[]>([]);
  const [currentDirectory, setCurrentDirectory] = useState("");
  const [selectedFilePath, setSelectedFilePath] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<FileReadResult | null>(null);
  const [selectedDiff, setSelectedDiff] = useState<GitDiffResult | null>(null);
  const [dependencyCheck, setDependencyCheck] =
    useState<RuntimeCapabilities | null>(null);
  const [claudeStatusState, setClaudeStatusState] = useState<Record<
    string,
    unknown
  > | null>(null);
  const [terminalStatusState, setTerminalStatusState] = useState<Record<
    string,
    unknown
  > | null>(null);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [workspaceCenterTab, setWorkspaceCenterTab] =
    useState<WorkspaceCenterTab>("conversation");
  const [workspaceSidebarTab, setWorkspaceSidebarTab] =
    useState<WorkspaceSidebarTab>("changes");
  const [gitCommitMessage, setGitCommitMessage] = useState("");
  const [prompt, setPrompt] = useState("");
  const [terminalCommand, setTerminalCommand] = useState("");
  const [isCreateProjectDialogOpen, setIsCreateProjectDialogOpen] =
    useState(false);
  const [isCreateCompanyDialogOpen, setIsCreateCompanyDialogOpen] =
    useState(false);
  const [companyDialogName, setCompanyDialogName] = useState("");
  const [companyDialogDescription, setCompanyDialogDescription] = useState("");
  const [companyDialogBrandColor, setCompanyDialogBrandColor] = useState(
    defaultCompanyBrandColor
  );
  const [companyDialogError, setCompanyDialogError] = useState<string | null>(
    null
  );
  const [isCompanyDialogSaving, setIsCompanyDialogSaving] = useState(false);
  const [projectDialogRepoPath, setProjectDialogRepoPath] = useState("");
  const [projectDialogStatus, setProjectDialogStatus] = useState("planned");
  const [projectDialogGoalId, setProjectDialogGoalId] = useState("");
  const [projectDialogTargetDate, setProjectDialogTargetDate] = useState("");
  const [projectDialogError, setProjectDialogError] = useState<string | null>(
    null
  );
  const [isProjectDialogSaving, setIsProjectDialogSaving] = useState(false);
  const [isCreateIssueDialogOpen, setIsCreateIssueDialogOpen] = useState(false);
  const [issueDialogTitle, setIssueDialogTitle] = useState("");
  const [issueDialogDescription, setIssueDialogDescription] = useState("");
  const [issueDialogPriority, setIssueDialogPriority] = useState("medium");
  const [issueDialogStatus, setIssueDialogStatus] = useState("todo");
  const [issueDialogProjectId, setIssueDialogProjectId] = useState("");
  const [issueDialogAssigneeAgentId, setIssueDialogAssigneeAgentId] =
    useState("");
  const [issueDialogParentIssueId, setIssueDialogParentIssueId] = useState("");
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
  const [newIssueCommentBody, setNewIssueCommentBody] = useState("");
  const [newIssueCommentTargetAgentId, setNewIssueCommentTargetAgentId] =
    useState("");
  const [isEditingIssue, setIsEditingIssue] = useState(false);
  const [issueDraft, setIssueDraft] = useState<IssueEditDraft>(
    createEmptyIssueDraft()
  );
  const [isSavingIssue, setIsSavingIssue] = useState(false);
  const [issueEditorError, setIssueEditorError] = useState<string | null>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [companyContextMenu, setCompanyContextMenu] =
    useState<CompanyContextMenuState | null>(null);
  const [companyBrandColorDraft, setCompanyBrandColorDraft] = useState(
    defaultCompanyBrandColor
  );
  const [isSavingCompanyBrandColor, setIsSavingCompanyBrandColor] =
    useState(false);
  const [companyBrandColorError, setCompanyBrandColorError] = useState<
    string | null
  >(null);
  const [agentConfigDraft, setAgentConfigDraft] = useState<AgentConfigDraft>(
    createEmptyAgentConfigDraft()
  );
  const [isSavingAgentConfig, setIsSavingAgentConfig] = useState(false);
  const [agentConfigError, setAgentConfigError] = useState<string | null>(null);
  const [dashboardCanvasOffset, setDashboardCanvasOffset] =
    useState<DashboardCanvasOffset>(defaultDashboardCanvasOffset);
  const [isDashboardCanvasDragging, setIsDashboardCanvasDragging] =
    useState(false);

  const terminalContainerRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const refreshTimeoutRef = useRef<number | null>(null);
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

  const deferredMessages = useDeferredValue(messages);
  const selectedRepository = repositories.find(
    (repository) => repository.id === selectedRepositoryId
  );
  const selectedCompany = companySnapshot?.company ?? null;
  const boardIssues = companySnapshot?.issues ?? [];
  const selectedIssue =
    boardIssues.find((issue) => issue.id === selectedIssueId) ?? null;
  const visibleIssues = useMemo(
    () => issuesVisible(boardIssues, selectedIssuesListTab),
    [boardIssues, selectedIssuesListTab]
  );
  const activityVisibleIssues = useMemo(
    () => boardIssues.filter((issue) => !issue.hidden_at),
    [boardIssues]
  );
  const activityMissingCommentIssueIds = useMemo(
    () =>
      activityVisibleIssues
        .filter((issue) => issueCommentsByIssueId[issue.id] === undefined)
        .map((issue) => issue.id),
    [activityVisibleIssues, issueCommentsByIssueId]
  );
  const issueSummaryText = useMemo(() => {
    const suffix = visibleIssues.length === 1 ? "issue" : "issues";
    return `${issuesListTabTitle(selectedIssuesListTab)} · ${visibleIssues.length} ${suffix}`;
  }, [selectedIssuesListTab, visibleIssues.length]);
  const issueSubissues = useMemo(
    () =>
      selectedIssue
        ? boardIssues.filter((issue) => issue.parent_id === selectedIssue.id)
        : [],
    [boardIssues, selectedIssue]
  );
  const linkedIssueApprovals = useMemo(
    () =>
      selectedIssue
        ? (companySnapshot?.approvals ?? []).filter((approval) =>
            approvalLinksIssue(approval, selectedIssue.id)
          )
        : [],
    [companySnapshot?.approvals, selectedIssue]
  );
  const selectedIssueComments = selectedIssue
    ? (issueCommentsByIssueId[selectedIssue.id] ?? [])
    : [];
  const selectedIssueAttachments = selectedIssue
    ? (issueAttachmentsByIssueId[selectedIssue.id] ?? [])
    : [];
  const boardGoals = companySnapshot?.goals ?? [];
  const selectedGoal =
    boardGoals.find((goal) => goal.id === selectedGoalId) ??
    boardGoals[0] ??
    null;
  const boardProjects = companySnapshot?.projects ?? [];
  const issueDialogProjectRepoPath =
    boardProjects.find((project) => project.id === issueDialogProjectId)
      ?.primary_workspace?.cwd ?? null;
  const issueDialogWorktreeState = useProjectWorktrees(
    issueDialogProjectRepoPath
  );
  const issueDetailProjectRepoPath =
    boardProjects.find((project) => project.id === issueDraft.projectId)
      ?.primary_workspace?.cwd ?? null;
  const issueDetailWorktreeState = useProjectWorktrees(
    issueDetailProjectRepoPath
  );
  const boardAgents = companySnapshot?.agents ?? [];
  const dashboardProjectViews = settings.dashboard_project_views ?? {};
  const dashboardProjectColumns = useMemo(
    () =>
      buildDashboardProjectColumns(
        boardProjects,
        boardIssues,
        boardAgents,
        dashboardProjectViews
      ),
    [boardAgents, boardIssues, boardProjects, dashboardProjectViews]
  );
  const dashboardProjectIssueIds = useMemo(
    () =>
      Array.from(
        new Set(
          boardIssues
            .filter((issue) => issue.project_id && !issue.hidden_at)
            .map((issue) => issue.id)
        )
      ).sort(),
    [boardIssues]
  );
  const dashboardProjectIssueIdSet = useMemo(
    () => new Set(dashboardProjectIssueIds),
    [dashboardProjectIssueIds]
  );
  const dashboardCanvasBounds = useMemo(
    () => buildDashboardCanvasBounds(dashboardProjectColumns),
    [dashboardProjectColumns]
  );
  const selectedProject =
    boardProjects.find((project) => project.id === selectedProjectId) ??
    boardProjects[0] ??
    null;
  const boardApprovals = companySnapshot?.approvals ?? [];
  const selectedApproval =
    boardApprovals.find((approval) => approval.id === selectedApprovalId) ??
    boardApprovals[0] ??
    null;
  const companyWorkspaces = companySnapshot?.workspaces ?? [];
  const selectedBoardWorkspace =
    companyWorkspaces.find(
      (workspace) => workspace.id === selectedBoardWorkspaceId
    ) ??
    companyWorkspaces[0] ??
    null;
  const selectedIssueWorkspace = selectedIssue?.workspace_session_id
    ? companyWorkspaces.find(
        (workspace) =>
          workspace.id === selectedIssue.workspace_session_id ||
          workspace.session_id === selectedIssue.workspace_session_id
      ) ?? null
    : null;
  const selectedAgent =
    boardAgents.find((agent) => agent.id === selectedAgentId) ??
    boardAgents[0] ??
    null;
  const selectedAgentRunIsLive =
    selectedAgentRun?.status === "queued" ||
    selectedAgentRun?.status === "running";
  const selectedCompanyCeo = findCompanyCeo(
    boardAgents,
    selectedCompany?.ceo_agent_id ?? null
  );
  const orderedSidebarAgents = useMemo(
    () =>
      orderSidebarAgents(
        boardAgents,
        typeof selectedCompany?.ceo_agent_id === "string"
          ? selectedCompany.ceo_agent_id
          : null
      ),
    [boardAgents, selectedCompany?.ceo_agent_id]
  );
  const orderedSidebarProjects = useMemo(
    () =>
      [...boardProjects].sort((left, right) =>
        (left.name ?? left.title ?? left.id).localeCompare(
          right.name ?? right.title ?? right.id
        )
      ),
    [boardProjects]
  );
  const activeSession =
    sessions.find((session) => session.id === selectedSessionId) ?? null;
  const activeWorkspaceAgent =
    boardAgents.find((agent) => agent.id === selectedBoardWorkspace?.agent_id) ??
    null;
  const activeWorkspaceProvider = detectWorkspaceAgentProvider(
    activeSession,
    activeWorkspaceAgent
  );
  const activeWorkspaceProviderLabel =
    activeWorkspaceProvider === "codex"
      ? "Codex"
      : activeWorkspaceProvider === "claude"
        ? "Claude"
        : "Agent";
  const previewTabLabel = selectedFilePath
    ? (selectedFilePath.split("/").filter(Boolean).at(-1) ?? "Preview")
    : "Preview";
  const currentBranchName = branchState?.current ?? gitState?.branch ?? "main";
  const currentBranch =
    branchState?.local.find((branch) => branch.name === currentBranchName) ??
    null;
  const hasUncommittedChanges = (gitState?.files.length ?? 0) > 0;
  const hasUnpushedCommits = (currentBranch?.ahead ?? 0) > 0;
  const projectDialogDerivedName = useMemo(
    () => deriveProjectName(projectDialogRepoPath),
    [projectDialogRepoPath]
  );
  const issueStatusOptions = useMemo(
    () => mergeIssueOptions(canonicalIssueStatuses, issueDraft.status),
    [issueDraft.status]
  );
  const issuePriorityOptions = useMemo(
    () =>
      mergeIssueOptions(
        ["low", "medium", "high", "urgent"],
        issueDraft.priority
      ),
    [issueDraft.priority]
  );
  const selectableParentIssues = useMemo(
    () => boardIssues.filter((issue) => issue.id !== selectedIssue?.id),
    [boardIssues, selectedIssue?.id]
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
      dashboardCanvasBounds
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
            : null
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
    if (!agentId || !runId) {
      return;
    }

    setIsLoadingAgentRunDetail(true);

    try {
      const [run, events, logChunk] = await Promise.all([
        boardGetAgentRun(runId),
        boardListAgentRunEvents(
          runId,
          resetStreams ? undefined : agentRunEvents.at(-1)?.seq,
          400
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
            existingRun.id === run.id ? run : existingRun
          )
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
    operation: () => Promise<AgentRunRecord>
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

        const [loadedSettings, loadedCompanies, loadedRepositories] =
          await Promise.all([
            settingsGet(),
            boardListCompanies(),
            repositoryList(),
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
          setSelectedScreen(nextScreen);
          setSelectedCompanyId(nextCompanyId);
          setSelectedRepositoryId(nextRepositoryId);
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error)
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
  }, [dashboardCanvasBounds.height, dashboardCanvasBounds.width]);

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
          : null
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
          companyContextMenu.companyId
        );
        if (cancelled) {
          return;
        }

        const nextAgents = orderSidebarAgents(
          snapshot.agents ?? [],
          typeof snapshot.company?.ceo_agent_id === "string"
            ? snapshot.company.ceo_agent_id
            : null
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
          error instanceof Error ? error.message : String(error)
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
    if (!selectedCompanyId || bootstrap?.state !== "ready") {
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
            error instanceof Error ? error.message : String(error)
          );
        }
      }
    };

    void loadSnapshot();

    return () => {
      cancelled = true;
    };
  }, [bootstrap?.state, selectedCompanyId]);

  useEffect(() => {
    const nextWorkspaces = companySnapshot?.workspaces ?? [];
    const nextAgents = companySnapshot?.agents ?? [];
    const nextGoals = companySnapshot?.goals ?? [];
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

    setSelectedGoalId((current) => {
      if (current && nextGoals.some((goal) => goal.id === current)) {
        return current;
      }
      return nextGoals[0]?.id ?? null;
    });

    setIssueCommentsByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId)
        )
      )
    );
    setIssueAttachmentsByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId)
        )
      )
    );
    setIssueRunCardUpdatesByIssueId((current) =>
      Object.fromEntries(
        Object.entries(current).filter(([issueId]) =>
          nextIssues.some((issue) => issue.id === issueId)
        )
      )
    );
  }, [companySnapshot]);

  useEffect(() => {
    if (
      selectedScreen !== "dashboard" ||
      bootstrap?.state !== "ready" ||
      !selectedCompanyId
    ) {
      setIssueRunCardUpdatesByIssueId({});
      return;
    }

    if (dashboardProjectIssueIds.length === 0) {
      setIssueRunCardUpdatesByIssueId({});
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
          selectedCompanyId
        )) as IssueRunCardUpdateRecord[];
        if (cancelled) {
          return;
        }

        const nextUpdates = Object.fromEntries(
          updates
            .filter((update) => dashboardProjectIssueIdSet.has(update.issue_id))
            .map((update) => [update.issue_id, update])
        );
        const hasLiveUpdates = Object.values(nextUpdates).some(
          (update) =>
            update.run_status === "queued" || update.run_status === "running"
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

        scheduleRefresh(hasLiveUpdates ? 2000 : 10000);
      } catch (error) {
        if (cancelled) {
          return;
        }

        setStatusMessage(
          error instanceof Error ? error.message : String(error)
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
  }, [
    bootstrap?.state,
    dashboardProjectIssueIdSet,
    dashboardProjectIssueIds.length,
    selectedCompanyId,
    selectedScreen,
  ]);

  useEffect(() => {
    if (issuesRouteMode === "detail" && !selectedIssueId) {
      setIssuesRouteMode("list");
    }
  }, [issuesRouteMode, selectedIssueId]);

  useEffect(() => {
    if (!selectedIssue || issuesRouteMode !== "detail") {
      setNewIssueCommentBody("");
      setNewIssueCommentTargetAgentId("");
      setIsEditingIssue(false);
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
              issue.id === detailIssue.id ? detailIssue : issue
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
        setNewIssueCommentTargetAgentId(detailIssue.assignee_agent_id ?? "");
        setIsEditingIssue(false);
        setIssueEditorError(null);
        setNewIssueCommentBody("");
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error)
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
            [issueId, await boardListIssueComments(issueId)] as const
        )
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
          selectedRepositoryId
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
                (session) => session.id === boardWorkspaceSessionId
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
            error instanceof Error ? error.message : String(error)
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
      setMessages([]);
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
        const [
          nextMessages,
          nextFiles,
          nextGit,
          nextHistory,
          nextBranches,
          nextClaudeStatus,
          nextTerminalStatus,
        ] = await Promise.all([
          messageList(selectedSessionId),
          repositoryListFiles(selectedSessionId, ""),
          gitStatus(selectedSessionId),
          gitLog(selectedSessionId),
          gitBranches(selectedSessionId),
          agentStatus(selectedSessionId),
          terminalStatus(selectedSessionId),
        ]);

        if (cancelled) {
          return;
        }

        startTransition(() => {
          setMessages(nextMessages as SessionMessage[]);
          setFileEntries(nextFiles as FileEntry[]);
          setCurrentDirectory("");
          setSelectedDiff(null);
          setGitState(nextGit as GitStatusResult);
          setGitHistory(nextHistory as GitLogResult);
          setBranchState(nextBranches as GitBranchesResult);
          setClaudeStatusState(nextClaudeStatus);
          setTerminalStatusState(nextTerminalStatus);
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(
            error instanceof Error ? error.message : String(error)
          );
        }
      }
    };

    void loadWorkspace();
    void sessionSubscribe(selectedSessionId);

    return () => {
      cancelled = true;
      void sessionUnsubscribe(selectedSessionId);
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
      setStatusMessage(payload.message);
    }).then((cleanup) => {
      unlistenErrors = cleanup;
    });

    return () => {
      unlistenEvents?.();
      unlistenErrors?.();
    };
  }, [selectedSessionId]);

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
          setStatusMessage(error instanceof Error ? error.message : String(error));
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

  const activeSessionMessages = useMemo(() => {
    return deferredMessages
      .slice()
      .sort(
        (left, right) =>
          Number(left.sequence_number ?? 0) - Number(right.sequence_number ?? 0)
      );
  }, [deferredMessages]);

  const retryBootstrap = async () => {
    setStatusMessage(null);
    setBootstrap(null);

    try {
      const status = await desktopBootstrap();
      setBootstrap(status);
      if (status.state === "ready") {
        const [loadedSettings, loadedCompanies, loadedRepositories] =
          await Promise.all([
            settingsGet(),
            boardListCompanies(),
            repositoryList(),
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
        setSelectedScreen(normalizeScreen(nextSettings.preferred_view));
        setSelectedCompanyId(nextCompanyId);
        setSelectedRepositoryId(nextRepositoryId);
      }
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleSessionEvent = (payload: SessionStreamPayload) => {
    if (payload.session_id !== selectedSessionId) {
      return;
    }

    if (refreshTimeoutRef.current !== null) {
      window.clearTimeout(refreshTimeoutRef.current);
    }

    refreshTimeoutRef.current = window.setTimeout(() => {
      void refreshActiveSession(payload.session_id);
    }, 120);
  };

  const refreshActiveSession = async (sessionId: string) => {
    try {
      const [
        nextMessages,
        nextFiles,
        nextGit,
        nextHistory,
        nextBranches,
        nextTerminalStatus,
        nextClaudeStatus,
      ] = await Promise.all([
        messageList(sessionId),
        repositoryListFiles(sessionId, currentDirectory),
        gitStatus(sessionId),
        gitLog(sessionId),
        gitBranches(sessionId),
        terminalStatus(sessionId),
        agentStatus(sessionId),
      ]);
      setMessages(nextMessages as SessionMessage[]);
      setFileEntries(nextFiles as FileEntry[]);
      setGitState(nextGit as GitStatusResult);
      setGitHistory(nextHistory as GitLogResult);
      setBranchState(nextBranches as GitBranchesResult);
      setClaudeStatusState(nextClaudeStatus);
      setTerminalStatusState(nextTerminalStatus);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const refreshBoardData = async () => {
    if (!selectedCompanyId) {
      return;
    }

    try {
      const [loadedCompanies, snapshot] = await Promise.all([
        boardListCompanies(),
        boardCompanySnapshot(selectedCompanyId),
      ]);
      setCompanies(loadedCompanies as Company[]);
      setCompanySnapshot(snapshot);
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
    screen: CompanyContextMenuScreen
  ) => {
    if (screen === "dashboard") {
      handleSelectCompany(companyId);
      return;
    }

    setCompanyContextMenu(null);
    if (companyId !== selectedCompanyId) {
      setCompanySnapshot(null);
    }
    startTransition(() => {
      setSelectedCompanyId(companyId);
      setSelectedScreen(screen);
      if (screen === "workspaces") {
        setWorkspaceCenterTab("conversation");
      }
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
    company: Company
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
              : null
          )
        : [];
    const nextX = Math.min(
      Math.max(event.clientX + 12, viewportPadding),
      window.innerWidth - menuWidth - viewportPadding
    );
    const nextY = Math.min(
      Math.max(event.clientY - 8, viewportPadding),
      window.innerHeight - menuHeight - viewportPadding
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
    event: PointerEvent<HTMLDivElement>
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
    event: PointerEvent<HTMLDivElement>
  ) => {
    const panState = dashboardCanvasPanRef.current;
    if (!panState || panState.pointerId !== event.pointerId) {
      return;
    }

    setDashboardCanvasOffset(
      clampDashboardOffset({
        x: panState.originX + event.clientX - panState.startX,
        y: panState.originY + event.clientY - panState.startY,
      })
    );
  };

  const handleDashboardCanvasPointerEnd = (
    event: PointerEvent<HTMLDivElement>
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
    if (target?.closest(".project-kanban-columns")) {
      return;
    }

    event.preventDefault();
    setDashboardCanvasOffset((current) =>
      clampDashboardOffset({
        x: current.x - event.deltaX,
        y: current.y - event.deltaY,
      })
    );
  };

  const handleSelectBoardWorkspace = (workspace: WorkspaceRecord) => {
    startTransition(() => {
      setSelectedBoardWorkspaceId(workspace.id);
      setSelectedScreen("workspaces");
      setWorkspaceCenterTab("conversation");
      setSelectedRepositoryId(workspace.repository_id);
      setSelectedSessionId(workspace.session_id);
    });

    void persistSettings({
      ...settings,
      preferred_repository_id: workspace.repository_id,
      preferred_view: preferredViewForScreen("workspaces"),
    });
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
    grouping: DashboardProjectGrouping
  ) => {
    const currentProjectViews = dashboardProjectViews[projectId] ?? {};
    const currentSavedViews = dashboardProjectSavedViews(
      currentProjectViews.saved_views
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
                    : savedView
                ),
              }),
        },
      },
    });
  };

  const handleCreateProjectBoardView = async (
    projectId: string,
    draft: DashboardProjectViewDraft
  ) => {
    const currentProjectViews = dashboardProjectViews[projectId] ?? {};
    const currentSavedViews = dashboardProjectSavedViews(
      currentProjectViews.saved_views
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
        error instanceof Error ? error.message : String(error)
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
        error instanceof Error ? error.message : String(error)
      );
    }
  };

  const handleAgentConfigEnvVarChange = (
    envId: string,
    patch: Partial<AgentConfigEnvVarDraft>
  ) => {
    setAgentConfigDraft((current) => ({
      ...current,
      envVars: current.envVars.map((envVar) =>
        envVar.id === envId ? { ...envVar, ...patch } : envVar
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
        buildAgentConfigUpdateParams(selectedAgent, agentConfigDraft)
      );
      setCompanySnapshot((current) =>
        current
          ? {
              ...current,
              agents: current.agents.map((agent) =>
                agent.id === updatedAgent.id ? updatedAgent : agent
              ),
            }
          : current
      );
      setAgentConfigDraft(createAgentConfigDraft(updatedAgent));
    } catch (error) {
      setAgentConfigError(
        error instanceof Error ? error.message : String(error)
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
          : current
      );
      setCompanies((current) =>
        current.map((company) =>
          company.id === updatedCompany.id
            ? { ...company, ...updatedCompany }
            : company
        )
      );
    } catch (error) {
      setCompanyBrandColorDraft(
        normalizeHexColor(selectedCompany?.brand_color)
      );
      setCompanyBrandColorError(
        error instanceof Error ? error.message : String(error)
      );
    } finally {
      setIsSavingCompanyBrandColor(false);
    }
  };

  const resetProjectDialog = () => {
    setProjectDialogRepoPath("");
    setProjectDialogStatus("planned");
    setProjectDialogGoalId("");
    setProjectDialogTargetDate("");
    setProjectDialogError(null);
    setIsProjectDialogSaving(false);
  };

  const handleOpenCreateProjectDialog = () => {
    resetProjectDialog();
    setIsCreateProjectDialogOpen(true);
  };

  const handleCloseCreateProjectDialog = () => {
    setIsCreateProjectDialogOpen(false);
    resetProjectDialog();
  };

  const handleChooseProjectFolder = async () => {
    setProjectDialogError(null);
    try {
      const path = await desktopPickRepositoryDirectory();
      if (path) {
        setProjectDialogRepoPath(path);
      }
    } catch (error) {
      setProjectDialogError(
        error instanceof Error ? error.message : String(error)
      );
    }
  };

  const handleCreateProjectFromDialog = async () => {
    if (
      !selectedCompanyId ||
      !projectDialogDerivedName ||
      isProjectDialogSaving
    ) {
      return;
    }

    setIsProjectDialogSaving(true);
    setProjectDialogError(null);

    try {
      const params: Record<string, unknown> = {
        company_id: selectedCompanyId,
        name: projectDialogDerivedName,
        repo_path: projectDialogRepoPath.trim(),
        status: projectDialogStatus,
      };

      if (projectDialogGoalId) {
        params.goal_id = projectDialogGoalId;
      }

      if (projectDialogTargetDate) {
        params.target_date = new Date(
          `${projectDialogTargetDate}T00:00:00`
        ).toISOString();
      }

      const project = await boardCreateProject(params);
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setSelectedProjectId(project.id);
      setSelectedScreen("projects");
      handleCloseCreateProjectDialog();
    } catch (error) {
      setProjectDialogError(
        error instanceof Error ? error.message : String(error)
      );
      setIsProjectDialogSaving(false);
    }
  };

  const resetIssueDialog = () => {
    setIssueDialogTitle("");
    setIssueDialogDescription("");
    setIssueDialogPriority("medium");
    setIssueDialogStatus("todo");
    setIssueDialogProjectId("");
    setIssueDialogAssigneeAgentId("");
    setIssueDialogParentIssueId("");
    setIssueDialogWorkspaceTargetMode("main");
    setIssueDialogWorkspaceWorktreePath("");
    setIssueDialogWorkspaceWorktreeBranch("");
    setIssueDialogWorkspaceWorktreeName("");
    setIssueDialogAttachments([]);
    setIssueDialogError(null);
    setIsIssueDialogSaving(false);
  };

  const handleIssueDialogProjectChange = (projectId: string) => {
    setIssueDialogProjectId(projectId);
    setIssueDialogWorkspaceTargetMode("main");
    setIssueDialogWorkspaceWorktreePath("");
    setIssueDialogWorkspaceWorktreeBranch("");
    setIssueDialogWorkspaceWorktreeName("");
  };

  const handleIssueDialogWorkspaceTargetChange = (value: string) => {
    const patch = issueWorkspaceDraftPatchFromSelection(
      value,
      issueDialogWorktreeState.worktrees,
      {
        workspaceWorktreeBranch: issueDialogWorkspaceWorktreeBranch,
        workspaceWorktreeName: issueDialogWorkspaceWorktreeName,
        workspaceWorktreePath: issueDialogWorkspaceWorktreePath,
      }
    );

    setIssueDialogWorkspaceTargetMode(
      (patch.workspaceTargetMode ?? "main") as IssueWorkspaceTargetMode
    );
    setIssueDialogWorkspaceWorktreePath(patch.workspaceWorktreePath ?? "");
    setIssueDialogWorkspaceWorktreeBranch(patch.workspaceWorktreeBranch ?? "");
    setIssueDialogWorkspaceWorktreeName(patch.workspaceWorktreeName ?? "");
  };

  const handleOpenCreateIssueDialog = (
    defaults?: CreateIssueDialogDefaults
  ) => {
    resetIssueDialog();
    setIssueDialogAssigneeAgentId(defaults?.assigneeAgentId ?? "");
    setIssueDialogPriority(defaults?.priority ?? "medium");
    setIssueDialogStatus(normalizeBoardIssueValue(defaults?.status ?? "todo"));
    setIssueDialogProjectId(defaults?.projectId ?? "");
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
        error instanceof Error ? error.message : String(error)
      );
    }
  };

  const handleRemoveIssueDialogAttachment = (path: string) => {
    setIssueDialogAttachments((current) =>
      current.filter((attachment) => attachment.path !== path)
    );
  };

  const handleCreateIssueFromDialog = async () => {
    if (!selectedCompanyId || !issueDialogTitle.trim() || isIssueDialogSaving) {
      return;
    }

    const validationMessage = issueStatusAssigneeValidationMessage(
      issueDialogStatus,
      issueDialogAssigneeAgentId,
      boardAgents
    );
    if (validationMessage) {
      return;
    }

    setIsIssueDialogSaving(true);
    setIssueDialogError(null);

    try {
      const params: Record<string, unknown> = {
        company_id: selectedCompanyId,
        title: issueDialogTitle.trim(),
        status: normalizeBoardIssueValue(issueDialogStatus),
        priority: issueDialogPriority,
      };

      if (issueDialogDescription.trim()) {
        params.description = issueDialogDescription.trim();
      }
      if (issueDialogProjectId) {
        params.project_id = issueDialogProjectId;
      }
      if (issueDialogAssigneeAgentId) {
        params.assignee_agent_id = issueDialogAssigneeAgentId;
      }
      if (issueDialogParentIssueId) {
        params.parent_id = issueDialogParentIssueId;
      }
      const executionWorkspaceSettings =
        issueExecutionWorkspaceSettingsFromDraft({
          workspaceTargetMode: issueDialogWorkspaceTargetMode,
          workspaceWorktreePath: issueDialogWorkspaceWorktreePath,
          workspaceWorktreeBranch: issueDialogWorkspaceWorktreeBranch,
          workspaceWorktreeName: issueDialogWorkspaceWorktreeName,
        }, issueDialogProjectId);
      if (executionWorkspaceSettings) {
        params.execution_workspace_settings = executionWorkspaceSettings;
      }

      const createdIssue = await boardCreateIssue(params);
      let uploadedAttachments: IssueAttachmentRecord[] = [];
      let attachmentUploadMessage: string | null = null;

      if (issueDialogAttachments.length > 0) {
        const uploadResults = await Promise.allSettled(
          issueDialogAttachments.map((attachment) =>
            boardAddIssueAttachment({
              company_id: createdIssue.company_id,
              issue_id: createdIssue.id,
              local_file_path: attachment.path,
            })
          )
        );

        uploadedAttachments = uploadResults.flatMap((result) =>
          result.status === "fulfilled" ? [result.value] : []
        );

        const failedUploads = uploadResults.filter(
          (result) => result.status === "rejected"
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

      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      if (uploadedAttachments.length > 0) {
        setIssueAttachmentsByIssueId((current) => ({
          ...current,
          [createdIssue.id]: uploadedAttachments,
        }));
      }
      setSelectedIssueId(createdIssue.id);
      setIssueDraft(createIssueDraft(createdIssue));
      setIssuesRouteMode("detail");
      setSelectedScreen("issues");
      void persistSettings({
        ...settings,
        preferred_view: preferredViewForScreen("issues"),
      });
      handleCloseCreateIssueDialog();
      if (attachmentUploadMessage) {
        setStatusMessage(
          `${createdIssue.identifier ?? createdIssue.title} created, but one or more attachments failed to upload: ${attachmentUploadMessage}`
        );
      }
    } catch (error) {
      setIssueDialogError(
        error instanceof Error ? error.message : String(error)
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

  const handleSelectIssue = async (issueId: string) => {
    setStatusMessage(null);
    try {
      const issue = await boardGetIssue(issueId);
      setSelectedIssueId((issue as IssueRecord).id);
      setIssueDraft(createIssueDraft(issue as IssueRecord));
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

  const beginEditingIssue = (issue: IssueRecord) => {
    setIssueDraft(createIssueDraft(issue));
    setIssueEditorError(null);
    setIsEditingIssue(true);
  };

  const discardIssueEdits = (issue: IssueRecord) => {
    setIssueDraft(createIssueDraft(issue));
    setIssueEditorError(null);
    setIsEditingIssue(false);
  };

  function enqueueIssueUpdate<T>(task: () => Promise<T>) {
    const nextTask = issueUpdateQueueRef.current.then(task, task);
    issueUpdateQueueRef.current = nextTask.then(
      () => undefined,
      () => undefined
    );
    return nextTask;
  }

  const applyIssueUpdateToSnapshot = (
    updatedIssue: IssueRecord,
    options?: { removeFromSnapshot?: boolean }
  ) => {
    setCompanySnapshot((current) => {
      if (!current) {
        return current;
      }

      const nextIssues = options?.removeFromSnapshot
        ? current.issues.filter((entry) => entry.id !== updatedIssue.id)
        : current.issues.map((entry) =>
            entry.id === updatedIssue.id ? updatedIssue : entry
          );

      return {
        ...current,
        issues: nextIssues,
      };
    });
  };

  const syncIssueDraftFromUpdate = (
    updatedIssue: IssueRecord,
    patch: Partial<IssueEditDraft>
  ) => {
    const nextDraftPatch: Partial<IssueEditDraft> = {};

    if (Object.prototype.hasOwnProperty.call(patch, "title")) {
      nextDraftPatch.title = updatedIssue.title;
    }
    if (Object.prototype.hasOwnProperty.call(patch, "description")) {
      nextDraftPatch.description = updatedIssue.description ?? "";
    }
    if (Object.prototype.hasOwnProperty.call(patch, "status")) {
      nextDraftPatch.status = updatedIssue.status;
    }
    if (Object.prototype.hasOwnProperty.call(patch, "priority")) {
      nextDraftPatch.priority = updatedIssue.priority;
    }
    if (Object.prototype.hasOwnProperty.call(patch, "projectId")) {
      nextDraftPatch.projectId = updatedIssue.project_id ?? "";
    }
    if (Object.prototype.hasOwnProperty.call(patch, "assigneeAgentId")) {
      nextDraftPatch.assigneeAgentId = updatedIssue.assignee_agent_id ?? "";
    }
    if (Object.prototype.hasOwnProperty.call(patch, "parentId")) {
      nextDraftPatch.parentId = updatedIssue.parent_id ?? "";
    }
    if (
      Object.prototype.hasOwnProperty.call(patch, "workspaceTargetMode") ||
      Object.prototype.hasOwnProperty.call(patch, "workspaceWorktreePath") ||
      Object.prototype.hasOwnProperty.call(patch, "workspaceWorktreeBranch") ||
      Object.prototype.hasOwnProperty.call(patch, "workspaceWorktreeName")
    ) {
      Object.assign(
        nextDraftPatch,
        parseIssueExecutionWorkspaceSettings(
          updatedIssue.execution_workspace_settings
        )
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
    options?: { hiddenAt?: string | null }
  ) =>
    enqueueIssueUpdate(async () => {
      const shouldValidateIssueStatus =
        Object.prototype.hasOwnProperty.call(patch, "status") ||
        Object.prototype.hasOwnProperty.call(patch, "assigneeAgentId");
      if (shouldValidateIssueStatus) {
        const validationMessage = issueStatusAssigneeValidationMessage(
          Object.prototype.hasOwnProperty.call(patch, "status")
            ? patch.status
            : issueDraft.status,
          Object.prototype.hasOwnProperty.call(patch, "assigneeAgentId")
            ? patch.assigneeAgentId
            : issueDraft.assigneeAgentId,
          boardAgents
        );
        if (validationMessage) {
          return null;
        }
      }

      const params: Record<string, unknown> = {
        issue_id: issue.id,
      };

      if (Object.prototype.hasOwnProperty.call(patch, "title")) {
        const trimmedTitle = (patch.title ?? "").trim();
        if (!trimmedTitle) {
          setIssueEditorError("Issue title is required.");
          return null;
        }
        params.title = trimmedTitle;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "description")) {
        const trimmedDescription = (patch.description ?? "").trim();
        params.description = trimmedDescription ? trimmedDescription : null;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "status")) {
        params.status = patch.status;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "priority")) {
        params.priority = patch.priority;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "projectId")) {
        params.project_id = patch.projectId?.trim()
          ? patch.projectId.trim()
          : null;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "assigneeAgentId")) {
        params.assignee_agent_id = patch.assigneeAgentId?.trim()
          ? patch.assigneeAgentId.trim()
          : null;
      }

      if (Object.prototype.hasOwnProperty.call(patch, "parentId")) {
        params.parent_id = patch.parentId?.trim()
          ? patch.parentId.trim()
          : null;
      }

      const shouldPersistWorkspaceSettings =
        Object.prototype.hasOwnProperty.call(patch, "workspaceTargetMode") ||
        Object.prototype.hasOwnProperty.call(patch, "workspaceWorktreePath") ||
        Object.prototype.hasOwnProperty.call(
          patch,
          "workspaceWorktreeBranch"
        ) ||
        Object.prototype.hasOwnProperty.call(patch, "workspaceWorktreeName");

      if (shouldPersistWorkspaceSettings) {
        params.execution_workspace_settings =
          issueExecutionWorkspaceSettingsFromDraft({
            workspaceTargetMode:
              patch.workspaceTargetMode ?? issueDraft.workspaceTargetMode,
            workspaceWorktreePath:
              patch.workspaceWorktreePath ?? issueDraft.workspaceWorktreePath,
            workspaceWorktreeBranch:
              patch.workspaceWorktreeBranch ?? issueDraft.workspaceWorktreeBranch,
            workspaceWorktreeName:
              patch.workspaceWorktreeName ?? issueDraft.workspaceWorktreeName,
          }, patch.projectId ?? issueDraft.projectId);
      }

      if (
        options &&
        Object.prototype.hasOwnProperty.call(options, "hiddenAt")
      ) {
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
        setIsEditingIssue(false);
        setIssuesRouteMode(isHidden ? "list" : "detail");

        if (isHidden) {
          setStatusMessage(
            `${updatedIssue.identifier ?? updatedIssue.title} hidden.`
          );
        }

        return updatedIssue;
      } catch (error) {
        setIssueEditorError(
          error instanceof Error ? error.message : String(error)
        );
        return null;
      } finally {
        setIsSavingIssue(false);
      }
    });

  const handleSaveIssueEdits = async (issue: IssueRecord) =>
    handlePersistIssuePatch(issue, {
      title: issueDraft.title,
      description: issueDraft.description,
      status: issueDraft.status,
      priority: issueDraft.priority,
      projectId: issueDraft.projectId,
      assigneeAgentId: issueDraft.assigneeAgentId,
      parentId: issueDraft.parentId,
      workspaceTargetMode: issueDraft.workspaceTargetMode,
      workspaceWorktreePath: issueDraft.workspaceWorktreePath,
      workspaceWorktreeBranch: issueDraft.workspaceWorktreeBranch,
      workspaceWorktreeName: issueDraft.workspaceWorktreeName,
    });

  const handleHideIssue = async (issue: IssueRecord) =>
    handlePersistIssuePatch(issue, {}, { hiddenAt: new Date().toISOString() });

  const handleAddIssueComment = async (issue: IssueRecord) => {
    const body = newIssueCommentBody.trim();
    if (!body) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await boardAddIssueComment({
        company_id: issue.company_id,
        issue_id: issue.id,
        target_agent_id: newIssueCommentTargetAgentId || undefined,
        body,
      });
      const [comments, snapshot] = await Promise.all([
        boardListIssueComments(issue.id),
        boardCompanySnapshot(issue.company_id),
      ]);
      setCompanySnapshot(snapshot);
      setIssueCommentsByIssueId((current) => ({
        ...current,
        [issue.id]: comments as IssueCommentRecord[],
      }));
      setNewIssueCommentBody("");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
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
        `${attachment.original_filename ?? fileName(path)} attached to ${issue.identifier ?? issue.title}.`
      );
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleRevealIssueAttachment = async (
    attachment: IssueAttachmentRecord
  ) => {
    try {
      await desktopRevealInFinder(attachment.local_path);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const handleApproveApproval = async (
    approvalId: string,
    decisionNote?: string
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
        relativePath
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

  const handleRunAgent = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedSessionId || !prompt.trim()) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await agentSend(
        selectedSessionId,
        prompt.trim(),
        activeWorkspaceProvider === "custom" ? undefined : activeWorkspaceProvider
      );
      setPrompt("");
      await refreshActiveSession(selectedSessionId);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleRunTerminal = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedSessionId || !terminalCommand.trim()) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await terminalRun(selectedSessionId, terminalCommand.trim());
      setTerminalCommand("");
      const nextTerminalStatus = await terminalStatus(selectedSessionId);
      setTerminalStatusState(nextTerminalStatus);
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
      });
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
        error instanceof Error ? error.message : String(error)
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
      await refreshActiveSession(selectedSessionId);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleStageFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitStage([file.path], selectedSessionId ?? undefined)
    );
  };

  const handleUnstageFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitUnstage([file.path], selectedSessionId ?? undefined)
    );
  };

  const handleDiscardFile = async (file: GitStatusFile) => {
    await runGitMutation(() =>
      gitDiscard([file.path], selectedSessionId ?? undefined)
    );
  };

  const handleGitCommit = async (pushAfterCommit = false) => {
    if (!selectedSessionId || !gitCommitMessage.trim()) {
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
      })
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
                  "https://github.com/unbound-computer/unbound"
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

  const activeWorkspaceTitle =
    activeSession?.title ??
    selectedBoardWorkspace?.issue_title ??
    selectedBoardWorkspace?.title ??
    null;
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
            aria-label="Create company"
            className="company-rail-button add"
            onClick={handleOpenCreateCompanyDialog}
            title="Create company"
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
            <div className="company-context-menu-monogram" aria-hidden="true">
              {companyContextMenu.companyName.slice(0, 1).toUpperCase()}
            </div>
            <div className="company-context-menu-copy">
              <strong>{companyContextMenu.companyName}</strong>
              <span>Shortcuts and agent pages</span>
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
                      item.screen
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
          <div className="company-context-menu-divider" />
          <div className="company-context-menu-section">
            <div className="company-context-menu-section-label">
              <CompanyContextMenuIcon icon="agents" />
              <span>Agents</span>
            </div>
            <div className="company-context-menu-agent-list">
              {companyContextMenu.isLoadingAgents ? (
                <div className="company-context-menu-empty">
                  Loading agents...
                </div>
              ) : companyContextMenu.agents.length ? (
                companyContextMenu.agents.map((agent) => {
                  const isActive =
                    companyContextMenu.companyId === selectedCompanyId &&
                    selectedScreen === "agents" &&
                    selectedAgentId === agent.id;

                  return (
                    <button
                      className={
                        isActive
                          ? "company-context-menu-item company-context-menu-item-agent active"
                          : "company-context-menu-item company-context-menu-item-agent"
                      }
                      key={agent.id}
                      onClick={() =>
                        handleSelectCompanyAgent(
                          companyContextMenu.companyId,
                          agent.id
                        )
                      }
                      role="menuitem"
                      type="button"
                    >
                      <CompanyContextMenuIcon icon="agents" />
                      <span className="company-context-menu-agent-copy">
                        <strong>
                          {agent.name || agent.title || agent.role || "Agent"}
                        </strong>
                        <small>{agent.title ?? agent.role ?? "Agent"}</small>
                      </span>
                    </button>
                  );
                })
              ) : (
                <div className="company-context-menu-empty">No agents yet</div>
              )}
            </div>
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
                  <strong>{selectedCompany?.name ?? "Company"}</strong>
                  <span>Local board</span>
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
                    label="New Issue"
                    onClick={handleOpenCreateIssueDialog}
                  />
                  <BoardSidebarButton
                    active={false}
                    icon="dashboard"
                    label="Dashboard"
                    onClick={() => handleSelectScreen("dashboard")}
                  />
                  <BoardSidebarButton
                    active={selectedScreen === "inbox"}
                    icon="inbox"
                    label="Inbox"
                    onClick={() => handleSelectScreen("inbox")}
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
                    <span className="sidebar-section-title">Agents</span>
                  </div>
                  {orderedSidebarAgents.length ? (
                    orderedSidebarAgents.map((agent) => (
                      <button
                        className={
                          selectedScreen === "agents" &&
                          selectedAgentId === agent.id
                            ? "agent-sidebar-button active"
                            : "agent-sidebar-button"
                        }
                        key={agent.id}
                        onClick={() => handleSelectAgent(agent.id)}
                        type="button"
                      >
                        <span
                          aria-hidden="true"
                          className="agent-sidebar-avatar"
                        >
                          {sidebarAgentAvatarLabel(agent)}
                        </span>
                        <span className="agent-sidebar-button-label">
                          {agent.name || agent.title || agent.role || agent.id}
                        </span>
                      </button>
                    ))
                  ) : (
                    <div className="agent-sidebar-empty">No agents yet</div>
                  )}
                </div>

                <div className="board-sidebar-section">
                  <div className="sidebar-section-row">
                    <span className="sidebar-section-title">Projects</span>
                  </div>
                  <SidebarLinkButton
                    label="New Project"
                    onClick={handleOpenCreateProjectDialog}
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
              <DashboardCanvasRouteView
                agents={boardAgents}
                canvasBounds={dashboardCanvasBounds}
                canvasOffset={dashboardCanvasOffset}
                isDragging={isDashboardCanvasDragging}
                onCreateProject={handleOpenCreateProjectDialog}
                onOpenIssue={(issueId) => void handleSelectIssue(issueId)}
                onPointerCancel={handleDashboardCanvasPointerEnd}
                onPointerDown={handleDashboardCanvasPointerDown}
                onPointerMove={handleDashboardCanvasPointerMove}
                onPointerUp={handleDashboardCanvasPointerEnd}
                onCreateIssueForColumn={handleOpenCreateIssueDialog}
                onCreateProjectView={handleCreateProjectBoardView}
                onProjectGroupingChange={handleProjectBoardGroupingChange}
                issueRunCardUpdatesByIssueId={issueRunCardUpdatesByIssueId}
                projectColumns={dashboardProjectColumns}
                selectedProjectId={selectedProjectId}
                viewportRef={dashboardCanvasViewportRef}
                onWheel={handleDashboardCanvasWheel}
              />
            ) : null}

            {selectedScreen === "stats" ? (
              <StatsRouteView
                bootstrap={bootstrap}
                company={selectedCompany}
                dependencyCheck={dependencyCheck}
                onCheckDependencies={() => void loadDependencies()}
                onOpenWorkspace={handleSelectBoardWorkspace}
                repositoriesCount={repositories.length}
                snapshot={companySnapshot}
              />
            ) : null}

            {selectedScreen === "inbox" ? (
              <RoutePlaceholder
                body="Inbox routing exists in the shell now. Use Approvals and Issues while the daemon inbox surface catches up."
                title="Inbox"
              />
            ) : null}

            {selectedScreen === "org" ? (
              <OrgRouteView
                agents={boardAgents}
                company={selectedCompany}
                projects={boardProjects}
                selectedAgentId={selectedAgentId}
                onSelectAgent={handleSelectAgent}
              />
            ) : null}

            {selectedScreen === "agents" ? (
              <AgentsRouteView
                agentRunError={agentRunError}
                agentRunEvents={agentRunEvents}
                agentRunLogContent={agentRunLogContent}
                agentRuns={agentRuns}
                companyName={selectedCompany?.name ?? "Unbound"}
                dependencyCheck={dependencyCheck}
                isLoadingAgentRunDetail={isLoadingAgentRunDetail}
                isLoadingAgentRuns={isLoadingAgentRuns}
                isPerformingAgentRunAction={isPerformingAgentRunAction}
                isSavingConfiguration={isSavingAgentConfig}
                configurationDraft={agentConfigDraft}
                configurationError={agentConfigError}
                mode={agentsRouteMode}
                onAddEnvVar={handleAddAgentConfigEnvVar}
                onCancelSelectedRun={() => void handleCancelSelectedAgentRun()}
                onChooseInstructionsFile={() =>
                  void handleChooseAgentInstructionsFile()
                }
                onChooseWorkingDirectory={() =>
                  void handleChooseAgentWorkingDirectory()
                }
                onConfigurationDraftChange={(patch) =>
                  setAgentConfigDraft((current) => ({
                    ...current,
                    ...patch,
                  }))
                }
                onConfigurationEnvVarChange={handleAgentConfigEnvVarChange}
                onRemoveEnvVar={handleRemoveAgentConfigEnvVar}
                onRefreshRuns={() => void handleRefreshAgentRuns()}
                onResumeSelectedRun={() => void handleResumeSelectedAgentRun()}
                onRetrySelectedRun={() => void handleRetrySelectedAgentRun()}
                onSaveConfiguration={() => void handleSaveAgentConfiguration()}
                onSelectRun={handleSelectAgentRun}
                onSelectTab={handleSelectAgentTab}
                selectedAgent={selectedAgent}
                selectedRun={selectedAgentRun}
              />
            ) : null}

            {selectedScreen === "issues" ? (
              issuesRouteMode === "detail" && selectedIssue ? (
                <IssueDetailView
                  assigneeLabel={(assigneeAgentId) =>
                    issueAssigneeLabel(
                      companySnapshot?.agents ?? [],
                      assigneeAgentId
                    )
                  }
                  attachments={selectedIssueAttachments}
                  availablePriorityOptions={issuePriorityOptions}
                  availableStatusOptions={issueStatusOptions}
                  comments={selectedIssueComments}
                  isSavingIssue={isSavingIssue}
                  isWorking={isWorking}
                  issue={selectedIssue}
                  issueDraft={issueDraft}
                  issueEditorError={issueEditorError}
                  issueWorkspaceSidebar={
                    selectedIssueWorkspace ? (
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
                        isWorking={isWorking}
                        selectedDiff={selectedDiff}
                        selectedFilePath={selectedFilePath}
                        workspace={selectedIssueWorkspace}
                        workspaceSidebarTab={workspaceSidebarTab}
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
                      />
                    ) : null
                  }
                  isEditingIssue={isEditingIssue}
                  linkedApprovals={linkedIssueApprovals}
                  newCommentBody={newIssueCommentBody}
                  newCommentTargetAgentId={newIssueCommentTargetAgentId}
                  onAddComment={() => void handleAddIssueComment(selectedIssue)}
                  onAddAttachment={() =>
                    void handleAddIssueAttachment(selectedIssue)
                  }
                  onBack={() => handleShowIssuesList()}
                  onBeginEditing={() => beginEditingIssue(selectedIssue)}
                  onCancelEditing={() => discardIssueEdits(selectedIssue)}
                  onCommitIssuePatch={(patch) =>
                    void handlePersistIssuePatch(selectedIssue, patch)
                  }
                  onHideIssue={() => void handleHideIssue(selectedIssue)}
                  onIssueDraftChange={(patch) =>
                    setIssueDraft((current) => ({
                      ...current,
                      ...patch,
                    }))
                  }
                  onLinkedApprovalSelect={(approvalId) => {
                    setSelectedApprovalId(approvalId);
                    handleSelectScreen("approvals");
                  }}
                  onOpenRunDetail={handleOpenIssueLinkedRun}
                  onNewCommentBodyChange={setNewIssueCommentBody}
                  onCommentTargetAgentChange={setNewIssueCommentTargetAgentId}
                  onRevealAttachment={(attachment) =>
                    void handleRevealIssueAttachment(attachment)
                  }
                  onParentIssueSelect={(parentIssueId) =>
                    setIssueDraft((current) => ({
                      ...current,
                      parentId: parentIssueId,
                    }))
                  }
                  onProjectSelect={(projectId) =>
                    setIssueDraft((current) => ({
                      ...current,
                      projectId,
                    }))
                  }
                  onSave={() => void handleSaveIssueEdits(selectedIssue)}
                  parentIssueLabel={(parentIssueId) =>
                    issueParentLabel(boardIssues, parentIssueId)
                  }
                  statusLabel={issueStatusLabel}
                  priorityLabel={humanizeIssueValue}
                  projects={companySnapshot?.projects ?? []}
                  projectLabel={(projectId) =>
                    issueProjectLabel(
                      companySnapshot?.projects ?? [],
                      projectId
                    )
                  }
                  agents={companySnapshot?.agents ?? []}
                  selectableParentIssues={selectableParentIssues}
                  subissues={issueSubissues}
                  workspaceTargetErrorMessage={
                    issueDetailWorktreeState.errorMessage
                  }
                  workspaceTargetLoading={issueDetailWorktreeState.isLoading}
                  workspaceTargetWorktrees={issueDetailWorktreeState.worktrees}
                />
              ) : (
                <IssuesListView
                  activeTab={selectedIssuesListTab}
                  emptyTitle={`No issues in ${issuesListTabTitle(selectedIssuesListTab).toLowerCase()}`}
                  issues={visibleIssues}
                  onSelectIssue={(issueId) => void handleSelectIssue(issueId)}
                  onTabChange={setSelectedIssuesListTab}
                  selectedIssueId={selectedIssueId}
                  summaryText={issueSummaryText}
                />
              )
            ) : null}

            {selectedScreen === "approvals" ? (
              <ApprovalsRouteView
                approvals={boardApprovals}
                currentApproval={selectedApproval}
                isWorking={isWorking}
                onApprove={(approvalId) =>
                  void handleApproveApproval(approvalId)
                }
                onSelectApproval={setSelectedApprovalId}
              />
            ) : null}

            {selectedScreen === "projects" ? (
              <ProjectsRouteView
                currentProject={selectedProject}
                currentProjectIssueCount={
                  selectedProject
                    ? boardIssues.filter(
                        (issue) => issue.project_id === selectedProject.id
                      ).length
                    : 0
                }
                currentProjectWorkspaceCount={
                  selectedProject
                    ? companyWorkspaces.filter(
                        (workspace) =>
                          workspace.project_id === selectedProject.id
                      ).length
                    : 0
                }
                goals={boardGoals}
                onDeleteProject={handleDeleteProject}
                onOpenCreateProject={handleOpenCreateProjectDialog}
                onSelectProject={setSelectedProjectId}
                projects={boardProjects}
              />
            ) : null}

            {selectedScreen === "goals" ? (
              <GoalsRouteView
                agents={companySnapshot?.agents ?? []}
                currentGoal={selectedGoal}
                goals={boardGoals}
                onSelectGoal={setSelectedGoalId}
                projects={boardProjects}
              />
            ) : null}

            {selectedScreen === "companySettings" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <DashboardBreadcrumbs
                    items={[{ label: "Company settings" }]}
                  />
                  <span className="route-kicker">Company settings</span>
                  <h1>{selectedCompany?.name ?? "Company settings"}</h1>
                  <p>
                    Board-specific company details and policies live here.
                    Device and app settings stay behind the rail gear.
                  </p>
                </div>

                <div className="surface-grid single">
                  <section className="surface-panel wide">
                    <h3>Company profile</h3>
                    <p>
                      This route follows the board/company admin surface rather
                      than the desktop preferences shell.
                    </p>
                    <div className="surface-list">
                      <DetailRow
                        label="Company Name"
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
                        label="Issue Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                    </div>
                  </section>

                  <section className="surface-panel wide">
                    <h3>Board policy</h3>
                    <div className="summary-grid">
                      <SummaryPill
                        label="Issue Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                      <SummaryPill
                        label="Monthly Budget"
                        value={formatCents(
                          selectedCompany?.budget_monthly_cents
                        )}
                      />
                      <SummaryPill
                        label="Monthly Spend"
                        value={formatCents(
                          selectedCompany?.spent_monthly_cents
                        )}
                      />
                    </div>

                    <div className="surface-list">
                      <DetailRow
                        label="Require Agent Approval"
                        value={
                          selectedCompany?.require_board_approval_for_new_agents
                            ? "Enabled"
                            : "Disabled"
                        }
                      />
                      <DetailRow
                        label="Status"
                        value={String(selectedCompany?.status ?? "active")}
                      />
                      <DetailRow
                        label="CEO"
                        value={
                          selectedCompanyCeo?.name ??
                          selectedCompany?.ceo_agent_id ??
                          "Unassigned"
                        }
                      />
                      <DetailRow
                        label="Issue Counter"
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
                approvals={boardApprovals}
                issueCommentsByIssueId={issueCommentsByIssueId}
                issues={activityVisibleIssues}
                onOpenApproval={(approvalId) => {
                  setSelectedApprovalId(approvalId);
                  handleSelectScreen("approvals");
                }}
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

      {layout === "workspace" ? (
        <div className="workspace-shell">
          <aside className="workspace-sidebar">
            <div className="workspace-sidebar-header">
              <div>
                <h2>Worktrees</h2>
                <span>{selectedCompany?.name ?? "Company"} board</span>
              </div>
              <button
                className="icon-button"
                onClick={() => void refreshBoardData()}
                type="button"
              >
                ↻
              </button>
            </div>

            {companyWorkspaces.length ? (
              <div className="workspace-session-list workspace-board-list">
                {companyWorkspaces.map((workspace) => (
                  <WorkspaceBoardItem
                    active={workspace.id === selectedBoardWorkspaceId}
                    key={workspace.id}
                    onClick={() => handleSelectBoardWorkspace(workspace)}
                    workspace={workspace}
                  />
                ))}
              </div>
            ) : (
              <div className="workspace-empty-state">
                <h3>No active worktrees</h3>
                <p>
                  Worktrees appear automatically when an assigned agent starts
                  an issue.
                </p>
              </div>
            )}
          </aside>

          <main className="workspace-center">
            {selectedBoardWorkspace ? (
              <>
                <section className="workspace-summary-banner">
                  <div>
                    <span className="route-kicker">
                      {selectedBoardWorkspace.issue_identifier ?? "Worktree"}
                    </span>
                    <h1>
                      {selectedBoardWorkspace.issue_title ??
                        selectedBoardWorkspace.title}
                    </h1>
                    <p>
                      {[
                        selectedBoardWorkspace.project_name,
                        selectedBoardWorkspace.agent_name,
                        selectedBoardWorkspace.workspace_branch,
                      ]
                        .filter(Boolean)
                        .join(" · ") || "Issue-owned coding session"}
                    </p>
                  </div>
                  <SummaryPill
                    label="Status"
                    value={selectedBoardWorkspace.workspace_status ?? "active"}
                  />
                </section>

                <div className="workspace-center-header">
                  <div className="workspace-tab-strip">
                    <WorkspaceCenterTabButton
                      active={workspaceCenterTab === "conversation"}
                      label={activeWorkspaceTitle ?? "New conversation"}
                      onClick={() => setWorkspaceCenterTab("conversation")}
                    />
                    <WorkspaceCenterTabButton
                      active={workspaceCenterTab === "terminal"}
                      label="Terminal"
                      onClick={() => setWorkspaceCenterTab("terminal")}
                    />
                    {selectedFilePath ? (
                      <WorkspaceCenterTabButton
                        active={workspaceCenterTab === "preview"}
                        label={previewTabLabel}
                        onClick={() => setWorkspaceCenterTab("preview")}
                      />
                    ) : null}
                  </div>
                  <div className="workspace-header-actions">
                    <SummaryPill
                      label={activeWorkspaceProviderLabel}
                      value={stringifyStatus(claudeStatusState)}
                    />
                    <SummaryPill
                      label="Terminal"
                      value={stringifyStatus(terminalStatusState)}
                    />
                  </div>
                </div>

                {statusMessage ? (
                  <div className="status-banner">{statusMessage}</div>
                ) : null}

                {workspaceCenterTab === "conversation" ? (
                  <section className="workspace-panel workspace-chat-panel">
                    <div className="workspace-panel-header">
                      <div>
                        <span className="route-kicker">Conversation</span>
                        <h1>{selectedRepository?.name ?? "Session"}</h1>
                      </div>
                      <div className="workspace-header-actions">
                        {selectedSessionId ? (
                          <button
                            className="secondary-button"
                            onClick={() => void agentStop(selectedSessionId)}
                            type="button"
                          >
                            Stop {activeWorkspaceProviderLabel}
                          </button>
                        ) : null}
                        {selectedBoardWorkspace.workspace_repo_path ? (
                          <button
                            className="secondary-button"
                            onClick={() =>
                              void desktopRevealInFinder(
                                selectedBoardWorkspace.workspace_repo_path ?? ""
                              )
                            }
                            type="button"
                          >
                            Reveal repo
                          </button>
                        ) : null}
                      </div>
                    </div>

                    <div className="message-timeline">
                      {activeSessionMessages.map((message) => (
                        <article className="message-card" key={message.id}>
                          <header>
                            <strong>#{message.sequence_number}</strong>
                            <span>{describeMessageKind(message.content)}</span>
                          </header>
                          <pre>
                            {renderMessageContent(
                              message.content,
                              settings.show_raw_message_json
                            )}
                          </pre>
                        </article>
                      ))}
                    </div>

                    <form className="composer" onSubmit={handleRunAgent}>
                      <textarea
                        onChange={(event) => setPrompt(event.target.value)}
                        placeholder={`Send a prompt to ${activeWorkspaceProviderLabel} for the selected session`}
                        value={prompt}
                      />
                      <button
                        className="primary-button"
                        disabled={isWorking}
                        type="submit"
                      >
                        Send prompt
                      </button>
                    </form>
                  </section>
                ) : null}

                {workspaceCenterTab === "terminal" ? (
                  <section className="workspace-panel workspace-chat-panel">
                    <div className="workspace-panel-header">
                      <h3>Terminal</h3>
                      <button
                        className="secondary-button"
                        onClick={() => {
                          if (selectedSessionId) {
                            void terminalStop(selectedSessionId);
                          }
                        }}
                        type="button"
                      >
                        Stop
                      </button>
                    </div>
                    <div
                      className="terminal-frame"
                      ref={terminalContainerRef}
                    />
                    <form
                      className="workspace-terminal-form"
                      onSubmit={handleRunTerminal}
                    >
                      <input
                        onChange={(event) =>
                          setTerminalCommand(event.target.value)
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

                {workspaceCenterTab === "preview" ? (
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
                <h3>Select a worktree</h3>
                <p>
                  Issue-owned coding sessions appear here. Repo-root targets run
                  directly in the project checkout.
                </p>
              </section>
            )}
          </main>

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
            isWorking={isWorking}
            selectedDiff={selectedDiff}
            selectedFilePath={selectedFilePath}
            workspace={selectedBoardWorkspace}
            workspaceSidebarTab={workspaceSidebarTab}
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
          />
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
                            settings.preferred_view
                          )}
                        />
                      </div>
                      <div className="settings-shadcn-actions">
                        <button className="settings-shadcn-button" type="submit">
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

      {isCreateProjectDialogOpen ? (
        <CreateProjectDialogView
          derivedProjectName={projectDialogDerivedName}
          errorMessage={projectDialogError}
          goals={boardGoals}
          isSaving={isProjectDialogSaving}
          repoPath={projectDialogRepoPath}
          selectedGoalId={projectDialogGoalId}
          selectedStatus={projectDialogStatus}
          targetDate={projectDialogTargetDate}
          onChooseFolder={() => void handleChooseProjectFolder()}
          onClose={handleCloseCreateProjectDialog}
          onCreate={() => void handleCreateProjectFromDialog()}
          onGoalChange={setProjectDialogGoalId}
          onStatusChange={setProjectDialogStatus}
          onTargetDateChange={setProjectDialogTargetDate}
        />
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
          agents={companySnapshot?.agents ?? []}
          companyPrefix={selectedCompany?.issue_prefix ?? "ISS"}
          errorMessage={issueDialogError}
          isSaving={isIssueDialogSaving}
          onAssigneeChange={setIssueDialogAssigneeAgentId}
          onAddAttachment={() => void handleAddIssueDialogAttachment()}
          onClose={handleCloseCreateIssueDialog}
          onCreate={() => void handleCreateIssueFromDialog()}
          onDescriptionChange={setIssueDialogDescription}
          onPriorityChange={setIssueDialogPriority}
          onProjectChange={handleIssueDialogProjectChange}
          onRemoveAttachment={handleRemoveIssueDialogAttachment}
          onStatusChange={setIssueDialogStatus}
          onTitleChange={setIssueDialogTitle}
          onWorkspaceTargetChange={handleIssueDialogWorkspaceTargetChange}
          attachments={issueDialogAttachments}
          priorities={mergeIssueOptions(
            ["low", "medium", "high", "urgent"],
            issueDialogPriority
          )}
          projects={boardProjects}
          selectedAssigneeAgentId={issueDialogAssigneeAgentId}
          selectedPriority={issueDialogPriority}
          selectedProjectId={issueDialogProjectId}
          selectedStatus={issueDialogStatus}
          statuses={mergeIssueOptions(canonicalIssueStatuses, issueDialogStatus)}
          selectedWorkspaceTargetValue={issueWorkspaceTargetSelectValue(
            issueDialogWorkspaceTargetMode,
            issueDialogWorkspaceWorktreePath
          )}
          title={issueDialogTitle}
          description={issueDialogDescription}
          workspaceTargetErrorMessage={issueDialogWorktreeState.errorMessage}
          workspaceTargetLoading={issueDialogWorktreeState.isLoading}
          workspaceTargetWorktrees={issueDialogWorktreeState.worktrees}
        />
      ) : null}
    </div>
  );
}

function MetricCard({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <section className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </section>
  );
}

function SummaryPill({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <div className="summary-pill">
      <span>{label}</span>
      <strong>{value}</strong>
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
    [agents]
  );
  const hierarchy = useMemo(
    () => buildOrgHierarchy(agents, projects, ceoAgentId),
    [agents, projects, ceoAgentId]
  );
  const flattenedHierarchy = useMemo(() => flattenOrgHierarchy(hierarchy), [hierarchy]);
  const managersCount = flattenedHierarchy.filter(
    (node) => node.reports.length > 0
  ).length;
  const ceo = useMemo(
    () => findCompanyCeo(agents, ceoAgentId),
    [agents, ceoAgentId]
  );

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: "Org" }]} />
        <span className="route-kicker">Agent org</span>
        <h1>{company?.name ? `${company.name} agent org` : "Agent org"}</h1>
        <p>
          See the reporting hierarchy for agents across the company and jump
          into any agent to inspect its configuration and runs.
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
                This chart shows how agents report across the company. Select
                any node to jump into that agent&apos;s configuration and runs.
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
                node.agent.status
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
    patch: Partial<AgentConfigEnvVarDraft>
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
    selectedAgent?.status ?? "idle"
  ).toLowerCase();

  return (
    <section className="route-scroll agent-detail-route">
      <div className="agent-detail-layout">
        <DashboardBreadcrumbs
          items={
            selectedAgent
              ? [
                  { label: "Agents" },
                  { label: selectedAgent.name || "Agent" },
                ]
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
                      selectedAgent.status
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
              className="agents-tab-strip"
              role="tablist"
              aria-label="Agent views"
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
                draft={configurationDraft}
                errorMessage={configurationError}
                dependencyCheck={dependencyCheck}
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
            No agents are available for this company yet.
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
        <SummaryPill label="Company" value={companyName} />
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
    patch: Partial<AgentConfigEnvVarDraft>
  ) => void;
  onRemoveEnvVar: (envId: string) => void;
  onSave: () => void;
}) {
  const canSave = !isSaving && draft.name.trim().length > 0;
  const provider = detectAgentCliProvider(draft.command, draft.model);
  const adapterTypeOptions = mergeIssueOptions(["process"], draft.adapterType);
  const commandOptions = buildAgentCommandOptions(
    dependencyCheck,
    draft.command
  );
  const modelOptions = buildAgentModelOptions(draft, dependencyCheck);
  const thinkingEffortOptions = mergeIssueOptions(
    ["auto", "low", "medium", "high"],
    draft.thinkingEffort
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
        fullWidth ? "issue-dialog-field agent-config-field-full" : "issue-dialog-field"
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
        <AgentConfigInlineButton onClick={onChoose}>Choose</AgentConfigInlineButton>
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

      {!selectedAgent ? (
        <p>Select an agent to review its runs.</p>
      ) : (
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
                        selectedRun.invocation_source
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
                      selectedRun.invocation_source
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
                      selectedRun.started_at ?? selectedRun.created_at
                    )}
                  />
                  <DetailRow
                    label="Finished"
                    value={formatIssueDate(selectedRun.finished_at)}
                  />
                  <DetailRow
                    label="Trigger detail"
                    value={agentRunTriggerDetailLabel(
                      selectedRun.trigger_detail
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
                          {event.message ? <p>{event.message}</p> : null}
                          {event.payload !== undefined &&
                          event.payload !== null ? (
                            <pre className="agent-run-json-block">
                              {formatJsonBlock(event.payload)}
                            </pre>
                          ) : null}
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
      <button className="agent-page-header-action-chip" onClick={onClick} type="button">
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
}: {
  active: boolean;
  icon?: CompanyContextMenuIconKey | null;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      className={
        active ? "board-sidebar-button active" : "board-sidebar-button"
      }
      onClick={onClick}
      type="button"
    >
      {icon ? (
        <span aria-hidden="true" className="board-sidebar-button-icon">
          <CompanyContextMenuIcon
            className="board-sidebar-icon"
            icon={icon}
          />
        </span>
      ) : null}
      <span>{label}</span>
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
    0
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
    event: ReactKeyboardEvent<HTMLButtonElement>
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
    index: number
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

function DashboardCanvasRouteView({
  agents,
  canvasBounds,
  canvasOffset,
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
  issueRunCardUpdatesByIssueId,
  onWheel,
  projectColumns,
  selectedProjectId,
  viewportRef,
}: {
  agents: AgentRecord[];
  canvasBounds: { height: number; width: number };
  canvasOffset: DashboardCanvasOffset;
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
    draft: DashboardProjectViewDraft
  ) => Promise<void>;
  onProjectGroupingChange: (
    projectId: string,
    viewId: string,
    grouping: DashboardProjectGrouping
  ) => void;
  issueRunCardUpdatesByIssueId: Record<string, IssueRunCardUpdateRecord>;
  onWheel: (event: WheelEvent<HTMLDivElement>) => void;
  projectColumns: DashboardProjectColumnLayout[];
  selectedProjectId: string | null;
  viewportRef: RefObject<HTMLDivElement | null>;
}) {
  const [creatingProjectId, setCreatingProjectId] = useState<string | null>(
    null
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
    projectColumn: DashboardProjectColumnLayout
  ) => {
    setCreatingProjectId(projectColumn.project.id);
    setNewProjectViewName(nextDashboardProjectViewName(projectColumn.boards));
    setNewProjectViewGrouping(
      nextDashboardProjectViewGrouping(projectColumn.boards)
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
        error instanceof Error ? error.message : String(error)
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
              height: canvasBounds.height,
              transform: `translate(${canvasOffset.x}px, ${canvasOffset.y}px)`,
              width: canvasBounds.width,
            }}
          >
            {projectColumns.map((projectColumn) => {
              const isSelected = selectedProjectId === projectColumn.project.id;
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
                        <div>
                          <span className="project-kanban-view-label">
                            {projectBoard.viewName}
                          </span>
                          <h2>
                            {projectBoard.project.name ??
                              projectBoard.project.title ??
                              "Untitled project"}
                          </h2>
                          <p>
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
                                  nextValue
                                )
                              }
                              options={dashboardProjectGroupingSelectOptions}
                              value={projectBoard.grouping}
                            />
                          </label>

                          <div className="project-kanban-board-meta">
                            <span>{projectBoard.issueCount} issues</span>
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
                                className="project-kanban-column-create-icon"
                                aria-hidden="true"
                              >
                                +
                              </span>
                              <span className="project-kanban-column-create-copy">
                                <strong>New issue</strong>
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
                                        ? issueRunCardUpdateSummary(cardUpdate)
                                        : null;

                                      return (
                                        <button
                                          className="project-kanban-card"
                                          data-priority={normalizeBoardIssueValue(
                                            issue.priority
                                          )}
                                          key={issue.id}
                                          onClick={() => onOpenIssue(issue.id)}
                                          type="button"
                                        >
                                          <strong>
                                            {issue.identifier ?? issue.title}
                                          </strong>
                                          <p>{issue.title}</p>
                                          {cardUpdate ? (
                                            <div className="project-kanban-card-update">
                                              <span
                                                className={`agent-run-status-badge ${agentRunStatusTone(cardUpdate.run_status)} project-kanban-card-update-status`}
                                              >
                                                {agentRunStatusLabel(
                                                  cardUpdate.run_status
                                                )}
                                              </span>
                                              <span
                                                className="project-kanban-card-update-copy"
                                                title={cardUpdateSummary ?? undefined}
                                              >
                                                {cardUpdateSummary}
                                              </span>
                                            </div>
                                          ) : null}
                                          <div className="project-kanban-card-meta">
                                            {projectBoardCardMeta(
                                              projectBoard.grouping,
                                              issue,
                                              agents
                                            ).map((meta, index) => (
                                              <span key={`${issue.id}-${index}`}>
                                                {meta}
                                              </span>
                                            ))}
                                          </div>
                                        </button>
                                      );
                                    })}
                                    {createIssueCard}
                                  </>
                                ) : (
                                  <div className="project-kanban-column-empty">
                                    <span>No issues yet</span>
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
                                void handleSaveProjectView(projectColumn.project.id)
                              }
                              type="button"
                            >
                              {isSavingProjectView ? "Saving..." : "Save view"}
                            </button>
                          </div>
                        </div>
                      </div>
                    ) : (
                      <button
                        className="project-kanban-add-button"
                        onClick={() => handleOpenProjectViewComposer(projectColumn)}
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
      ) : (
        <div className="dashboard-canvas-empty-wrap">
          <div className="dashboard-canvas-empty-card">
            <div className="dashboard-canvas-empty-icon" aria-hidden="true">
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
    </section>
  );
}

function StatsRouteView({
  bootstrap,
  company,
  dependencyCheck,
  onCheckDependencies,
  onOpenWorkspace,
  repositoriesCount,
  snapshot,
}: {
  bootstrap: DesktopBootstrapStatus;
  company: Company | null;
  dependencyCheck: RuntimeCapabilities | null;
  onCheckDependencies: () => void;
  onOpenWorkspace: (workspace: WorkspaceRecord) => void;
  repositoriesCount: number;
  snapshot: CompanySnapshot | null;
}) {
  return (
    <section className="route-scroll">
      <div className="route-header">
        <DashboardBreadcrumbs items={[{ label: "Stats" }]} />
        <span className="route-kicker">Stats</span>
        <h1>{company?.name ?? "Unbound"}</h1>
        <p>
          {company?.description ??
            "A quick board snapshot across issues, agents, approvals, projects, and active work."}
        </p>
      </div>

      <div className="metric-grid">
        <MetricCard label="Issues" value={snapshot?.issues.length ?? 0} />
        <MetricCard label="Projects" value={snapshot?.projects.length ?? 0} />
        <MetricCard label="Agents" value={snapshot?.agents.length ?? 0} />
        <MetricCard label="Approvals" value={snapshot?.approvals.length ?? 0} />
        <MetricCard
          label="Worktrees"
          value={snapshot?.workspaces.length ?? 0}
        />
        <MetricCard label="Repositories" value={repositoriesCount} />
      </div>

      <div className="surface-grid">
        <section className="surface-panel wide">
          <div className="surface-header">
            <h3>Production boundary preserved</h3>
            <button
              className="secondary-button"
              onClick={onCheckDependencies}
              type="button"
            >
              Check dependencies
            </button>
          </div>
          <p>
            `unbound-daemon` stays separately installed and version-checked. The
            desktop app only connects over the existing local socket boundary.
          </p>
          <div className="summary-grid">
            <SummaryPill
              label="Daemon"
              value={bootstrap.daemon_info?.daemon_version ?? "unknown"}
            />
            <SummaryPill
              label="Protocol"
              value={bootstrap.daemon_info?.protocol_version ?? "unknown"}
            />
            <SummaryPill label="App" value={bootstrap.expected_app_version} />
          </div>
          {dependencyCheck ? (
            <div className="surface-list dense">
              <DependencyToolRow
                capability={dependencyCheck.cli.claude}
                label="Claude"
              />
              <DependencyToolRow
                capability={dependencyCheck.cli.codex}
                label="Codex"
              />
              <DependencyToolRow
                capability={dependencyCheck.cli.gh}
                label="GitHub CLI"
              />
              <DependencyToolRow
                capability={dependencyCheck.cli.ollama}
                label="Ollama"
              />
            </div>
          ) : (
            <p>
              Check dependencies to see which local coding CLIs are available
              and which model families the daemon can offer.
            </p>
          )}
        </section>

        <section className="surface-panel">
          <h3>Projects</h3>
          {(snapshot?.projects ?? []).length ? (
            <div className="surface-list">
              {(snapshot?.projects ?? []).slice(0, 5).map((project) => (
                <div className="surface-list-row" key={project.id}>
                  <strong>
                    {project.name ?? project.title ?? "Untitled project"}
                  </strong>
                  <span>
                    {project.primary_workspace?.cwd ??
                      project.status ??
                      "Missing repo path"}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="surface-empty-copy">
              Projects define the main repo path for worktrees.
            </p>
          )}
        </section>

        <section className="surface-panel">
          <h3>Agents</h3>
          <div className="surface-list">
            {(snapshot?.agents ?? []).map((agent) => (
              <div className="surface-list-row" key={agent.id}>
                <strong>{agent.name}</strong>
                <span>{agent.title ?? agent.role ?? "Agent"}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="surface-panel">
          <h3>Active Worktrees</h3>
          <div className="surface-list">
            {(snapshot?.workspaces ?? []).map((workspace) => (
              <button
                className="file-list-button"
                key={workspace.id}
                onClick={() => onOpenWorkspace(workspace)}
                type="button"
              >
                <strong>{workspace.issue_identifier ?? workspace.title}</strong>
                <span>
                  {[
                    workspace.issue_title,
                    workspace.project_name,
                    workspace.agent_name,
                  ]
                    .filter(Boolean)
                    .join(" · ") ||
                    workspace.workspace_status ||
                    "worktree"}
                </span>
              </button>
            ))}
          </div>
        </section>
      </div>
    </section>
  );
}

function DependencyToolRow({
  capability,
  label,
}: {
  capability: RuntimeCapabilities["cli"][keyof RuntimeCapabilities["cli"]];
  label: string;
}) {
  return (
    <div className="surface-list-row">
      <div>
        <strong>{label}</strong>
        <span>
          {capability.installed
            ? capability.path ?? "Installed and ready"
            : "Not detected in PATH"}
        </span>
      </div>
      <span>
        {capability.installed && capability.models?.length
          ? `${capability.models.length} ${capability.models.length === 1 ? "model" : "models"}`
          : capability.installed
            ? "Ready"
            : "Missing"}
      </span>
    </div>
  );
}

function IssuesListView({
  activeTab,
  issues,
  selectedIssueId,
  summaryText,
  emptyTitle,
  onTabChange,
  onSelectIssue,
}: {
  activeTab: IssuesListTab;
  issues: IssueRecord[];
  selectedIssueId: string | null;
  summaryText: string;
  emptyTitle: string;
  onTabChange: (tab: IssuesListTab) => void;
  onSelectIssue: (issueId: string) => void;
}) {
  return (
    <section className="issues-route">
      <div className="issues-route-header">
        <div className="issues-route-header-inner">
          <DashboardBreadcrumbs items={[{ label: "Issues" }]} />
        </div>
      </div>

      <div className="issues-tab-bar">
        <div className="issues-tab-bar-inner">
          {(["new", "all"] as const).map((tab) => (
            <button
              className={
                activeTab === tab
                  ? "issues-tab-button active"
                  : "issues-tab-button"
              }
              key={tab}
              onClick={() => onTabChange(tab)}
              type="button"
            >
              {issuesListTabTitle(tab)}
            </button>
          ))}
        </div>
      </div>

      <div className="issues-summary-bar">
        <div className="issues-summary-bar-inner">
          <span>{summaryText}</span>
        </div>
      </div>

      <div className="issues-list-scroll">
        {issues.length ? (
          <div className="issues-list">
            {issues.map((issue) => {
              const isSelected = selectedIssueId === issue.id;
              const normalizedIssueStatus = normalizeBoardIssueValue(
                issue.status
              );
              return (
                <button
                  className={
                    isSelected ? "issues-list-row active" : "issues-list-row"
                  }
                  key={issue.id}
                  onClick={() => onSelectIssue(issue.id)}
                  type="button"
                >
                  <span
                    className="issues-list-row-main"
                    style={{
                      paddingLeft: `${20 + issue.request_depth * 12}px`,
                    }}
                  >
                    <span
                      aria-hidden="true"
                      className="issues-list-row-status"
                      data-status={normalizedIssueStatus}
                    >
                      <IssueListStatusIcon status={normalizedIssueStatus} />
                    </span>
                    {issue.identifier ? (
                      <span className="issues-list-row-identifier">
                        {issue.identifier}
                      </span>
                    ) : null}
                    <span className="issues-list-row-title">{issue.title}</span>
                  </span>
                  <span className="issues-list-row-timestamp">
                    {formatCompactIssueTimestamp(issue.updated_at)}
                  </span>
                </button>
              );
            })}
          </div>
        ) : (
          <div className="issues-empty-state">
            <h2>{emptyTitle}</h2>
            <p>
              Issues own worktrees. Create one from the sidebar to start agent
              work.
            </p>
          </div>
        )}
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
  availablePriorityOptions,
  projects,
  agents,
  selectableParentIssues,
  linkedApprovals,
  subissues,
  comments,
  issueEditorError,
  issueWorkspaceSidebar,
  newCommentBody,
  newCommentTargetAgentId,
  onBack,
  onCommitIssuePatch,
  onHideIssue,
  onIssueDraftChange,
  onLinkedApprovalSelect,
  onOpenRunDetail,
  onNewCommentBodyChange,
  onCommentTargetAgentChange,
  onAddComment,
  onAddAttachment,
  onRevealAttachment,
  projectLabel,
  assigneeLabel,
  parentIssueLabel,
  statusLabel,
  priorityLabel,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  isEditingIssue: boolean;
  isSavingIssue: boolean;
  isWorking: boolean;
  attachments: IssueAttachmentRecord[];
  availableStatusOptions: string[];
  availablePriorityOptions: string[];
  projects: ProjectRecord[];
  agents: AgentRecord[];
  selectableParentIssues: IssueRecord[];
  linkedApprovals: ApprovalRecord[];
  subissues: IssueRecord[];
  comments: IssueCommentRecord[];
  issueEditorError: string | null;
  issueWorkspaceSidebar?: ReactNode;
  newCommentBody: string;
  newCommentTargetAgentId: string;
  onBack: () => void;
  onBeginEditing: () => void;
  onCancelEditing: () => void;
  onCommitIssuePatch: (patch: Partial<IssueEditDraft>) => void;
  onHideIssue: () => void;
  onSave: () => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  onProjectSelect: (projectId: string) => void;
  onParentIssueSelect: (parentIssueId: string) => void;
  onLinkedApprovalSelect: (approvalId: string) => void;
  onOpenRunDetail: (run: AgentRunRecord) => void;
  onNewCommentBodyChange: (value: string) => void;
  onCommentTargetAgentChange: (value: string) => void;
  onAddComment: () => void;
  onAddAttachment: () => void;
  onRevealAttachment: (attachment: IssueAttachmentRecord) => void;
  projectLabel: (projectId?: string | null) => string;
  assigneeLabel: (assigneeAgentId?: string | null) => string;
  parentIssueLabel: (parentIssueId?: string | null) => string;
  statusLabel: (value: string) => string;
  priorityLabel: (value: string) => string;
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
    agents
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
    issueDraft.workspaceWorktreePath
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
        selectedWorkspaceTargetValue
    )
      ? {
          name:
            issueDraft.workspaceWorktreeName ||
            fileName(issueDraft.workspaceWorktreePath),
          path: issueDraft.workspaceWorktreePath,
        }
      : null;

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
          error instanceof Error ? error.message : "Could not load linked runs."
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
          { label: "Issues", onClick: onBack },
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
                  aria-label="Issue actions"
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
                      Hide this issue
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
                placeholder="Issue title"
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
                placeholder="Add context, scope, acceptance criteria, or a short brief for the assignee."
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
              className="issues-detail-tabs"
              role="tablist"
              aria-label="Issue details sections"
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
                aria-selected={activeTab === "subissues"}
                className={
                  activeTab === "subissues"
                    ? "issues-detail-tab-button active"
                    : "issues-detail-tab-button"
                }
                onClick={() => setActiveTab("subissues")}
                role="tab"
                type="button"
              >
                Sub-issues
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
                          in new agent runs for this issue.
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
                        <h3>Comments</h3>
                      </div>
                    </div>

                    {comments.length ? (
                      <div className="issues-comment-list">
                        {comments.map((comment) => (
                          <article
                            className="issues-comment-card"
                            key={comment.id}
                          >
                            {comment.target_agent_id ? (
                              <div className="issues-comment-card-target">
                                Tagged{" "}
                                {issueAssigneeLabel(
                                  agents,
                                  comment.target_agent_id
                                )}
                              </div>
                            ) : null}
                            <p>{comment.body}</p>
                            <span>{formatIssueDate(comment.created_at)}</span>
                          </article>
                        ))}
                      </div>
                    ) : (
                      <p className="issues-detail-copy muted">
                        No comments yet.
                      </p>
                    )}

                    <div className="issues-comment-composer">
                      <textarea
                        onChange={(event) =>
                          onNewCommentBodyChange(event.target.value)
                        }
                        placeholder="Leave a comment..."
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
                              <span>Re-open</span>
                            </label>
                          ) : null}
                          <div className="issue-dialog-select-shell issues-comment-target-select-shell">
                            <select
                              className="issue-dialog-select issues-comment-target-select"
                              onChange={(event) =>
                                onCommentTargetAgentChange(event.target.value)
                              }
                              value={newCommentTargetAgentId}
                            >
                              <option value="">No tagged agent</option>
                              {agents.map((agent) => (
                                <option key={agent.id} value={agent.id}>
                                  {agent.name}
                                </option>
                              ))}
                            </select>
                            <span className="issue-dialog-select-arrow">▼</span>
                          </div>
                          <button
                            className="secondary-button issues-comment-submit-button"
                            disabled={isWorking || !newCommentBody.trim()}
                            onClick={onAddComment}
                            type="button"
                          >
                            Comment
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
                                {agentInitials(
                                  issueAssigneeLabel(agents, run.agent_id)
                                )}
                              </span>
                              <strong>
                                {issueAssigneeLabel(agents, run.agent_id)}
                              </strong>
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
                  ) : !isLoadingLinkedRuns && !linkedRunsError ? (
                    <p className="issues-detail-copy muted">
                      No runs linked to this issue yet.
                    </p>
                  ) : null}
                </>
              ) : null}

              {activeTab === "subissues" ? (
                subissues.length ? (
                  <div className="surface-list dense">
                    {subissues.map((child) => (
                      <div
                        className="surface-list-row issues-supporting-row"
                        key={child.id}
                      >
                        <strong>{child.identifier ?? child.title}</strong>
                        <span className="workspace-status-pill">
                          {statusLabel(child.status)}
                        </span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="issues-detail-copy muted">No sub-issues yet.</p>
                )
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
              aria-label="Issue properties"
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
                    tone={normalizeBoardIssueValue(issueDraft.status)}
                    onChange={(value) =>
                      commitPropertyPatch({
                        status: value,
                      })
                    }
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
                    label="Priority"
                    tone={normalizeBoardIssueValue(issueDraft.priority)}
                    onChange={(value) =>
                      commitPropertyPatch({
                        priority: value,
                      })
                    }
                    value={issueDraft.priority}
                  >
                    {availablePriorityOptions.map((priority) => (
                      <option key={priority} value={priority}>
                        {priorityLabel(priority)}
                      </option>
                    ))}
                  </IssuePropertySelectRow>

                  <IssuePropertyStaticRow
                    label="Labels"
                    tone="neutral"
                    value="No labels"
                  />

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Assignee"
                    tone="agent"
                    onChange={(value) =>
                      commitPropertyPatch({
                        assigneeAgentId: value,
                      })
                    }
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
                    tone="project"
                    onChange={(value) =>
                      commitPropertyPatch({
                        projectId: value,
                        workspaceTargetMode: "main",
                        workspaceWorktreePath: "",
                        workspaceWorktreeBranch: "",
                        workspaceWorktreeName: "",
                      })
                    }
                    value={issueDraft.projectId}
                  >
                    <option value="">No project</option>
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
                    tone="neutral"
                    onChange={(value) =>
                      commitPropertyPatch(
                        issueWorkspaceDraftPatchFromSelection(
                          value,
                          workspaceTargetWorktrees,
                          issueDraft
                        )
                      )
                    }
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
                          fallbackSelectedWorktree.path
                        )}
                      >
                        {fallbackSelectedWorktree.name}
                      </option>
                    ) : null}
                  </IssuePropertySelectRow>

                  <IssuePropertySelectRow
                    disabled={isSavingIssue}
                    label="Parent"
                    tone="neutral"
                    onChange={(value) =>
                      commitPropertyPatch({
                        parentId: value,
                      })
                    }
                    value={issueDraft.parentId}
                  >
                    <option value="">No parent issue</option>
                    {selectableParentIssues.map((parentIssue) => (
                      <option key={parentIssue.id} value={parentIssue.id}>
                        {parentIssue.identifier ?? parentIssue.title}
                      </option>
                    ))}
                  </IssuePropertySelectRow>
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

                {linkedApprovals.length ? (
                  <>
                    <div className="issues-properties-divider" />
                    <section className="issues-properties-section">
                      <h3>Linked approvals</h3>
                      <div className="surface-list dense">
                        {linkedApprovals.map((approval) => (
                          <button
                            className="file-list-button"
                            key={approval.id}
                            onClick={() => onLinkedApprovalSelect(approval.id)}
                            type="button"
                          >
                            <strong>
                              {priorityLabel(
                                approval.approval_type ?? "approval"
                              )}
                            </strong>
                            <span>
                              {priorityLabel(approval.status ?? "pending")}
                              {approval.updated_at
                                ? ` · ${formatIssueDate(approval.updated_at)}`
                                : ""}
                            </span>
                          </button>
                        ))}
                      </div>
                    </section>
                  </>
                ) : null}
              </div>
            </aside>
          </>
        ) : null}
      </div>
    </section>
  );
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
          <circle cx="8" cy="8" r="5.25" stroke="currentColor" strokeWidth="1.8" />
        </svg>
      );
  }
}

function ApprovalsRouteView({
  approvals,
  currentApproval,
  isWorking,
  onSelectApproval,
  onApprove,
}: {
  approvals: ApprovalRecord[];
  currentApproval: ApprovalRecord | null;
  isWorking: boolean;
  onSelectApproval: (approvalId: string) => void;
  onApprove: (approvalId: string, decisionNote?: string) => void;
}) {
  const decisionQuestions = useMemo(
    () => extractApprovalDecisionQuestions(currentApproval),
    [currentApproval]
  );
  const [decisionAnswers, setDecisionAnswers] = useState<Record<string, string>>(
    {}
  );
  const [additionalDecisionContext, setAdditionalDecisionContext] = useState("");

  useEffect(() => {
    setDecisionAnswers({});
    setAdditionalDecisionContext("");
  }, [currentApproval?.id]);

  const decisionNote = useMemo(
    () =>
      composeApprovalDecisionNote(
        decisionQuestions,
        decisionAnswers,
        additionalDecisionContext
      ),
    [additionalDecisionContext, decisionAnswers, decisionQuestions]
  );
  const decisionValidationError = useMemo(
    () =>
      validateApprovalDecision(
        currentApproval,
        decisionQuestions,
        decisionAnswers,
        additionalDecisionContext
      ),
    [
      additionalDecisionContext,
      currentApproval,
      decisionAnswers,
      decisionQuestions,
    ]
  );

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs
          items={
            currentApproval
              ? [
                  { label: "Approvals" },
                  { label: currentApproval.approval_type ?? "Decision queue" },
                ]
              : [{ label: "Approvals" }]
          }
        />
        <h1>Decision queue</h1>
      </div>

      <div className="surface-grid single">
        <section className="surface-panel approvals-panel">
          <div className="surface-header">
            <h3>Approvals</h3>
          </div>
          {approvals.length ? (
            <div className="surface-list">
              {approvals.map((approval) => (
                <ApprovalQueueRow
                  approval={approval}
                  isSelected={currentApproval?.id === approval.id}
                  onClick={() => onSelectApproval(approval.id)}
                />
              ))}
            </div>
          ) : (
            <p className="approvals-empty-text">
              Hire approvals and issue-linked approvals will appear here.
            </p>
          )}
        </section>

        {currentApproval ? (
          <section className="surface-panel approvals-panel">
            <div className="surface-header">
              <h3>Approval Details</h3>
            </div>

            <div className="approvals-detail-stack">
              <div className="approvals-detail-header">
                <div>
                  <h2>{currentApproval.approval_type ?? "approval"}</h2>
                  <p>Status: {currentApproval.status ?? "pending"}</p>
                </div>

                {currentApproval.status === "pending" ? (
                  <button
                    className="primary-button"
                    disabled={isWorking || Boolean(decisionValidationError)}
                    onClick={() => onApprove(currentApproval.id, decisionNote)}
                    type="button"
                  >
                    Approve
                  </button>
                ) : null}
              </div>

              <div className="approvals-detail-grid">
                <DetailRow
                  label="Requested By Agent"
                  value={currentApproval.requested_by_agent_id ?? "System"}
                />
                <DetailRow
                  label="Requested By User"
                  value={currentApproval.requested_by_user_id ?? "Local Board"}
                />
                <DetailRow
                  label="Decided By"
                  value={currentApproval.decided_by_user_id ?? "Pending"}
                />
                <DetailRow
                  label="Created"
                  value={formatBoardDate(currentApproval.created_at)}
                />
                <DetailRow
                  label="Updated"
                  value={formatBoardDate(currentApproval.updated_at)}
                />
              </div>

              {decisionQuestions.length ? (
                <section className="approvals-decision-section">
                  <div className="approvals-decision-header">
                    <h3>Requested Decision</h3>
                    <p>
                      Answering this approval will resume the linked agent run
                      with your decision.
                    </p>
                  </div>
                  <div className="approvals-decision-stack">
                    {decisionQuestions.map((question, index) => {
                      const answerKey = approvalDecisionAnswerKey(question, index);
                      const selectedAnswer = decisionAnswers[answerKey] ?? "";
                      return (
                        <div
                          className="approvals-decision-card"
                          key={answerKey}
                        >
                          <div className="approvals-decision-card-copy">
                            {question.header ? (
                              <span className="approvals-decision-chip">
                                {question.header}
                              </span>
                            ) : null}
                            <strong>{question.question}</strong>
                          </div>
                          {question.options.length ? (
                            <div className="approvals-decision-options">
                              {question.options.map((option) => {
                                const isSelected =
                                  selectedAnswer === option.label;
                                return (
                                  <button
                                    className={
                                      isSelected
                                        ? "approvals-decision-option active"
                                        : "approvals-decision-option"
                                    }
                                    key={option.label}
                                    onClick={() =>
                                      setDecisionAnswers((previous) => ({
                                        ...previous,
                                        [answerKey]: option.label,
                                      }))
                                    }
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
                          ) : (
                            <textarea
                              className="approvals-decision-textarea"
                              onChange={(event) =>
                                setDecisionAnswers((previous) => ({
                                  ...previous,
                                  [answerKey]: event.target.value,
                                }))
                              }
                              placeholder="Add the board's answer..."
                              rows={3}
                              value={selectedAnswer}
                            />
                          )}
                        </div>
                      );
                    })}
                  </div>

                  {currentApproval.status === "pending" ? (
                    <label className="approvals-decision-note-field">
                      <span>Additional Context</span>
                      <textarea
                        className="approvals-decision-textarea"
                        onChange={(event) =>
                          setAdditionalDecisionContext(event.target.value)
                        }
                        placeholder="Optional details for the agent..."
                        rows={3}
                        value={additionalDecisionContext}
                      />
                    </label>
                  ) : null}

                  {decisionValidationError ? (
                    <p className="approvals-decision-error">
                      {decisionValidationError}
                    </p>
                  ) : null}
                </section>
              ) : null}

              {currentApproval.decision_note ? (
                <section className="approvals-answer-section">
                  <h3>Decision Note</h3>
                  <pre>{currentApproval.decision_note}</pre>
                </section>
              ) : null}

              {currentApproval.payload &&
              Object.keys(currentApproval.payload).length > 0 ? (
                <section className="approvals-payload-section">
                  <h3>Payload</h3>
                  <pre>{formatApprovalPayload(currentApproval.payload)}</pre>
                </section>
              ) : null}
            </div>
          </section>
        ) : (
          <section className="surface-panel approvals-panel">
            <div className="surface-header">
              <h3>Approval Details</h3>
            </div>
            <div className="workspace-empty-state approvals-empty-state">
              <h3>Select an approval</h3>
              <p>Approval payloads and decisions show here.</p>
            </div>
          </section>
        )}
      </div>
    </section>
  );
}

type ApprovalDecisionOption = {
  label: string;
  description: string | null;
};

type ApprovalDecisionQuestion = {
  id: string | null;
  header: string | null;
  question: string;
  options: ApprovalDecisionOption[];
};

function extractApprovalDecisionQuestions(
  approval: ApprovalRecord | null
): ApprovalDecisionQuestion[] {
  const payload = approval?.payload;
  if (!payload || typeof payload !== "object") {
    return [];
  }

  const rawQuestions = Array.isArray(payload.questions)
    ? payload.questions
    : typeof payload.question === "string" && payload.question.trim()
      ? [
          {
            question: payload.question,
            options: Array.isArray(payload.options) ? payload.options : [],
          },
        ]
      : [];

  return rawQuestions
    .map((value) => parseApprovalDecisionQuestion(value))
    .filter((value): value is ApprovalDecisionQuestion => value !== null);
}

function parseApprovalDecisionQuestion(
  value: unknown
): ApprovalDecisionQuestion | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const record = value as Record<string, unknown>;

  const questionValue =
    typeof record.question === "string"
      ? record.question.trim()
      : typeof record.prompt === "string"
        ? record.prompt.trim()
        : "";
  if (!questionValue) {
    return null;
  }

  const idValue =
    typeof record.id === "string" && record.id.trim() ? record.id.trim() : null;
  const headerValue =
    typeof record.header === "string" && record.header.trim()
      ? record.header.trim()
      : typeof record.label === "string" && record.label.trim()
        ? record.label.trim()
        : null;

  return {
    id: idValue,
    header: headerValue,
    question: questionValue,
    options: parseApprovalDecisionOptions(record.options),
  };
}

function parseApprovalDecisionOptions(value: unknown): ApprovalDecisionOption[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((entry) => {
      if (typeof entry === "string") {
        const label = entry.trim();
        return label ? { label, description: null } : null;
      }
      if (!entry || typeof entry !== "object") {
        return null;
      }
      const record = entry as Record<string, unknown>;

      const label =
        typeof record.label === "string" && record.label.trim()
          ? record.label.trim()
          : typeof record.title === "string" && record.title.trim()
            ? record.title.trim()
            : null;
      if (!label) {
        return null;
      }

      const description =
        typeof record.description === "string" && record.description.trim()
          ? record.description.trim()
          : null;
      return { label, description };
    })
    .filter((entry): entry is ApprovalDecisionOption => entry !== null);
}

function approvalDecisionAnswerKey(
  question: ApprovalDecisionQuestion,
  index: number
) {
  return question.id ?? `question-${index}`;
}

function composeApprovalDecisionNote(
  questions: ApprovalDecisionQuestion[],
  answers: Record<string, string>,
  additionalContext: string
) {
  const sections = questions
    .map((question, index) => {
      const answer = answers[approvalDecisionAnswerKey(question, index)]?.trim();
      if (!answer) {
        return null;
      }
      const label = question.header ?? question.question;
      return `${label}: ${answer}`;
    })
    .filter((value): value is string => Boolean(value));

  const trimmedContext = additionalContext.trim();
  if (trimmedContext) {
    sections.push(`Additional context:\n${trimmedContext}`);
  }

  return sections.join("\n\n").trim();
}

function validateApprovalDecision(
  approval: ApprovalRecord | null,
  questions: ApprovalDecisionQuestion[],
  answers: Record<string, string>,
  additionalContext: string
) {
  if (approval?.status !== "pending" || approval.approval_type !== "agent_decision") {
    return null;
  }

  if (!questions.length) {
    return additionalContext.trim()
      ? null
      : "Add the board's decision before approving.";
  }

  for (let index = 0; index < questions.length; index += 1) {
    const question = questions[index];
    const answer = answers[approvalDecisionAnswerKey(question, index)]?.trim();
    if (!answer) {
      return question.options.length
        ? `Choose an option for "${question.question}".`
        : `Add an answer for "${question.question}".`;
    }
  }

  return null;
}

function ActivityRouteView({
  approvals,
  issues,
  issueCommentsByIssueId,
  onOpenApproval,
  onOpenIssue,
}: {
  approvals: ApprovalRecord[];
  issues: IssueRecord[];
  issueCommentsByIssueId: Record<string, IssueCommentRecord[]>;
  onOpenApproval: (approvalId: string) => void;
  onOpenIssue: (issueId: string) => void;
}) {
  const feedItems = useMemo(
    () => buildActivityFeedItems(approvals, issues, issueCommentsByIssueId),
    [approvals, issues, issueCommentsByIssueId]
  );

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: "Activity" }]} />
        <span className="route-kicker">Activity</span>
        <h1>Approvals and recent issue activity</h1>
      </div>

      <div className="surface-grid single">
        <section className="surface-panel activity-panel">
          <div className="surface-header">
            <h3>Activity</h3>
          </div>

          {feedItems.length ? (
            <div className="surface-list activity-feed-list">
              {feedItems.map((item) => (
                <ActivityFeedRow
                  item={item}
                  key={item.id}
                  onClick={() => {
                    if (item.target.kind === "approval") {
                      onOpenApproval(item.target.approvalId);
                      return;
                    }

                    onOpenIssue(item.target.issueId);
                  }}
                />
              ))}
            </div>
          ) : (
            <p className="activity-empty-text">
              Pending approvals and recent issue activity will appear here.
            </p>
          )}
        </section>
      </div>
    </section>
  );
}

function ActivityFeedRow({
  item,
  onClick,
}: {
  item: ActivityFeedItem;
  onClick: () => void;
}) {
  return (
    <button className="activity-feed-row" onClick={onClick} type="button">
      <div className="activity-feed-row-main">
        <strong>{item.title}</strong>
        <span>{item.subtitle}</span>
      </div>
      <span className="activity-feed-row-trailing">
        {item.trailingLabel.replaceAll("_", " ")}
      </span>
    </button>
  );
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
          right.name || right.title || right.role || right.id
        );
      }),
    [agents]
  );
  const companyBudget = companyBudgetCents(company);
  const companySpent = companySpentCents(company);
  const companyRemaining = companyBudget - companySpent;
  const agentTrackedSpend = sortedAgents.reduce(
    (total, agent) => total + agentSpentCents(agent),
    0
  );
  const agentsWithSpendCount = sortedAgents.filter(
    (agent) => agentSpentCents(agent) > 0
  ).length;
  const overBudgetAgentsCount = sortedAgents.filter(isAgentOverBudget).length;
  const companyUtilizationLabel = formatBudgetUtilization(
    companySpent,
    companyBudget
  );
  const companyBudgetStatus = companyBudgetStatusLabel(
    companySpent,
    companyBudget
  );
  const unattributedSpend = companySpent - agentTrackedSpend;

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: "Costs" }]} />
        <span className="route-kicker">Costs</span>
        <h1>Budget and spend</h1>
        <p>
          Company and agent spend from the daemon-backed board models, matching
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
            <h3>Company Budget</h3>
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
                  : `${formatCents(companySpent)} spent this month with no company budget cap`}
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
              <span>Company Policy</span>
              <strong>
                {companyBudget > 0 ? "Budget capped" : "No company cap"}
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
              Agent spend will appear here once the company has active agents.
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

function ProjectsRouteView({
  projects,
  goals,
  currentProject,
  currentProjectIssueCount,
  currentProjectWorkspaceCount,
  onDeleteProject,
  onSelectProject,
  onOpenCreateProject,
}: {
  projects: ProjectRecord[];
  goals: GoalRecord[];
  currentProject: ProjectRecord | null;
  currentProjectIssueCount: number;
  currentProjectWorkspaceCount: number;
  onDeleteProject: (projectId: string) => Promise<void>;
  onSelectProject: (projectId: string) => void;
  onOpenCreateProject: () => void;
}) {
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeletingProject, setIsDeletingProject] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  useEffect(() => {
    setIsDeleteDialogOpen(false);
    setIsDeletingProject(false);
    setDeleteError(null);
  }, [currentProject?.id]);

  const handleConfirmProjectDelete = async () => {
    if (!currentProject || isDeletingProject) {
      return;
    }

    setDeleteError(null);
    setIsDeletingProject(true);

    try {
      await onDeleteProject(currentProject.id);
      setIsDeleteDialogOpen(false);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : String(error));
      setIsDeletingProject(false);
    }
  };

  return (
    <>
      <section className="route-scroll">
        <div className="route-header compact projects-route-header">
          <div>
            <DashboardBreadcrumbs
              items={
                currentProject
                  ? [
                      { label: "Projects" },
                      {
                        label:
                          currentProject.name ??
                          currentProject.title ??
                          "Project",
                      },
                    ]
                  : [{ label: "Projects" }]
              }
            />
            <span className="route-kicker">Projects</span>
            <h1>Repo anchors and ownership</h1>
          </div>

          <button
            className="primary-button"
            onClick={onOpenCreateProject}
            type="button"
          >
            New Project
          </button>
        </div>

        <section className="surface-panel projects-panel">
          <div className="surface-header projects-detail-header">
            <h3>Project Details</h3>
            {currentProject ? (
              <button
                className="secondary-button compact-button destructive-button"
                onClick={() => setIsDeleteDialogOpen(true)}
                type="button"
              >
                Delete Project
              </button>
            ) : null}
          </div>

          {currentProject ? (
            <div className="projects-detail-stack">
              <h2>{currentProject.name}</h2>

              {currentProject.description ? (
                <section className="projects-detail-section">
                  <h3>Description</h3>
                  <p>{currentProject.description}</p>
                </section>
              ) : null}

              <div className="projects-detail-grid">
                <DetailRow label="Status" value={currentProject.status} />
                <DetailRow
                  label="Lead Agent"
                  value={currentProject.lead_agent_id ?? "Unassigned"}
                />
                <DetailRow
                  label="Goal"
                  value={goalTitleForProject(goals, currentProject.goal_id)}
                />
                <DetailRow
                  label="Issues"
                  value={String(currentProjectIssueCount)}
                />
                <DetailRow
                  label="Worktrees"
                  value={String(currentProjectWorkspaceCount)}
                />
                <DetailRow
                  label="Repo Path"
                  value={currentProject.primary_workspace?.cwd ?? "Missing"}
                />
                <DetailRow
                  label="Repo URL"
                  value={
                    currentProject.primary_workspace?.repo_url ?? "Local only"
                  }
                />
                <DetailRow
                  label="Repo Ref"
                  value={currentProject.primary_workspace?.repo_ref ?? "main"}
                />
              </div>
            </div>
          ) : (
            <div className="workspace-empty-state projects-empty-state-panel">
              <h3>Select a project</h3>
              <p>Project repo-anchor configuration appears here.</p>
            </div>
          )}
        </section>

        <section className="surface-panel projects-panel">
          <div className="surface-header">
            <h3>Projects</h3>
          </div>
          {projects.length ? (
            <div className="surface-list">
              {projects.map((project) => (
                <ProjectQueueRow
                  isSelected={currentProject?.id === project.id}
                  key={project.id}
                  onClick={() => onSelectProject(project.id)}
                  project={project}
                />
              ))}
            </div>
          ) : (
            <p className="projects-empty-text">
              Projects define the main repo anchor that issue worktrees run
              inside.
            </p>
          )}
        </section>
      </section>

      {isDeleteDialogOpen && currentProject ? (
        <DeleteProjectDialogView
          errorMessage={deleteError}
          isDeleting={isDeletingProject}
          issueCount={currentProjectIssueCount}
          onClose={() => {
            if (!isDeletingProject) {
              setIsDeleteDialogOpen(false);
            }
          }}
          onConfirm={() => void handleConfirmProjectDelete()}
          project={currentProject}
          workspaceCount={currentProjectWorkspaceCount}
        />
      ) : null}
    </>
  );
}

function GoalsRouteView({
  agents,
  currentGoal,
  goals,
  onSelectGoal,
  projects,
}: {
  agents: AgentRecord[];
  currentGoal: GoalRecord | null;
  goals: GoalRecord[];
  onSelectGoal: (goalId: string) => void;
  projects: ProjectRecord[];
}) {
  const childGoals = currentGoal
    ? goals.filter((goal) => goal.parent_id === currentGoal.id)
    : [];
  const relatedProjects = currentGoal
    ? projects.filter((project) => project.goal_id === currentGoal.id)
    : [];

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs
          items={
            currentGoal
              ? [{ label: "Goals" }, { label: currentGoal.title }]
              : [{ label: "Goals" }]
          }
        />
        <span className="route-kicker">Goals</span>
        <h1>Board objectives and hierarchy</h1>
        <p>
          Goals are already loaded from the daemon and used during project
          planning. This route surfaces them directly in the company shell.
        </p>
      </div>

      <section className="surface-panel goals-panel">
        <div className="surface-header">
          <h3>Goals</h3>
        </div>
        {goals.length ? (
          <div className="surface-list">
            {goals.map((goal) => (
              <GoalQueueRow
                goal={goal}
                isSelected={currentGoal?.id === goal.id}
                key={goal.id}
                onClick={() => onSelectGoal(goal.id)}
              />
            ))}
          </div>
        ) : (
          <div className="workspace-empty-state goals-empty-state-panel">
            <h3>No goals yet</h3>
            <p>
              Goals created through the daemon-backed board flows will appear
              here.
            </p>
          </div>
        )}
      </section>

      {currentGoal ? (
        <section className="surface-panel goals-panel">
          <div className="surface-header">
            <h3>Goal Details</h3>
          </div>

          <div className="goals-detail-stack">
            <div className="goals-detail-hero">
              <div>
                <span className="goal-level-pill">
                  {humanizeIssueValue(currentGoal.level ?? "company")}
                </span>
                <h2>{currentGoal.title}</h2>
              </div>
              <span className="goal-status-pill">
                {humanizeIssueValue(currentGoal.status ?? "planned")}
              </span>
            </div>

            {currentGoal.description ? (
              <section className="projects-detail-section">
                <h3>Description</h3>
                <p>{currentGoal.description}</p>
              </section>
            ) : null}

            <div className="goals-detail-grid">
              <DetailRow
                label="Level"
                value={humanizeIssueValue(currentGoal.level ?? "company")}
              />
              <DetailRow
                label="Status"
                value={humanizeIssueValue(currentGoal.status ?? "planned")}
              />
              <DetailRow
                label="Owner Agent"
                value={goalOwnerLabel(agents, currentGoal.owner_agent_id)}
              />
              <DetailRow
                label="Parent Goal"
                value={goalTitleForProject(goals, currentGoal.parent_id)}
              />
              <DetailRow
                label="Child Goals"
                value={String(childGoals.length)}
              />
              <DetailRow
                label="Linked Projects"
                value={String(relatedProjects.length)}
              />
              <DetailRow
                label="Created"
                value={formatBoardDate(currentGoal.created_at)}
              />
              <DetailRow
                label="Updated"
                value={formatBoardDate(currentGoal.updated_at)}
              />
            </div>

            {childGoals.length ? (
              <section className="goals-detail-section">
                <h3>Child Goals</h3>
                <div className="surface-list">
                  {childGoals.map((goal) => (
                    <button
                      className="goal-relationship-row"
                      key={goal.id}
                      onClick={() => onSelectGoal(goal.id)}
                      type="button"
                    >
                      <div className="goal-relationship-row-main">
                        <strong>{goal.title}</strong>
                        <span>
                          {humanizeIssueValue(goal.status ?? "planned")}
                        </span>
                      </div>
                      <span className="goal-relationship-row-trailing">
                        {humanizeIssueValue(goal.level ?? "company")}
                      </span>
                    </button>
                  ))}
                </div>
              </section>
            ) : null}

            {relatedProjects.length ? (
              <section className="goals-detail-section">
                <h3>Linked Projects</h3>
                <div className="surface-list">
                  {relatedProjects.map((project) => (
                    <div className="surface-list-row" key={project.id}>
                      <span>{project.name}</span>
                      <strong>
                        {humanizeIssueValue(project.status ?? "planned")}
                      </strong>
                    </div>
                  ))}
                </div>
              </section>
            ) : null}
          </div>
        </section>
      ) : null}
    </section>
  );
}

function GoalQueueRow({
  goal,
  isSelected,
  onClick,
}: {
  goal: GoalRecord;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={isSelected ? "goal-queue-row active" : "goal-queue-row"}
      onClick={onClick}
      type="button"
    >
      <div className="goal-queue-row-main">
        <strong>{goal.title}</strong>
        <span>{goal.description ?? "No description yet"}</span>
      </div>
      <div className="goal-queue-row-meta">
        <span>{humanizeIssueValue(goal.level ?? "company")}</span>
        <span>{humanizeIssueValue(goal.status ?? "planned")}</span>
      </div>
    </button>
  );
}

function ProjectQueueRow({
  project,
  isSelected,
  onClick,
}: {
  project: ProjectRecord;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={isSelected ? "project-queue-row active" : "project-queue-row"}
      onClick={onClick}
      type="button"
    >
      <div className="project-queue-row-main">
        <strong>{project.name}</strong>
        <span>{project.primary_workspace?.cwd ?? "Missing repo path"}</span>
      </div>
      <span className="project-queue-row-trailing">{project.status}</span>
    </button>
  );
}

function DeleteProjectDialogView({
  errorMessage,
  isDeleting,
  issueCount,
  onClose,
  onConfirm,
  project,
  workspaceCount,
}: {
  errorMessage: string | null;
  isDeleting: boolean;
  issueCount: number;
  onClose: () => void;
  onConfirm: () => void;
  project: ProjectRecord;
  workspaceCount: number;
}) {
  return (
    <div
      className="modal-backdrop"
      onClick={() => {
        if (!isDeleting) {
          onClose();
        }
      }}
      role="presentation"
    >
      <div
        aria-describedby="delete-project-dialog-description"
        aria-labelledby="delete-project-dialog-title"
        aria-modal="true"
        className="project-dialog project-delete-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="delete-project-dialog-title">
              Delete {project.name ?? project.title ?? "project"}?
            </h2>
            <p id="delete-project-dialog-description">
              This will permanently delete this project, all related issues, and
              all related worktrees. This action cannot be undone.
            </p>
          </div>
          <button
            aria-label="Close delete project dialog"
            className="project-dialog-close"
            disabled={isDeleting}
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

          <div className="project-delete-impact-grid">
            <div className="project-delete-impact-card">
              <strong>{issueCount}</strong>
              <span>Issues will be deleted</span>
            </div>
            <div className="project-delete-impact-card">
              <strong>{workspaceCount}</strong>
              <span>Worktrees will be deleted</span>
            </div>
          </div>

          <p className="project-delete-warning">
            Repository records stay intact, but every board issue and worktree
            anchored to this project will be removed.
          </p>
        </div>

        <div className="issue-dialog-footer project-dialog-footer">
          <button
            className="secondary-button"
            disabled={isDeleting}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="secondary-button destructive-button"
            disabled={isDeleting}
            onClick={onConfirm}
            type="button"
          >
            {isDeleting ? "Deleting..." : "Delete Project"}
          </button>
        </div>
      </div>
    </div>
  );
}

function CreateProjectDialogView({
  repoPath,
  derivedProjectName,
  selectedStatus,
  selectedGoalId,
  targetDate,
  goals,
  isSaving,
  errorMessage,
  onChooseFolder,
  onStatusChange,
  onGoalChange,
  onTargetDateChange,
  onCreate,
  onClose,
}: {
  repoPath: string;
  derivedProjectName: string;
  selectedStatus: string;
  selectedGoalId: string;
  targetDate: string;
  goals: GoalRecord[];
  isSaving: boolean;
  errorMessage: string | null;
  onChooseFolder: () => void;
  onStatusChange: (value: string) => void;
  onGoalChange: (value: string) => void;
  onTargetDateChange: (value: string) => void;
  onCreate: () => void;
  onClose: () => void;
}) {
  const canCreate = Boolean(derivedProjectName) && !isSaving;

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        aria-modal="true"
        aria-labelledby="create-project-dialog-title"
        className="project-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="create-project-dialog-title">New project</h2>
            <p>
              Create a project from a repository folder and set its default
              board context.
            </p>
          </div>

          <button
            aria-label="Close create project dialog"
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
            <div className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Repository folder</span>
              <div className="project-folder-row">
                <div className="project-dialog-value-shell">
                  <span
                    className={
                      repoPath ? undefined : "project-dialog-value-placeholder"
                    }
                  >
                    {repoPath || "Choose a project folder"}
                  </span>
                </div>

                <button
                  className="secondary-button"
                  onClick={onChooseFolder}
                  type="button"
                >
                  Choose folder
                </button>
              </div>
              <small className="issue-dialog-hint">
                We&apos;ll use the selected folder name as the initial project
                title.
              </small>
            </div>

            <div className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Project name</span>
              <div className="project-dialog-value-shell">
                <span
                  className={
                    derivedProjectName
                      ? undefined
                      : "project-dialog-value-placeholder"
                  }
                >
                  {derivedProjectName || "Select a folder to generate a name"}
                </span>
              </div>
              <small className="issue-dialog-hint">
                You can rename the project later from the project detail page.
              </small>
            </div>

            <div className="project-dialog-grid">
              <ProjectDialogSelectField
                hint="Sets the default board status when the project is created."
                label="Status"
                onChange={onStatusChange}
                value={selectedStatus}
              >
                {["planned", "active", "completed"].map((status) => (
                  <option key={status} value={status}>
                    {humanizeIssueValue(status)}
                  </option>
                ))}
              </ProjectDialogSelectField>

              <ProjectDialogSelectField
                hint="Optionally connect the project to a larger goal."
                label="Goal"
                onChange={onGoalChange}
                value={selectedGoalId}
              >
                <option value="">No goal</option>
                {goals.map((goal) => (
                  <option key={goal.id} value={goal.id}>
                    {goal.title}
                  </option>
                ))}
              </ProjectDialogSelectField>

              <label className="project-dialog-field">
                <span className="issue-dialog-label">Target date</span>
                <input
                  className="issue-dialog-input"
                  onChange={(event) => onTargetDateChange(event.target.value)}
                  type="date"
                  value={targetDate}
                />
                <small className="issue-dialog-hint">
                  Optional milestone date for planning and review.
                </small>
              </label>
            </div>
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
            {isSaving ? "Creating project..." : "Create project"}
          </button>
        </div>
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
        aria-modal="true"
        aria-labelledby="create-company-dialog-title"
        className="project-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="create-company-dialog-title">New company</h2>
            <p>
              Add a company shell to the board so you can start routing agents,
              issues, and projects into it.
            </p>
          </div>

          <button
            aria-label="Close create company dialog"
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
              <span className="issue-dialog-label">Company name</span>
              <input
                autoFocus
                className="issue-dialog-input"
                onChange={(event) => onNameChange(event.target.value)}
                placeholder="Acme Systems"
                type="text"
                value={name}
              />
              <small className="issue-dialog-hint">
                Shown in the companies rail, dashboard, and board context menus.
              </small>
            </label>

            <label className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Description</span>
              <textarea
                className="issue-dialog-input issue-dialog-textarea"
                onChange={(event) => onDescriptionChange(event.target.value)}
                placeholder="Optional context for what this company owns or how it should operate inside the board..."
                value={description}
              />
              <small className="issue-dialog-hint">
                Optional setup context you can refine later from company
                settings.
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
                Optional hex color used for the company badge in the rail.
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
            {isSaving ? "Creating company..." : "Create company"}
          </button>
        </div>
      </div>
    </div>
  );
}

function ProjectDialogSelectField({
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
    <label className="project-dialog-field">
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

function CreateIssueDialogView({
  companyPrefix,
  title,
  description,
  attachments,
  selectedPriority,
  selectedProjectId,
  selectedStatus,
  selectedAssigneeAgentId,
  priorities,
  statuses,
  projects,
  agents,
  isSaving,
  errorMessage,
  onAddAttachment,
  onTitleChange,
  onDescriptionChange,
  onPriorityChange,
  onStatusChange,
  onProjectChange,
  onRemoveAttachment,
  onWorkspaceTargetChange,
  onAssigneeChange,
  onCreate,
  onClose,
  selectedWorkspaceTargetValue,
  workspaceTargetErrorMessage,
  workspaceTargetLoading,
  workspaceTargetWorktrees,
}: {
  companyPrefix: string;
  title: string;
  description: string;
  attachments: IssueAttachmentDraft[];
  selectedPriority: string;
  selectedProjectId: string;
  selectedStatus: string;
  selectedAssigneeAgentId: string;
  priorities: string[];
  statuses: string[];
  projects: ProjectRecord[];
  agents: AgentRecord[];
  isSaving: boolean;
  errorMessage: string | null;
  onAddAttachment: () => void;
  onTitleChange: (value: string) => void;
  onDescriptionChange: (value: string) => void;
  onPriorityChange: (value: string) => void;
  onStatusChange: (value: string) => void;
  onProjectChange: (value: string) => void;
  onRemoveAttachment: (path: string) => void;
  onWorkspaceTargetChange: (value: string) => void;
  onAssigneeChange: (value: string) => void;
  onCreate: () => void;
  onClose: () => void;
  selectedWorkspaceTargetValue: string;
  workspaceTargetErrorMessage: string | null;
  workspaceTargetLoading: boolean;
  workspaceTargetWorktrees: GitWorktreeRecord[];
}) {
  const issueCompanyPrefix = stringFromUnknown(companyPrefix, "ISS");
  const issueTitle = stringFromUnknown(title);
  const issueDescription = stringFromUnknown(description);
  const issuePriority = stringFromUnknown(selectedPriority);
  const issueStatus = stringFromUnknown(selectedStatus);
  const issueProjectId = stringFromUnknown(selectedProjectId);
  const issueAssigneeAgentId = stringFromUnknown(selectedAssigneeAgentId);
  const issueWorkspaceTargetValue = stringFromUnknown(
    selectedWorkspaceTargetValue,
    "main"
  );
  const issueErrorMessage = errorMessage
    ? stringFromUnknown(errorMessage)
    : null;
  const issueWorkspaceTargetErrorMessage = workspaceTargetErrorMessage
    ? stringFromUnknown(workspaceTargetErrorMessage)
    : null;
  const isSavingIssue = booleanFromUnknown(isSaving);
  const attachmentDrafts = arrayFromUnknown(attachments).filter(
    (attachment): attachment is IssueAttachmentDraft =>
      Boolean(attachment) &&
      typeof attachment === "object" &&
      typeof (attachment as IssueAttachmentDraft).path === "string" &&
      typeof (attachment as IssueAttachmentDraft).name === "string"
  );
  const priorityOptions = arrayFromUnknown(priorities).filter(
    (priority): priority is string => typeof priority === "string"
  );
  const statusOptions = arrayFromUnknown(statuses).filter(
    (status): status is string => typeof status === "string"
  );
  const projectOptions = arrayFromUnknown(projects).filter(
    (project): project is ProjectRecord =>
      Boolean(project) &&
      typeof project === "object" &&
      typeof (project as ProjectRecord).id === "string"
  );
  const agentOptions = arrayFromUnknown(agents).filter(
    (agent): agent is AgentRecord =>
      Boolean(agent) &&
      typeof agent === "object" &&
      typeof (agent as AgentRecord).id === "string"
  );
  const worktreeOptions = normalizeGitWorktreeRecords(
    workspaceTargetWorktrees
  );
  const issueValidationMessage = issueStatusAssigneeValidationMessage(
    issueStatus,
    issueAssigneeAgentId,
    agentOptions
  );
  const visibleIssueErrorMessage = issueValidationMessage ?? issueErrorMessage;
  const canCreate =
    !isSavingIssue &&
    issueTitle.trim().length > 0 &&
    issueValidationMessage === null;
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
        issueWorkspaceTargetValue
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

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        aria-modal="true"
        aria-labelledby="create-issue-dialog-title"
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
            <span id="create-issue-dialog-title">New issue</span>
          </div>
          <button
            aria-label="Close create issue dialog"
            className="project-dialog-close issue-dialog-close"
            onClick={onClose}
            type="button"
          >
            x
          </button>
        </div>

        <div className="issue-dialog-body">
          {visibleIssueErrorMessage ? (
            <div className="issue-dialog-alert">
              {visibleIssueErrorMessage}
            </div>
          ) : null}

          <div className="issue-dialog-composer">
            <input
              autoFocus
              className="issue-dialog-title-input"
              onChange={(event) => onTitleChange(event.target.value)}
              placeholder="Issue title"
              value={issueTitle}
            />

            <div className="issue-dialog-inline-row">
              <span className="issue-dialog-inline-copy">For</span>
              <IssueDialogInlineSelect
                ariaLabel="Select assignee"
                onChange={onAssigneeChange}
                value={issueAssigneeAgentId}
              >
                <option value="">Assignee</option>
                {agentOptions.map((agent) => (
                  <option key={agent.id} value={agent.id}>
                    {agent.name || agent.title || agent.role || agent.id}
                  </option>
                ))}
              </IssueDialogInlineSelect>
              <span className="issue-dialog-inline-copy">in</span>
              <IssueDialogInlineSelect
                ariaLabel="Select project"
                className="issue-dialog-inline-select-project"
                onChange={onProjectChange}
                value={issueProjectId}
              >
                <option value="">Project</option>
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
                          fallbackSelectedWorktree.path
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
          </div>

          <div className="issue-dialog-divider" />

          <div className="issue-dialog-description-panel">
            <textarea
              className="issue-dialog-description-input"
              onChange={(event) => onDescriptionChange(event.target.value)}
              placeholder="Add description..."
              value={issueDescription}
            />

            {attachmentDrafts.length ? (
              <div className="issue-dialog-attachments">
                <div className="issues-detail-subsection-header">
                  <div className="issues-detail-subsection-copy">
                    <h3>Attachments</h3>
                    <p className="issues-detail-copy muted">
                      These files will be copied into the board storage and
                      linked to the issue when it is created.
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
            <IssueDialogFooterSelect
              ariaLabel="Select issue status"
              onChange={onStatusChange}
              value={issueStatus}
            >
              {statusOptions.map((status) => (
                <option key={status} value={status}>
                  {humanizeIssueValue(status)}
                </option>
              ))}
            </IssueDialogFooterSelect>

            <IssueDialogFooterSelect
              ariaLabel="Select issue priority"
              onChange={onPriorityChange}
              value={issuePriority}
            >
              {priorityOptions.map((priority) => (
                <option key={priority} value={priority}>
                  {humanizeIssueValue(priority)}
                </option>
              ))}
            </IssueDialogFooterSelect>

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
              {isSavingIssue ? "Creating..." : "Create Issue"}
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

function IssueDialogFooterSelect({
  ariaLabel,
  children,
  onChange,
  value,
}: {
  ariaLabel: string;
  children: ReactNode;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <div className="issue-dialog-footer-chip">
      <select
        aria-label={ariaLabel}
        className="issue-dialog-footer-chip-control"
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        {children}
      </select>
      <span aria-hidden="true" className="issue-dialog-footer-chip-arrow">
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

function ApprovalQueueRow({
  approval,
  isSelected,
  onClick,
}: {
  approval: ApprovalRecord;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={
        isSelected ? "approval-queue-row active" : "approval-queue-row"
      }
      onClick={onClick}
      type="button"
    >
      <div className="approval-queue-row-main">
        <strong>{approval.approval_type ?? "approval"}</strong>
        <span>{formatBoardDate(approval.created_at)}</span>
      </div>
      <span className="approval-queue-row-trailing">
        {approval.status ?? "pending"}
      </span>
    </button>
  );
}

function DashboardBreadcrumbs({ items }: { items: DashboardBreadcrumbItem[] }) {
  return (
    <nav aria-label="Breadcrumb" className="dashboard-breadcrumbs">
      {items.map((item, index) => {
        const isCurrent = index === items.length - 1;

        return (
          <div
            className="dashboard-breadcrumb-step"
            key={`${item.label}-${index}`}
          >
            {item.onClick && !isCurrent ? (
              <button
                className="dashboard-breadcrumb-button"
                onClick={item.onClick}
                type="button"
              >
                {item.label}
              </button>
            ) : (
              <span
                className={
                  isCurrent
                    ? "dashboard-breadcrumb-current"
                    : "dashboard-breadcrumb-label"
                }
              >
                {item.label}
              </span>
            )}

            {!isCurrent ? (
              <span
                aria-hidden="true"
                className="dashboard-breadcrumb-separator"
              >
                ›
              </span>
            ) : null}
          </div>
        );
      })}
    </nav>
  );
}

function RoutePlaceholder({ title, body }: { title: string; body: string }) {
  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <DashboardBreadcrumbs items={[{ label: title }]} />
        <span className="route-kicker">{title}</span>
        <h1>{title}</h1>
        <p>{body}</p>
      </div>
    </section>
  );
}

function BoardPlaceholderView({
  title,
  message,
}: {
  title: string;
  message: string;
}) {
  return (
    <section className="board-placeholder-route">
      <div className="board-placeholder-state">
        <BoardPlaceholderIcon />
        <div className="board-placeholder-copy">
          <h2>{title}</h2>
          <p>{message}</p>
        </div>
      </div>
    </section>
  );
}

function BoardPlaceholderIcon() {
  return (
    <svg
      aria-hidden="true"
      className="board-placeholder-icon"
      fill="none"
      viewBox="0 0 48 48"
    >
      <path
        d="M9 15.5h30v14a5.5 5.5 0 0 1-5.5 5.5H14.5A5.5 5.5 0 0 1 9 29.5v-14Z"
        rx="5.5"
        stroke="currentColor"
        strokeWidth="2.5"
      />
      <path
        d="M16 22h16"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2.5"
      />
      <path
        d="M18.5 12.5h11"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2.5"
      />
    </svg>
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
      {!isAvailable ? (
        <small className="theme-card-meta">Coming soon</small>
      ) : isSelected ? (
        <span className="theme-card-check">✓</span>
      ) : (
        <span className="theme-card-empty" />
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

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="detail-row">
      <span>{label}</span>
      <strong>{value}</strong>
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

function WorkspaceBoardItem({
  active,
  workspace,
  onClick,
}: {
  active: boolean;
  workspace: WorkspaceRecord;
  onClick: () => void;
}) {
  return (
    <button
      className={
        active ? "workspace-board-item active" : "workspace-board-item"
      }
      onClick={onClick}
      type="button"
    >
      <div className="workspace-board-item-top">
        <strong>{workspace.issue_identifier ?? workspace.title}</strong>
        <span className="workspace-status-pill">
          {workspace.workspace_status ?? workspace.status ?? "active"}
        </span>
      </div>
      <span>{workspace.issue_title ?? workspace.title}</span>
      <small>
        {[workspace.project_name, workspace.agent_name]
          .filter(Boolean)
          .join(" · ") || "Assigned worktree"}
      </small>
    </button>
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

function WorkspaceInspectorSidebar({
  currentBranch,
  currentBranchName,
  currentDirectory,
  fileEntries,
  gitCommitMessage,
  gitHistory,
  gitState,
  hasUncommittedChanges,
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
  return (
    <aside className="workspace-inspector">
      {workspace ? (
        <section className="inspector-panel workspace-details-panel">
          <h3>Worktree Details</h3>
          <div className="workspace-detail-grid">
            <DetailRow
              label="Issue"
              value={
                workspace.issue_identifier ?? workspace.issue_id ?? "Missing"
              }
            />
            <DetailRow
              label="Agent"
              value={workspace.agent_name ?? workspace.agent_id ?? "Missing"}
            />
            <DetailRow
              label="Project"
              value={
                workspace.project_name ?? workspace.project_id ?? "Missing"
              }
            />
            <DetailRow
              label="Branch"
              value={workspace.workspace_branch ?? "main"}
            />
            <DetailRow
              label="Repo"
              value={workspace.workspace_repo_path ?? "Missing"}
            />
          </div>
        </section>
      ) : null}

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

          <div className="git-sidebar-actions">
            {hasUncommittedChanges ? (
              <>
                <button
                  className="primary-button compact-button"
                  disabled={isWorking || !gitCommitMessage.trim()}
                  onClick={() => onGitCommit(false)}
                  type="button"
                >
                  Commit
                </button>
                <button
                  className="secondary-button compact-button"
                  disabled={isWorking || !gitCommitMessage.trim()}
                  onClick={() => onGitCommit(true)}
                  type="button"
                >
                  Commit + Push
                </button>
              </>
            ) : (
              <button
                className="primary-button compact-button"
                disabled={isWorking || !hasUnpushedCommits}
                onClick={onGitPush}
                type="button"
              >
                Push
              </button>
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
        </div>

        {workspaceSidebarTab === "changes" ? (
          <div className="workspace-sidebar-content">
            <label className="git-commit-field">
              <span>Commit message</span>
              <input
                onChange={(event) => onGitCommitMessageChange(event.target.value)}
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
                    entry.is_dir ? onOpenDirectory(entry.path) : onOpenFile(entry.path)
                  }
                  type="button"
                >
                  <strong>{entry.is_dir ? `${entry.name}/` : entry.name}</strong>
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
              <SummaryPill label="Changed" value={gitState?.files.length ?? 0} />
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
    case "org":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M8 2.5a1.75 1.75 0 1 1 0 3.5a1.75 1.75 0 0 1 0-3.5ZM3.75 10.25a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0-3ZM12.25 10.25a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0-3Z"
            stroke="currentColor"
            strokeWidth="1.3"
          />
          <path
            d="M8 6v2.25M4 10.25V9h8v1.25"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.3"
          />
        </svg>
      );
    case "workspaces":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M2.5 3.25h4.75v4.75H2.5zM8.75 3.25h4.75v4.75H8.75zM2.5 8.75h4.75v4.75H2.5zM8.75 8.75h4.75v4.75H8.75z"
            rx="1.3"
            stroke="currentColor"
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
    case "inbox":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <path
            d="M2.5 5.25h11v6a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 11.25Z"
            stroke="currentColor"
            strokeWidth="1.4"
          />
          <path
            d="M2.75 8.75h3l1.1 1.5h2.3l1.1-1.5h3"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.4"
          />
          <path
            d="M5 5.25 6 3.5h4l1 1.75"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
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
    case "goals":
      return (
        <svg
          aria-hidden="true"
          className={className}
          fill="none"
          viewBox="0 0 16 16"
        >
          <circle
            cx="8"
            cy="8"
            r="4.75"
            stroke="currentColor"
            strokeWidth="1.3"
          />
          <circle
            cx="8"
            cy="8"
            r="2.25"
            stroke="currentColor"
            strokeWidth="1.3"
          />
          <path
            d="M8 1.75v1.5M8 12.75v1.5M1.75 8h1.5M12.75 8h1.5"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.3"
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
              {!file.staged ? (
                <button
                  className="secondary-button compact-button destructive-button"
                  onClick={() => onDiscard(file)}
                  type="button"
                >
                  Discard
                </button>
              ) : null}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function screenLabel(screen: AppScreen) {
  switch (screen) {
    case "dashboard":
      return "Dashboard";
    case "org":
      return "Org";
    case "stats":
      return "Stats";
    case "inbox":
      return "Inbox";
    case "workspaces":
      return "Worktrees";
    case "agents":
      return "Agents";
    case "issues":
      return "Issues";
    case "approvals":
      return "Approvals";
    case "projects":
      return "Projects";
    case "goals":
      return "Goals";
    case "activity":
      return "Activity";
    case "costs":
      return "Costs";
    case "companySettings":
    case "appSettings":
      return "Settings";
  }
}

function sidebarScreenIcon(
  screen: AppScreen
): CompanyContextMenuIconKey | null {
  switch (screen) {
    case "dashboard":
      return "dashboard";
    case "inbox":
      return "inbox";
    case "workspaces":
      return "workspaces";
    case "issues":
      return "issues";
    case "approvals":
      return "approvals";
    case "goals":
      return "goals";
    case "org":
      return "org";
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
  if (screen === "workspaces") {
    return "workspace";
  }

  if (screen === "appSettings") {
    return "settings";
  }

  return "companyDashboard";
}

function preferredViewForScreen(screen: AppScreen) {
  if (screen === "org") {
    return "org";
  }

  if (screen === "workspaces") {
    return "workspaces";
  }

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
    return "org";
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
    return "workspaces";
  }

  return "dashboard";
}

function preferredViewSelectValue(
  view: string | null | undefined
): DesktopPreferredViewValue {
  if (view === "settings") {
    return "settings";
  }

  if (view === "org") {
    return "org";
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
    return "workspaces";
  }

  return "dashboard";
}

function mergeDesktopSettings(settings: DesktopSettings): DesktopSettings {
  return {
    ...defaultSettings,
    ...settings,
    dashboard_project_views: settings.dashboard_project_views ?? {},
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
  return {
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
    issue.execution_workspace_settings
  );

  return {
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
      "auto"
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
      adapterConfig.environmentVariables ?? adapterConfig.envVars
    ),
    timeoutSec: numericInputValue(runtimeConfig.timeoutSec),
    interruptGraceSec: numericInputValue(runtimeConfig.interruptGraceSec),
    canCreateAgents: booleanFromUnknown(permissions.canCreateAgents),
    monthlyBudget: budgetInputValue(agent.budget_monthly_cents),
  };
}

function createAgentConfigEnvVarDraft(
  value?: Partial<AgentConfigEnvVarDraft>
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
  draft: AgentConfigDraft
) {
  const adapterConfig = {
    ...objectFromUnknown(agent.adapter_config),
    command: normalizeOptionalDraftString(draft.command) ?? "claude",
    model: normalizeOptionalDraftString(draft.model) ?? "default",
    thinkingEffort: normalizeOptionalDraftString(draft.thinkingEffort) ?? "auto",
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
      if (!key && !envValue) {
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

function detectAgentCliProvider(
  command: string | null | undefined,
  model?: string | null
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
  selectedCommand: string
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

function buildAgentModelOptions(
  draft: Pick<AgentConfigDraft, "command" | "model">,
  dependencyCheck: RuntimeCapabilities | null
) {
  const provider = detectAgentCliProvider(draft.command, draft.model);
  const discoveredModels =
    provider === "codex"
      ? dependencyCheck?.cli.codex.installed
        ? dependencyCheck?.cli.codex.models ?? []
        : []
      : provider === "claude"
        ? dependencyCheck?.cli.claude.installed
          ? dependencyCheck?.cli.claude.models ?? []
          : []
        : [];

  return mergeIssueOptions(["default", ...discoveredModels], draft.model);
}

function detectWorkspaceAgentProvider(
  session: SessionRecord | null,
  agent: AgentRecord | null
): AgentCliProvider {
  if (session?.provider) {
    return session.provider === "codex" ? "codex" : "claude";
  }

  if (agent) {
    const adapterConfig = objectFromUnknown(agent.adapter_config);
    return detectAgentCliProvider(
      stringFromUnknown(adapterConfig.command),
      stringFromUnknown(adapterConfig.model)
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

function hasAssignedAgent(
  assigneeAgentId: string | null | undefined,
  agents: AgentRecord[]
) {
  const trimmedAssigneeAgentId = assigneeAgentId?.trim() ?? "";
  return (
    trimmedAssigneeAgentId.length > 0 &&
    agents.some((agent) => agent.id === trimmedAssigneeAgentId)
  );
}

function issueStatusAssigneeValidationMessage(
  status: string | null | undefined,
  assigneeAgentId: string | null | undefined,
  agents: AgentRecord[]
) {
  const hasAgentAssignee = hasAssignedAgent(assigneeAgentId, agents);
  const normalizedStatus = normalizeBoardIssueValue(status);

  if (normalizedStatus === "todo" && !hasAgentAssignee) {
    return "To Do issues must be assigned to an agent.";
  }

  if (normalizedStatus === "in_progress" && hasAgentAssignee) {
    return "In Progress issues cannot have an assigned agent.";
  }

  return null;
}

function normalizeHexColor(
  value: string | null | undefined,
  fallback = defaultCompanyBrandColor
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
  value: string | null | undefined
): DashboardProjectGrouping {
  switch (value?.trim().toLowerCase()) {
    case "priority":
      return "priority";
    case "assignee":
      return "assignee";
    default:
      return "status";
  }
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

function projectBoardColumnPriorities(issues: IssueRecord[]) {
  const priorities = ["urgent", "high", "medium", "low"];
  for (const issue of issues) {
    const normalizedPriority = normalizeBoardIssueValue(issue.priority);
    if (!priorities.includes(normalizedPriority)) {
      priorities.push(normalizedPriority);
    }
  }
  return priorities;
}

function projectBoardColumnsByStatus(
  issues: IssueRecord[]
): DashboardProjectColumn[] {
  return projectBoardColumnStatuses(issues).map((status) => ({
    createDefaults: { status },
    id: `status:${status}`,
    issues: issues.filter(
      (issue) => normalizeBoardIssueValue(issue.status) === status
    ),
    label: issueStatusLabel(status),
  }));
}

function projectBoardColumnsByPriority(
  issues: IssueRecord[]
): DashboardProjectColumn[] {
  return projectBoardColumnPriorities(issues).map((priority) => ({
    createDefaults: { priority },
    id: `priority:${priority}`,
    issues: issues.filter(
      (issue) => normalizeBoardIssueValue(issue.priority) === priority
    ),
    label: humanizeIssueValue(priority),
  }));
}

function projectBoardColumnsByAssignee(
  issues: IssueRecord[],
  agents: AgentRecord[]
): DashboardProjectColumn[] {
  const assigneeIds = Array.from(
    new Set(
      issues
        .map((issue) => issue.assignee_agent_id?.trim() ?? "")
        .filter((assigneeAgentId) => assigneeAgentId.length > 0)
    )
  ).sort((left, right) =>
    issueAssigneeLabel(agents, left).localeCompare(
      issueAssigneeLabel(agents, right)
    )
  );

  return ["", ...assigneeIds].map((assigneeAgentId) => ({
    createDefaults: assigneeAgentId ? { assigneeAgentId } : {},
    id: assigneeAgentId ? `assignee:${assigneeAgentId}` : "assignee:unassigned",
    issues: issues.filter(
      (issue) => (issue.assignee_agent_id?.trim() ?? "") === assigneeAgentId
    ),
    label: assigneeAgentId
      ? issueAssigneeLabel(agents, assigneeAgentId)
      : "Unassigned",
  }));
}

function projectBoardColumns(
  issues: IssueRecord[],
  agents: AgentRecord[],
  grouping: DashboardProjectGrouping
): DashboardProjectColumn[] {
  switch (grouping) {
    case "priority":
      return projectBoardColumnsByPriority(issues);
    case "assignee":
      return projectBoardColumnsByAssignee(issues, agents);
    default:
      return projectBoardColumnsByStatus(issues);
  }
}

function buildDashboardProjectColumns(
  projects: ProjectRecord[],
  issues: IssueRecord[],
  agents: AgentRecord[],
  projectViews: NonNullable<DesktopSettings["dashboard_project_views"]>
): DashboardProjectColumnLayout[] {
  const gridColumnCount = projects.length <= 1 ? 1 : 2;
  const projectColumnDrafts = projects.map((project) => {
    const projectViewSettings = projectViews[project.id] ?? {};
    const projectIssues = issues.filter(
      (issue) => issue.project_id === project.id
    );
    const boards = buildDashboardProjectColumnBoards(
      project,
      projectIssues,
      agents,
      projectViewSettings
    );
    const width = Math.max(
      ...boards.map((board) => board.width),
      dashboardProjectBoardMinWidth
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
      projectColumnDrafts.reduce((maxWidth, projectColumn, columnIndexInDraft) => {
        if (columnIndexInDraft % gridColumnCount !== columnIndex) {
          return maxWidth;
        }

        return Math.max(maxWidth, projectColumn.width);
      }, dashboardProjectBoardMinWidth)
  );
  const rowHeights = Array.from({ length: rowCount }, (_, rowIndex) =>
    projectColumnDrafts.reduce((maxHeight, projectColumn, columnIndexInDraft) => {
      if (Math.floor(columnIndexInDraft / gridColumnCount) !== rowIndex) {
        return maxHeight;
      }

      return Math.max(maxHeight, projectColumn.height);
    }, dashboardProjectBoardHeight + dashboardProjectAddViewSlotHeight)
  );
  const columnOffsets = columnWidths.map((_, columnIndex) => {
    if (columnIndex === 0) {
      return 120;
    }

    return (
      columnWidths
        .slice(0, columnIndex)
        .reduce((total, width) => total + width + dashboardProjectBoardGapX, 120)
    );
  });
  const rowOffsets = rowHeights.map((_, rowIndex) => {
    if (rowIndex === 0) {
      return 104;
    }

    return (
      rowHeights
        .slice(0, rowIndex)
        .reduce((total, height) => total + height + dashboardProjectBoardGapY, 104)
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

function projectBoardCardMeta(
  grouping: DashboardProjectGrouping,
  issue: IssueRecord,
  agents: AgentRecord[]
) {
  switch (grouping) {
    case "priority":
      return [
        humanizeIssueValue(issue.status),
        issueAssigneeLabel(agents, issue.assignee_agent_id),
      ];
    case "assignee":
      return [
        humanizeIssueValue(issue.status),
        humanizeIssueValue(issue.priority),
      ];
    default:
      return [
        humanizeIssueValue(issue.priority),
        issueAssigneeLabel(agents, issue.assignee_agent_id),
      ];
  }
}

function buildDashboardCanvasBounds(
  projectColumns: DashboardProjectColumnLayout[]
) {
  if (!projectColumns.length) {
    return { width: 2200, height: 1600 };
  }

  const maxRight = Math.max(
    ...projectColumns.map((projectColumn) => projectColumn.left + projectColumn.width)
  );
  const maxBottom = Math.max(
    ...projectColumns.map((projectColumn) => projectColumn.top + projectColumn.height)
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
  canvasBounds: { height: number; width: number }
) {
  const edgePadding = 120;
  const minX = Math.min(
    edgePadding,
    viewportWidth - canvasBounds.width + edgePadding
  );
  const minY = Math.min(
    edgePadding,
    viewportHeight - canvasBounds.height + edgePadding
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

function buildDashboardProjectColumnBoards(
  project: ProjectRecord,
  issues: IssueRecord[],
  agents: AgentRecord[],
  viewSettings: NonNullable<DesktopSettings["dashboard_project_views"]>[string]
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
      })
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
  const columns = projectBoardColumns(issues, agents, grouping);

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
    | undefined
) {
  return (views ?? []).filter(
    (
      view
    ): view is {
      group_by?: DashboardProjectGrouping | null;
      id: string;
      name?: string | null;
    } => Boolean(view?.id)
  );
}

function dashboardProjectViewName(
  value: string | null | undefined,
  index: number
) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : `View ${index + 1}`;
}

function nextDashboardProjectViewName(boards: DashboardProjectBoardLayout[]) {
  return `View ${boards.filter((board) => !board.isDefaultView).length + 1}`;
}

function nextDashboardProjectViewGrouping(
  boards: DashboardProjectBoardLayout[]
): DashboardProjectGrouping {
  const usedGroupings = new Set(boards.map((board) => board.grouping));

  return (
    dashboardProjectGroupingOptions.find(
      (grouping) => !usedGroupings.has(grouping)
    ) ?? "status"
  );
}

function createDashboardProjectViewId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
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
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (match) => match.toUpperCase());
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
  projectId?: string | null
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

function deriveProjectName(repoPath: string) {
  const trimmedPath = repoPath.trim();
  if (!trimmedPath) {
    return "";
  }

  const parts = trimmedPath.split("/").filter(Boolean);
  return parts.at(-1)?.trim() ?? "";
}

function issueAssigneeLabel(
  agents: AgentRecord[],
  assigneeAgentId?: string | null
) {
  if (!assigneeAgentId) {
    return "Unassigned";
  }

  const agent = agents.find((entry) => entry.id === assigneeAgentId);
  return agent?.name || agent?.title || agent?.role || assigneeAgentId;
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
  parentIssueId?: string | null
) {
  if (!parentIssueId) {
    return "No parent issue";
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
    ["day", 86400],
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
      return "Working on the issue";
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
      return "Issue Assigned";
    case "issue_status_changed":
      return "Issue Status Changed";
    case "issue_checked_out":
      return "Issue Checked Out";
    case "issue_commented":
      return "Issue Commented";
    case "issue_comment_mentioned":
      return "Issue Comment Mentioned";
    case "issue_reopened_via_comment":
      return "Issue Reopened";
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
    return issueAssigneeLabel(agents, issue.created_by_agent_id);
  }

  if (issue.created_by_user_id) {
    return issue.created_by_user_id === "local-board"
      ? "Board"
      : issue.created_by_user_id;
  }

  return "Board";
}

function agentRunEventLabel(eventType: string) {
  return humanizeIssueValue(eventType);
}

function formatRelativeAgentRunDate(value: string | null | undefined) {
  const date = parseIssueDate(value);
  if (!date) {
    return "Unknown";
  }

  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const deltaSeconds = Math.round((date.getTime() - Date.now()) / 1000);
  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["day", 86400],
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
    return "No company cap";
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
  ceoAgentId: string | null
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
  ceoAgentId: string | null
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
  ceoAgentId: string | null
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
    lineage: Set<string>
  ): OrgHierarchyNode => {
    if (lineage.has(agent.id)) {
      return {
        agent,
        leadProjects: sortProjectsForOrg(
          leadProjectsByAgentId.get(agent.id) ?? []
        ),
        reports: [],
        totalReports: 0,
      };
    }

    const nextLineage = new Set(lineage);
    nextLineage.add(agent.id);
    const reports = sortAgentsForOrg(
      childrenByManagerId.get(agent.id) ?? [],
      ceoAgentId
    ).map((child) => buildNode(child, nextLineage));

    return {
      agent,
      leadProjects: sortProjectsForOrg(
        leadProjectsByAgentId.get(agent.id) ?? []
      ),
      reports,
      totalReports: reports.reduce(
        (count, child) => count + 1 + child.totalReports,
        0
      ),
    };
  };

  return sortAgentsForOrg(roots, ceoAgentId).map((agent) =>
    buildNode(agent, new Set<string>())
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
  projects: ProjectRecord[]
) {
  const agentMap = new Map(agents.map((agent) => [agent.id, agent]));
  const assignments = new Map<string, ProjectRecord[]>();

  for (const project of projects) {
    if (!project.lead_agent_id || !agentMap.has(project.lead_agent_id)) {
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

function sortAgentsForOrg(
  agents: AgentRecord[],
  ceoAgentId: string | null
) {
  return [...agents].sort((left, right) =>
    compareAgentRecordsForOrg(left, right, ceoAgentId)
  );
}

function compareAgentRecordsForOrg(
  left: AgentRecord,
  right: AgentRecord,
  ceoAgentId: string | null
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
      right.name || right.title || right.id
    )
  );
}

function isCeoAgent(
  agent: Pick<AgentRecord, "id" | "role">,
  ceoAgentId: string | null
) {
  if (ceoAgentId) {
    return agent.id === ceoAgentId;
  }

  return agent.role?.toLowerCase() === "ceo";
}

function isOrgRootAgent(
  agent: AgentRecord,
  agentMap: Map<string, AgentRecord>,
  ceoAgentId: string | null
) {
  if (isCeoAgent(agent, ceoAgentId)) {
    return true;
  }

  if (!agent.reports_to || !agentMap.has(agent.reports_to)) {
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
  isRoot: boolean
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
    ["day", 86400],
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
  now = new Date()
) {
  const visibleIssues = issues.filter((issue) => !issue.hidden_at);
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
  now = new Date()
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
    date.getDate()
  );
  const dayDelta = Math.round(
    (startOfNow.getTime() - startOfDate.getTime()) / (24 * 60 * 60 * 1000)
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

function approvalLinksIssue(approval: ApprovalRecord, issueId: string) {
  const payload = approval.payload;
  if (!payload || typeof payload !== "object") {
    return false;
  }

  if (payload.source_issue_id === issueId) {
    return true;
  }

  const sourceIssueIds = payload.source_issue_ids;
  return Array.isArray(sourceIssueIds)
    ? sourceIssueIds.some((value) => value === issueId)
    : false;
}

function buildActivityFeedItems(
  approvals: ApprovalRecord[],
  issues: IssueRecord[],
  issueCommentsByIssueId: Record<string, IssueCommentRecord[]>
) {
  const approvalFeedItems: ActivityFeedItem[] = approvals
    .filter((approval) => approval.status === "pending")
    .map((approval) => ({
      id: `approval-${approval.id}`,
      timestamp: parseIssueDate(approval.updated_at) ?? new Date(0),
      title: humanizeIssueValue(approval.approval_type ?? "approval"),
      subtitle: `Pending approval · ${formatBoardDate(approval.updated_at)}`,
      trailingLabel: approval.status ?? "pending",
      target: { kind: "approval", approvalId: approval.id },
    }));

  const issueActivityFeedItems: ActivityFeedItem[] = issues.flatMap((issue) => {
    const issueTitle = issue.identifier ?? issue.title;
    const comments = issueCommentsByIssueId[issue.id] ?? [];
    const commentItems: ActivityFeedItem[] = comments.map((comment) => ({
      id: `comment-${comment.id}`,
      timestamp: parseIssueDate(comment.created_at) ?? new Date(0),
      title: issueTitle,
      subtitle: `${formatBoardDate(comment.created_at)} · ${comment.body.trim() || "Comment added"}`,
      trailingLabel: "comment",
      target: { kind: "issue", issueId: issue.id },
    }));

    return [
      ...commentItems,
      {
        id: `issue-update-${issue.id}`,
        timestamp: parseIssueDate(issue.updated_at) ?? new Date(0),
        title: issueTitle,
        subtitle: `${formatBoardDate(issue.updated_at)} · ${issueActivitySummary(issue)}`,
        trailingLabel: issue.status,
        target: { kind: "issue", issueId: issue.id },
      },
    ];
  });

  return [...approvalFeedItems, ...issueActivityFeedItems]
    .sort((left, right) => right.timestamp.getTime() - left.timestamp.getTime())
    .slice(0, 50);
}

function issueActivitySummary(issue: IssueRecord) {
  if (issue.completed_at) {
    return "Issue completed";
  }

  if (issue.cancelled_at) {
    return "Issue cancelled";
  }

  if (issue.started_at) {
    return "Work started";
  }

  if (issue.workspace_session_id) {
    return "Worktree attached";
  }

  return "Issue updated";
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
  value: unknown
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
