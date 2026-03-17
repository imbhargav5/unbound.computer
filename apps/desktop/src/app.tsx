import { Terminal } from "@xterm/xterm";
import {
  type FormEvent,
  type MouseEvent,
  type PointerEvent,
  type RefObject,
  type ReactNode,
  type WheelEvent,
  startTransition,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  boardAddIssueComment,
  boardCancelAgentRun,
  boardApproveApproval,
  boardCheckoutIssue,
  boardCompanySnapshot,
  boardCreateCompany,
  boardCreateIssue,
  boardCreateProject,
  boardGetAgentRun,
  boardGetIssue,
  boardListAgentRunEvents,
  boardListAgentRuns,
  boardListCompanies,
  boardListIssueComments,
  boardReadAgentRunLog,
  boardResumeAgentRun,
  boardRetryAgentRun,
  boardUpdateCompany,
  boardUpdateIssue,
  claudeSend,
  claudeStatus,
  desktopBootstrap,
  desktopOpenExternal,
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
  gitUnstage,
  listenToSessionEvents,
  listenToSessionStreamErrors,
  messageList,
  repositoryAdd,
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
  GoalRecord,
  GitStatusFile,
  GitStatusResult,
  IssueCommentRecord,
  IssueRecord,
  ProjectRecord,
  RepositoryRecord,
  SessionMessage,
  SessionRecord,
  SessionStreamPayload,
  WorkspaceRecord,
} from "./lib/types";

type AppScreen =
  | "dashboard"
  | "inbox"
  | "workspaces"
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
  | "repositories"
  | "appearance"
  | "notifications"
  | "privacy";

type ThemeMode = "system" | "light" | "dark";
type FontSizePreset = "small" | "medium" | "large";
type IssuesListTab = "new" | "all";
type IssuesRouteMode = "list" | "detail";
type IssueDetailTab = "conversation" | "runs" | "subissues";
type AgentsRouteMode = "details" | "runs";

interface IssueLinkedRun {
  label: string;
  run: AgentRunRecord;
}

type BoardRootLayout = "companyDashboard" | "workspace" | "settings";
type WorkspaceCenterTab = "conversation" | "terminal" | "preview";
type WorkspaceSidebarTab = "changes" | "files" | "commits";
type CompanyContextMenuScreen =
  | "dashboard"
  | "workspaces"
  | "issues"
  | "companySettings";
type CompanyContextMenuIconKey = CompanyContextMenuScreen | "agents";

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

interface DashboardProjectColumn {
  status: string;
  issues: IssueRecord[];
}

interface DashboardProjectBoardLayout {
  project: ProjectRecord;
  columns: DashboardProjectColumn[];
  left: number;
  top: number;
  issueCount: number;
}

interface CreateIssueDialogDefaults {
  projectId?: string;
  status?: string;
}

interface IssueEditDraft {
  title: string;
  description: string;
  status: string;
  priority: string;
  projectId: string;
  assigneeAgentId: string;
  parentId: string;
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

const primaryBoardSections: Array<{ title: string; screens: AppScreen[] }> = [
  { title: "Work", screens: ["issues", "approvals", "workspaces"] },
  { title: "Projects", screens: ["projects", "goals"] },
];

const companyBoardSection: { title: string; screens: AppScreen[] } = {
  title: "Company",
  screens: ["stats", "activity", "costs", "companySettings"],
};

const settingsSections: Array<{ id: SettingsSection; label: string }> = [
  { id: "general", label: "General" },
  { id: "repositories", label: "Repositories" },
  { id: "appearance", label: "Appearance" },
  { id: "notifications", label: "Notifications" },
  { id: "privacy", label: "Privacy" },
];

const themeModes: ThemeMode[] = ["system", "light", "dark"];
const fontSizePresets: FontSizePreset[] = ["small", "medium", "large"];

const defaultSettings: DesktopSettings = {
  preferred_company_id: null,
  preferred_repository_id: null,
  preferred_view: "dashboard",
  show_raw_message_json: false,
  last_repository_path: null,
  theme_mode: "dark",
  font_size_preset: "medium",
};

const companyContextMenuItems: Array<{
  icon: CompanyContextMenuIconKey;
  label: string;
  screen: CompanyContextMenuScreen;
}> = [
  { icon: "dashboard", label: "Dashboard", screen: "dashboard" },
  { icon: "workspaces", label: "Workspaces", screen: "workspaces" },
  { icon: "issues", label: "Issues", screen: "issues" },
  { icon: "companySettings", label: "Settings", screen: "companySettings" },
];

const defaultDashboardCanvasOffset: DashboardCanvasOffset = {
  x: 96,
  y: 88,
};

const dashboardProjectBoardWidth = 920;
const dashboardProjectBoardHeight = 540;
const dashboardProjectBoardGapX = 88;
const dashboardProjectBoardGapY = 80;

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
    useState<AgentsRouteMode>("details");
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
  const [dependencyCheck, setDependencyCheck] = useState<Record<
    string,
    unknown
  > | null>(null);
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
  const [issueDialogStatus, setIssueDialogStatus] = useState("backlog");
  const [issueDialogProjectId, setIssueDialogProjectId] = useState("");
  const [issueDialogAssigneeAgentId, setIssueDialogAssigneeAgentId] =
    useState("");
  const [issueDialogParentIssueId, setIssueDialogParentIssueId] = useState("");
  const [issueDialogError, setIssueDialogError] = useState<string | null>(null);
  const [isIssueDialogSaving, setIsIssueDialogSaving] = useState(false);
  const [newIssueCommentBody, setNewIssueCommentBody] = useState("");
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
  const boardGoals = companySnapshot?.goals ?? [];
  const selectedGoal =
    boardGoals.find((goal) => goal.id === selectedGoalId) ??
    boardGoals[0] ??
    null;
  const boardProjects = companySnapshot?.projects ?? [];
  const dashboardProjectBoards = useMemo(
    () => buildDashboardProjectBoards(boardProjects, boardIssues),
    [boardIssues, boardProjects]
  );
  const dashboardCanvasBounds = useMemo(
    () => buildDashboardCanvasBounds(dashboardProjectBoards),
    [dashboardProjectBoards]
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
  const selectedAgent =
    (companySnapshot?.agents ?? []).find(
      (agent) => agent.id === selectedAgentId
    ) ??
    companySnapshot?.agents[0] ??
    null;
  const selectedAgentRunIsLive =
    selectedAgentRun?.status === "queued" ||
    selectedAgentRun?.status === "running";
  const selectedCompanyCeo = findCompanyCeo(
    companySnapshot?.agents ?? [],
    selectedCompany?.ceo_agent_id ?? null
  );
  const orderedSidebarAgents = useMemo(
    () =>
      orderSidebarAgents(
        companySnapshot?.agents ?? [],
        typeof selectedCompany?.ceo_agent_id === "string"
          ? selectedCompany.ceo_agent_id
          : null
      ),
    [companySnapshot?.agents, selectedCompany?.ceo_agent_id]
  );
  const activeSession =
    sessions.find((session) => session.id === selectedSessionId) ?? null;
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
    () =>
      mergeIssueOptions(
        ["backlog", "in_progress", "blocked", "done", "cancelled"],
        issueDraft.status
      ),
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
  }, [companySnapshot]);

  useEffect(() => {
    if (issuesRouteMode === "detail" && !selectedIssueId) {
      setIssuesRouteMode("list");
    }
  }, [issuesRouteMode, selectedIssueId]);

  useEffect(() => {
    if (!selectedIssue || issuesRouteMode !== "detail") {
      setNewIssueCommentBody("");
      setIsEditingIssue(false);
      setIssueEditorError(null);
      return;
    }

    let cancelled = false;

    const loadIssueDetailState = async () => {
      try {
        const [freshIssue, comments] = await Promise.all([
          boardGetIssue(selectedIssue.id),
          boardListIssueComments(selectedIssue.id),
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
    selectedAgentIdRef.current = selectedAgent?.id ?? null;
  }, [selectedAgent?.id]);

  useEffect(() => {
    selectedAgentRunIdRef.current = selectedAgentRunId;
  }, [selectedAgentRunId]);

  useEffect(() => {
    if (selectedScreen === "agents") {
      return;
    }

    setAgentsRouteMode("details");
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
          claudeStatus(selectedSessionId),
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
        claudeStatus(sessionId),
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
      setAgentsRouteMode("details");
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
    const menuHeight = 420;
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
    if (!dashboardProjectBoards.length) {
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

  const handleShowAgentRuns = () => {
    setAgentsRouteMode("runs");
  };

  const handleBackToAgentDetails = () => {
    setAgentsRouteMode("details");
    resetAgentRunsState();
  };

  const handleRefreshAgentRuns = async () => {
    await loadAgentRuns(false);
    await refreshSelectedAgentRun(true);
  };

  const handleSelectAgentRun = (runId: string) => {
    setSelectedAgentRunId(runId);
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
    setIssueDialogStatus("backlog");
    setIssueDialogProjectId("");
    setIssueDialogAssigneeAgentId("");
    setIssueDialogParentIssueId("");
    setIssueDialogError(null);
    setIsIssueDialogSaving(false);
  };

  const handleOpenCreateIssueDialog = (
    defaults?: CreateIssueDialogDefaults
  ) => {
    resetIssueDialog();
    setIssueDialogStatus(defaults?.status ?? "backlog");
    setIssueDialogProjectId(defaults?.projectId ?? "");
    setIsCreateIssueDialogOpen(true);
  };

  const handleCloseCreateIssueDialog = () => {
    setIsCreateIssueDialogOpen(false);
    resetIssueDialog();
  };

  const handleCreateIssueFromDialog = async () => {
    if (!selectedCompanyId || !issueDialogTitle.trim() || isIssueDialogSaving) {
      return;
    }

    setIsIssueDialogSaving(true);
    setIssueDialogError(null);

    try {
      const params: Record<string, unknown> = {
        company_id: selectedCompanyId,
        title: issueDialogTitle.trim(),
        status: issueDialogStatus,
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

      const createdIssue = await boardCreateIssue(params);
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setSelectedIssueId(createdIssue.id);
      setIssueDraft(createIssueDraft(createdIssue));
      setIssuesRouteMode("detail");
      setSelectedScreen("issues");
      void persistSettings({
        ...settings,
        preferred_view: preferredViewForScreen("issues"),
      });
      handleCloseCreateIssueDialog();
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

  const handleSaveIssueEdits = async (issue: IssueRecord) => {
    const trimmedTitle = issueDraft.title.trim();
    if (!trimmedTitle) {
      setIssueEditorError("Issue title is required.");
      return;
    }

    setIsSavingIssue(true);
    setIssueEditorError(null);

    try {
      const updatedIssue = await boardUpdateIssue({
        issue_id: issue.id,
        title: trimmedTitle,
        status: issueDraft.status,
        priority: issueDraft.priority,
        description: issueDraft.description.trim()
          ? issueDraft.description.trim()
          : null,
        project_id: issueDraft.projectId.trim() ? issueDraft.projectId : null,
        assignee_agent_id: issueDraft.assigneeAgentId.trim()
          ? issueDraft.assigneeAgentId
          : null,
        parent_id: issueDraft.parentId.trim() ? issueDraft.parentId : null,
      });
      const refreshedSnapshot = await boardCompanySnapshot(issue.company_id);
      setCompanySnapshot(refreshedSnapshot);
      setSelectedIssueId((updatedIssue as IssueRecord).id);
      setIssueDraft(createIssueDraft(updatedIssue as IssueRecord));
      setIsEditingIssue(false);
      setIssuesRouteMode("detail");
    } catch (error) {
      setIssueEditorError(
        error instanceof Error ? error.message : String(error)
      );
    } finally {
      setIsSavingIssue(false);
    }
  };

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

  const handleStartIssueWorkspace = async (issue: IssueRecord) => {
    setIsWorking(true);
    setStatusMessage(null);
    try {
      const workspace = await boardCheckoutIssue(issue.id);
      const [nextRepositories, snapshot] = await Promise.all([
        repositoryList(),
        boardCompanySnapshot(issue.company_id),
      ]);
      setRepositories(nextRepositories as RepositoryRecord[]);
      setCompanySnapshot(snapshot);
      setSelectedBoardWorkspaceId((workspace as WorkspaceRecord).id);
      setSelectedRepositoryId((workspace as WorkspaceRecord).repository_id);
      setSelectedSessionId((workspace as WorkspaceRecord).session_id);
      setSelectedScreen("workspaces");
      setWorkspaceCenterTab("conversation");
      void persistSettings({
        ...settings,
        preferred_repository_id: (workspace as WorkspaceRecord).repository_id,
        preferred_view: preferredViewForScreen("workspaces"),
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleApproveApproval = async (approvalId: string) => {
    if (!selectedCompanyId) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      const approval = await boardApproveApproval({
        approval_id: approvalId,
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

  const handleRunClaude = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedSessionId || !prompt.trim()) {
      return;
    }

    setIsWorking(true);
    setStatusMessage(null);
    try {
      await claudeSend(selectedSessionId, prompt.trim());
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

  const createCompany = async (name: string) => {
    setIsWorking(true);
    try {
      await boardCreateCompany({ name });
      const nextCompanies = (await boardListCompanies()) as Company[];
      setCompanies(nextCompanies);
      setSelectedCompanyId(nextCompanies[0]?.id ?? null);
      setSelectedScreen("dashboard");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleAddRepository = async () => {
    setStatusMessage(null);
    try {
      const path = await desktopPickRepositoryDirectory();
      if (!path) {
        return;
      }

      await repositoryAdd(path);
      const nextRepositories = (await repositoryList()) as RepositoryRecord[];
      setRepositories(nextRepositories);
      const latestRepository = nextRepositories.find(
        (repository) => repository.path === path
      );
      setSelectedRepositoryId(
        latestRepository?.id ?? nextRepositories[0]?.id ?? null
      );

      await persistSettings({
        ...settings,
        last_repository_path: path,
      });
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
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
            Checking for a compatible daemon and loading your local workspace.
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
          {companies.map((company) => (
            <button
              aria-label={company.name}
              className={
                company.id === selectedCompanyId
                  ? "company-rail-button active"
                  : "company-rail-button"
              }
              key={company.id}
              onClick={() => handleSelectCompany(company.id)}
              onContextMenu={(event) =>
                handleOpenCompanyContextMenu(event, company)
              }
              title={company.name}
              type="button"
            >
              {company.name.slice(0, 1).toUpperCase()}
            </button>
          ))}
          <button
            className="company-rail-button add"
            onClick={() => {
              const name = window.prompt("Company name");
              if (name?.trim()) {
                void createCompany(name.trim());
              }
            }}
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
                    label="Dashboard"
                    onClick={() => handleSelectScreen("dashboard")}
                  />
                  <BoardSidebarButton
                    active={selectedScreen === "inbox"}
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
                        {agent.name || agent.title || agent.role || agent.id}
                      </button>
                    ))
                  ) : (
                    <div className="agent-sidebar-empty">No agents yet</div>
                  )}
                </div>

                <div className="board-sidebar-section">
                  <span className="sidebar-section-title">
                    {companyBoardSection.title}
                  </span>
                  {companyBoardSection.screens.map((screen) => (
                    <BoardSidebarButton
                      active={selectedScreen === screen}
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
                agents={companySnapshot?.agents ?? []}
                canvasBounds={dashboardCanvasBounds}
                canvasOffset={dashboardCanvasOffset}
                isDragging={isDashboardCanvasDragging}
                onCreateProject={handleOpenCreateProjectDialog}
                onOpenIssue={(issueId) => void handleSelectIssue(issueId)}
                onPointerCancel={handleDashboardCanvasPointerEnd}
                onPointerDown={handleDashboardCanvasPointerDown}
                onPointerMove={handleDashboardCanvasPointerMove}
                onPointerUp={handleDashboardCanvasPointerEnd}
                onCreateIssueForColumn={(projectId, status) =>
                  handleOpenCreateIssueDialog({ projectId, status })
                }
                projectBoards={dashboardProjectBoards}
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

            {selectedScreen === "agents" ? (
              <AgentsRouteView
                agents={companySnapshot?.agents ?? []}
                agentRunError={agentRunError}
                agentRunEvents={agentRunEvents}
                agentRunLogContent={agentRunLogContent}
                agentRuns={agentRuns}
                companyName={selectedCompany?.name ?? "Unbound"}
                isLoadingAgentRunDetail={isLoadingAgentRunDetail}
                isLoadingAgentRuns={isLoadingAgentRuns}
                isPerformingAgentRunAction={isPerformingAgentRunAction}
                mode={agentsRouteMode}
                onBackToAgentDetails={handleBackToAgentDetails}
                onCancelSelectedRun={() => void handleCancelSelectedAgentRun()}
                onRefreshRuns={() => void handleRefreshAgentRuns()}
                onResumeSelectedRun={() => void handleResumeSelectedAgentRun()}
                onRetrySelectedRun={() => void handleRetrySelectedAgentRun()}
                onSelectAgent={handleSelectAgent}
                onSelectRun={handleSelectAgentRun}
                onShowRuns={handleShowAgentRuns}
                selectedAgent={selectedAgent}
                selectedAgentId={selectedAgentId}
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
                  availablePriorityOptions={issuePriorityOptions}
                  availableStatusOptions={issueStatusOptions}
                  canStartWorkspace={
                    Boolean(selectedIssue.assignee_agent_id) &&
                    Boolean(selectedIssue.project_id) &&
                    !isEditingIssue
                  }
                  comments={selectedIssueComments}
                  isSavingIssue={isSavingIssue}
                  isWorking={isWorking}
                  issue={selectedIssue}
                  issueDraft={issueDraft}
                  issueEditorError={issueEditorError}
                  isEditingIssue={isEditingIssue}
                  linkedApprovals={linkedIssueApprovals}
                  newCommentBody={newIssueCommentBody}
                  onAddComment={() => void handleAddIssueComment(selectedIssue)}
                  onBack={() => handleShowIssuesList()}
                  onBeginEditing={() => beginEditingIssue(selectedIssue)}
                  onCancelEditing={() => discardIssueEdits(selectedIssue)}
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
                  onNewCommentBodyChange={setNewIssueCommentBody}
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
                  onStartWorkspace={() =>
                    void handleStartIssueWorkspace(selectedIssue)
                  }
                  parentIssueLabel={(parentIssueId) =>
                    issueParentLabel(boardIssues, parentIssueId)
                  }
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
                goals={boardGoals}
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
                <h2>Workspaces</h2>
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
                <h3>No active workspaces</h3>
                <p>
                  Workspaces appear automatically when an assigned agent starts
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
                      {selectedBoardWorkspace.issue_identifier ?? "Workspace"}
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
                      label="Claude"
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

                    <form className="composer" onSubmit={handleRunClaude}>
                      <textarea
                        onChange={(event) => setPrompt(event.target.value)}
                        placeholder="Send a prompt to Claude for the selected session"
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
                <h3>Select a workspace</h3>
                <p>
                  Issue-owned coding sessions appear here. The main repo path is
                  used directly.
                </p>
              </section>
            )}
          </main>

          <aside className="workspace-inspector">
            {selectedBoardWorkspace ? (
              <section className="inspector-panel workspace-details-panel">
                <h3>Workspace Details</h3>
                <div className="workspace-detail-grid">
                  <DetailRow
                    label="Issue"
                    value={
                      selectedBoardWorkspace.issue_identifier ??
                      selectedBoardWorkspace.issue_id ??
                      "Missing"
                    }
                  />
                  <DetailRow
                    label="Agent"
                    value={
                      selectedBoardWorkspace.agent_name ??
                      selectedBoardWorkspace.agent_id ??
                      "Missing"
                    }
                  />
                  <DetailRow
                    label="Project"
                    value={
                      selectedBoardWorkspace.project_name ??
                      selectedBoardWorkspace.project_id ??
                      "Missing"
                    }
                  />
                  <DetailRow
                    label="Branch"
                    value={selectedBoardWorkspace.workspace_branch ?? "main"}
                  />
                  <DetailRow
                    label="Repo"
                    value={
                      selectedBoardWorkspace.workspace_repo_path ?? "Missing"
                    }
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
                      {currentBranch.ahead > 0 && currentBranch.behind > 0
                        ? " "
                        : ""}
                      {currentBranch.behind > 0
                        ? `-${currentBranch.behind}`
                        : ""}
                    </small>
                  ) : null}
                </div>

                <div className="git-sidebar-actions">
                  {hasUncommittedChanges ? (
                    <>
                      <button
                        className="primary-button compact-button"
                        disabled={isWorking || !gitCommitMessage.trim()}
                        onClick={() => void handleGitCommit(false)}
                        type="button"
                      >
                        Commit
                      </button>
                      <button
                        className="secondary-button compact-button"
                        disabled={isWorking || !gitCommitMessage.trim()}
                        onClick={() => void handleGitCommit(true)}
                        type="button"
                      >
                        Commit + Push
                      </button>
                    </>
                  ) : (
                    <button
                      className="primary-button compact-button"
                      disabled={isWorking || !hasUnpushedCommits}
                      onClick={() => void handleGitPush()}
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
                  onClick={() => setWorkspaceSidebarTab("changes")}
                />
                <WorkspaceSidebarTabButton
                  active={workspaceSidebarTab === "files"}
                  label="Files"
                  onClick={() => setWorkspaceSidebarTab("files")}
                />
                <WorkspaceSidebarTabButton
                  active={workspaceSidebarTab === "commits"}
                  label="Commits"
                  onClick={() => setWorkspaceSidebarTab("commits")}
                />
              </div>

              {workspaceSidebarTab === "changes" ? (
                <div className="workspace-sidebar-content">
                  <label className="git-commit-field">
                    <span>Commit message</span>
                    <input
                      onChange={(event) =>
                        setGitCommitMessage(event.target.value)
                      }
                      placeholder="Describe this change"
                      value={gitCommitMessage}
                    />
                  </label>

                  <GitChangeSection
                    activePath={selectedDiff ? selectedFilePath : null}
                    files={(gitState?.files ?? []).filter(
                      (file) => file.staged
                    )}
                    onDiscard={(file) => void handleDiscardFile(file)}
                    onOpen={(file) => void handleOpenDiff(file.path)}
                    onPrimaryAction={(file) => void handleUnstageFile(file)}
                    primaryActionLabel="Unstage"
                    title="Staged"
                  />
                  <GitChangeSection
                    activePath={selectedDiff ? selectedFilePath : null}
                    files={(gitState?.files ?? []).filter(
                      (file) => !file.staged
                    )}
                    onDiscard={(file) => void handleDiscardFile(file)}
                    onOpen={(file) => void handleOpenDiff(file.path)}
                    onPrimaryAction={(file) => void handleStageFile(file)}
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
                          void handleOpenDirectory(parent);
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
                            ? void handleOpenDirectory(entry.path)
                            : void handleOpenFile(entry.path)
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
            </section>
          </aside>
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
                  <section className="settings-inline-panel">
                    <form
                      className="settings-form"
                      onSubmit={handleSettingsSubmit}
                    >
                      <label className="checkbox-row">
                        <input
                          checked={settings.show_raw_message_json}
                          onChange={(event) =>
                            setSettings((current) => ({
                              ...current,
                              show_raw_message_json: event.target.checked,
                            }))
                          }
                          type="checkbox"
                        />
                        <span>
                          Show raw JSON for structured session messages
                        </span>
                      </label>
                      <label>
                        <span>Preferred shell</span>
                        <select
                          onChange={(event) =>
                            setSettings((current) => ({
                              ...current,
                              preferred_view: event.target.value,
                            }))
                          }
                          value={preferredViewSelectValue(
                            settings.preferred_view
                          )}
                        >
                          <option value="dashboard">Dashboard</option>
                          <option value="stats">Stats</option>
                          <option value="activity">Activity</option>
                          <option value="costs">Costs</option>
                          <option value="workspaces">Workspaces</option>
                          <option value="settings">Settings</option>
                        </select>
                      </label>
                      <button className="primary-button" type="submit">
                        Save device settings
                      </button>
                    </form>
                  </section>
                </SettingsSectionBlock>
              </SettingsPageShell>
            ) : null}
            {selectedSettingsSection === "repositories" ? (
              <SettingsPageShell
                subtitle="Manage your registered repositories."
                title="Repositories"
              >
                <section className="settings-inline-panel">
                  <div className="surface-header">
                    <h3>Repositories</h3>
                    <button
                      className="secondary-button"
                      onClick={() => void handleAddRepository()}
                      type="button"
                    >
                      Add repository
                    </button>
                  </div>
                  <div className="surface-list">
                    {repositories.map((repository) => (
                      <div className="surface-list-row" key={repository.id}>
                        <div>
                          <strong>{repository.name}</strong>
                          <span>{repository.path}</span>
                        </div>
                        <button
                          className="secondary-button"
                          onClick={() =>
                            void desktopRevealInFinder(repository.path)
                          }
                          type="button"
                        >
                          Reveal
                        </button>
                      </div>
                    ))}
                  </div>
                </section>
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

      {isCreateIssueDialogOpen ? (
        <CreateIssueDialogView
          agents={companySnapshot?.agents ?? []}
          errorMessage={issueDialogError}
          isSaving={isIssueDialogSaving}
          issues={boardIssues}
          onAssigneeChange={setIssueDialogAssigneeAgentId}
          onClose={handleCloseCreateIssueDialog}
          onCreate={() => void handleCreateIssueFromDialog()}
          onDescriptionChange={setIssueDialogDescription}
          onParentIssueChange={setIssueDialogParentIssueId}
          onPriorityChange={setIssueDialogPriority}
          onProjectChange={setIssueDialogProjectId}
          onTitleChange={setIssueDialogTitle}
          priorities={["low", "medium", "high", "urgent"]}
          projects={boardProjects}
          selectedAssigneeAgentId={issueDialogAssigneeAgentId}
          selectedParentIssueId={issueDialogParentIssueId}
          selectedPriority={issueDialogPriority}
          selectedProjectId={issueDialogProjectId}
          selectedStatus={issueDialogStatus}
          title={issueDialogTitle}
          description={issueDialogDescription}
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

function AgentsRouteView({
  agents,
  agentRunError,
  agentRunEvents,
  agentRunLogContent,
  agentRuns,
  companyName,
  isLoadingAgentRunDetail,
  isLoadingAgentRuns,
  isPerformingAgentRunAction,
  mode,
  onBackToAgentDetails,
  onCancelSelectedRun,
  onRefreshRuns,
  onResumeSelectedRun,
  onRetrySelectedRun,
  onSelectAgent,
  onSelectRun,
  onShowRuns,
  selectedAgent,
  selectedAgentId,
  selectedRun,
}: {
  agents: AgentRecord[];
  agentRunError: string | null;
  agentRunEvents: AgentRunEventRecord[];
  agentRunLogContent: string;
  agentRuns: AgentRunRecord[];
  companyName: string;
  isLoadingAgentRunDetail: boolean;
  isLoadingAgentRuns: boolean;
  isPerformingAgentRunAction: boolean;
  mode: AgentsRouteMode;
  onBackToAgentDetails: () => void;
  onCancelSelectedRun: () => void;
  onRefreshRuns: () => void;
  onResumeSelectedRun: () => void;
  onRetrySelectedRun: () => void;
  onSelectAgent: (agentId: string) => void;
  onSelectRun: (runId: string) => void;
  onShowRuns: () => void;
  selectedAgent: AgentRecord | null;
  selectedAgentId: string | null;
  selectedRun: AgentRunRecord | null;
}) {
  if (mode === "runs") {
    return (
      <AgentRunsRouteView
        agentRunError={agentRunError}
        agentRunEvents={agentRunEvents}
        agentRunLogContent={agentRunLogContent}
        agentRuns={agentRuns}
        isLoadingAgentRunDetail={isLoadingAgentRunDetail}
        isLoadingAgentRuns={isLoadingAgentRuns}
        isPerformingAgentRunAction={isPerformingAgentRunAction}
        onBack={onBackToAgentDetails}
        onCancelSelectedRun={onCancelSelectedRun}
        onRefreshRuns={onRefreshRuns}
        onResumeSelectedRun={onResumeSelectedRun}
        onRetrySelectedRun={onRetrySelectedRun}
        onSelectRun={onSelectRun}
        selectedAgent={selectedAgent}
        selectedRun={selectedRun}
      />
    );
  }

  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <span className="route-kicker">Agents</span>
        <h1>{selectedAgent?.name ?? "Company roster"}</h1>
        <p>
          Review the selected agent, verify its board wiring, and jump directly
          into its historical runs.
        </p>
      </div>

      <div className="surface-grid">
        <section className="surface-panel wide">
          {selectedAgent ? (
            <>
              <div className="agents-route-header-row">
                <div>
                  <span className="route-kicker">Selected agent</span>
                  <h2>{selectedAgent.name}</h2>
                </div>
                <button
                  className="secondary-button"
                  onClick={onShowRuns}
                  type="button"
                >
                  View runs
                </button>
              </div>

              <div className="summary-grid">
                <SummaryPill
                  label="Role"
                  value={selectedAgent.title ?? selectedAgent.role ?? "Agent"}
                />
                <SummaryPill
                  label="Status"
                  value={String(selectedAgent.status ?? "active")}
                />
                <SummaryPill label="Company" value={companyName} />
              </div>

              <div className="surface-list">
                <DetailRow
                  label="Adapter"
                  value={selectedAgent.adapter_type ?? "Not configured"}
                />
                <DetailRow
                  label="Reports to"
                  value={selectedAgent.reports_to ?? "CEO"}
                />
                <DetailRow
                  label="Home"
                  value={selectedAgent.home_path ?? "Missing"}
                />
                <DetailRow
                  label="Instructions"
                  value={selectedAgent.instructions_path ?? "Missing"}
                />
                <DetailRow
                  label="Monthly budget"
                  value={formatCents(selectedAgent.budget_monthly_cents)}
                />
                <DetailRow
                  label="Monthly spend"
                  value={formatCents(selectedAgent.spent_monthly_cents)}
                />
                <DetailRow
                  label="Last heartbeat"
                  value={formatIssueDate(selectedAgent.last_heartbeat_at)}
                />
              </div>

              {selectedAgent.capabilities ? (
                <section className="agent-run-section">
                  <h3>Capabilities</h3>
                  <p>{selectedAgent.capabilities}</p>
                </section>
              ) : null}

              {selectedAgent.metadata ? (
                <section className="agent-run-section">
                  <h3>Metadata</h3>
                  <pre className="agent-run-json-block">
                    {formatJsonBlock(selectedAgent.metadata)}
                  </pre>
                </section>
              ) : null}
            </>
          ) : (
            <p>No agents are available for this company yet.</p>
          )}
        </section>

        <section className="surface-panel">
          <div className="surface-header">
            <h3>Roster</h3>
          </div>
          {agents.length ? (
            <div className="surface-list">
              {agents.map((agent) => (
                <button
                  className={
                    agent.id === selectedAgentId
                      ? "file-list-button active"
                      : "file-list-button"
                  }
                  key={agent.id}
                  onClick={() => onSelectAgent(agent.id)}
                  type="button"
                >
                  <strong>{agent.name}</strong>
                  <span>{agent.title ?? agent.role ?? "Agent"}</span>
                </button>
              ))}
            </div>
          ) : (
            <p className="surface-empty-copy">
              No agents have been created for this company yet.
            </p>
          )}
        </section>
      </div>
    </section>
  );
}

function AgentRunsRouteView({
  agentRunError,
  agentRunEvents,
  agentRunLogContent,
  agentRuns,
  isLoadingAgentRunDetail,
  isLoadingAgentRuns,
  isPerformingAgentRunAction,
  onBack,
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
  onBack: () => void;
  onCancelSelectedRun: () => void;
  onRefreshRuns: () => void;
  onResumeSelectedRun: () => void;
  onRetrySelectedRun: () => void;
  onSelectRun: (runId: string) => void;
  selectedAgent: AgentRecord | null;
  selectedRun: AgentRunRecord | null;
}) {
  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <button className="issues-back-button" onClick={onBack} type="button">
          <span>‹</span>
          <span>Back to Agent</span>
        </button>
        <span className="route-kicker">Agent runs</span>
        <div className="agents-route-header-row">
          <div>
            <h1>
              {selectedAgent
                ? `${selectedAgent.name} run history`
                : "Run history"}
            </h1>
            <p>
              Queued, running, and completed runs for this agent appear here.
            </p>
          </div>
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
        </div>
      </div>

      {!selectedAgent ? (
        <div className="surface-grid single">
          <section className="surface-panel">
            <p>Select an agent to review its runs.</p>
          </section>
        </div>
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
                        Cancel
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
    </section>
  );
}

function RunStatusBadge({ status }: { status: string }) {
  return (
    <span className={`agent-run-status-badge ${agentRunStatusTone(status)}`}>
      {agentRunStatusLabel(status)}
    </span>
  );
}

function BoardSidebarButton({
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
      className={
        active ? "board-sidebar-button active" : "board-sidebar-button"
      }
      onClick={onClick}
      type="button"
    >
      {label}
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
  onWheel,
  projectBoards,
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
  onCreateIssueForColumn: (projectId: string, status: string) => void;
  onWheel: (event: WheelEvent<HTMLDivElement>) => void;
  projectBoards: DashboardProjectBoardLayout[];
  viewportRef: RefObject<HTMLDivElement | null>;
}) {
  return (
    <section className="dashboard-canvas-route">
      {projectBoards.length ? (
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
            {projectBoards.map((projectBoard) => (
              <article
                className="project-kanban-board"
                key={projectBoard.project.id}
                style={{
                  left: projectBoard.left,
                  top: projectBoard.top,
                }}
              >
                <div className="project-kanban-board-header">
                  <div>
                    <span className="project-kanban-board-kicker">
                      {humanizeIssueValue(
                        projectBoard.project.status ?? "planned"
                      )}
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
                  <div className="project-kanban-board-meta">
                    <span>{projectBoard.issueCount} issues</span>
                    <span>
                      {projectBoard.project.target_date
                        ? `Target ${formatShortDate(projectBoard.project.target_date)}`
                        : "No target date"}
                    </span>
                  </div>
                </div>

                <div className="project-kanban-columns">
                  {projectBoard.columns.map((column) => {
                    const createIssueCard = (
                      <button
                        className="project-kanban-column-create"
                        onClick={() =>
                          onCreateIssueForColumn(
                            projectBoard.project.id,
                            column.status
                          )
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
                          <small>
                            Add work directly to{" "}
                            {humanizeIssueValue(column.status)}
                          </small>
                        </span>
                      </button>
                    );

                    return (
                      <section
                        className="project-kanban-column"
                        key={column.status}
                      >
                        <div className="project-kanban-column-header">
                          <div className="project-kanban-column-header-copy">
                            <span>{humanizeIssueValue(column.status)}</span>
                            <strong>{column.issues.length}</strong>
                          </div>
                        </div>

                        <div className="project-kanban-cards">
                          {column.issues.length ? (
                            <>
                              {column.issues.map((issue) => (
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
                                  <div className="project-kanban-card-meta">
                                    <span>
                                      {humanizeIssueValue(issue.priority)}
                                    </span>
                                    <span>
                                      {issueAssigneeLabel(
                                        agents,
                                        issue.assignee_agent_id
                                      )}
                                    </span>
                                  </div>
                                </button>
                              ))}
                              {createIssueCard}
                            </>
                          ) : (
                            <>
                              {createIssueCard}
                              <div className="project-kanban-column-empty">
                                No issues yet
                              </div>
                            </>
                          )}
                        </div>
                      </section>
                    );
                  })}
                </div>
              </article>
            ))}
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
  dependencyCheck: Record<string, unknown> | null;
  onCheckDependencies: () => void;
  onOpenWorkspace: (workspace: WorkspaceRecord) => void;
  repositoriesCount: number;
  snapshot: CompanySnapshot | null;
}) {
  return (
    <section className="route-scroll">
      <div className="route-header">
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
          label="Workspaces"
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
            <pre>{JSON.stringify(dependencyCheck, null, 2)}</pre>
          ) : null}
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
              Projects define the main repo path for workspaces.
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
          <h3>Active Workspaces</h3>
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
                    "workspace"}
                </span>
              </button>
            ))}
          </div>
        </section>
      </div>
    </section>
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
          <span>ISSUES</span>
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
                    className="issues-list-row-title"
                    style={{
                      paddingLeft: `${20 + issue.request_depth * 12}px`,
                    }}
                  >
                    {issuesListRowTitle(issue)}
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
              Issues own workspaces. Create one from the sidebar to start agent
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
  isEditingIssue,
  isSavingIssue,
  isWorking,
  canStartWorkspace,
  availableStatusOptions,
  availablePriorityOptions,
  projects,
  agents,
  selectableParentIssues,
  linkedApprovals,
  subissues,
  comments,
  issueEditorError,
  newCommentBody,
  onBack,
  onBeginEditing,
  onCancelEditing,
  onSave,
  onStartWorkspace,
  onIssueDraftChange,
  onProjectSelect,
  onParentIssueSelect,
  onLinkedApprovalSelect,
  onNewCommentBodyChange,
  onAddComment,
  projectLabel,
  assigneeLabel,
  parentIssueLabel,
  priorityLabel,
}: {
  issue: IssueRecord;
  issueDraft: IssueEditDraft;
  isEditingIssue: boolean;
  isSavingIssue: boolean;
  isWorking: boolean;
  canStartWorkspace: boolean;
  availableStatusOptions: string[];
  availablePriorityOptions: string[];
  projects: ProjectRecord[];
  agents: AgentRecord[];
  selectableParentIssues: IssueRecord[];
  linkedApprovals: ApprovalRecord[];
  subissues: IssueRecord[];
  comments: IssueCommentRecord[];
  issueEditorError: string | null;
  newCommentBody: string;
  onBack: () => void;
  onBeginEditing: () => void;
  onCancelEditing: () => void;
  onSave: () => void;
  onStartWorkspace: () => void;
  onIssueDraftChange: (patch: Partial<IssueEditDraft>) => void;
  onProjectSelect: (projectId: string) => void;
  onParentIssueSelect: (parentIssueId: string) => void;
  onLinkedApprovalSelect: (approvalId: string) => void;
  onNewCommentBodyChange: (value: string) => void;
  onAddComment: () => void;
  projectLabel: (projectId?: string | null) => string;
  assigneeLabel: (assigneeAgentId?: string | null) => string;
  parentIssueLabel: (parentIssueId?: string | null) => string;
  priorityLabel: (value: string) => string;
}) {
  const canSaveIssueEdits =
    !isSavingIssue && issueDraft.title.trim().length > 0;
  const [activeTab, setActiveTab] = useState<IssueDetailTab>("conversation");
  const [linkedRuns, setLinkedRuns] = useState<IssueLinkedRun[]>([]);
  const [isLoadingLinkedRuns, setIsLoadingLinkedRuns] = useState(false);
  const [linkedRunsError, setLinkedRunsError] = useState<string | null>(null);

  useEffect(() => {
    setActiveTab("conversation");

    const runLabelsById = new Map<string, string[]>();
    const pushRunLabel = (runId: string | null | undefined, label: string) => {
      if (!runId) {
        return;
      }

      const labels = runLabelsById.get(runId);
      if (labels) {
        labels.push(label);
        return;
      }

      runLabelsById.set(runId, [label]);
    };

    pushRunLabel(issue.checkout_run_id, "Checkout Run");
    pushRunLabel(issue.execution_run_id, "Execution Run");

    const runRequests = Array.from(runLabelsById.entries()).map(
      ([runId, labels]) => ({
        runId,
        label: labels.join(" / "),
      })
    );

    if (!runRequests.length) {
      setLinkedRuns([]);
      setLinkedRunsError(null);
      setIsLoadingLinkedRuns(false);
      return;
    }

    let cancelled = false;
    setIsLoadingLinkedRuns(true);

    void Promise.allSettled(
      runRequests.map(async ({ runId, label }) => ({
        label,
        run: await boardGetAgentRun(runId),
      }))
    )
      .then((results) => {
        if (cancelled) {
          return;
        }

        const nextLinkedRuns: IssueLinkedRun[] = [];
        const failedLabels: string[] = [];

        results.forEach((result, index) => {
          if (result.status === "fulfilled") {
            nextLinkedRuns.push(result.value);
            return;
          }

          failedLabels.push(runRequests[index]?.label ?? "Run");
        });

        startTransition(() => {
          setLinkedRuns(nextLinkedRuns);
          setLinkedRunsError(
            failedLabels.length
              ? `Could not load ${failedLabels.join(" or ")}.`
              : null
          );
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

  return (
    <section className="route-scroll issues-detail-route">
      <div className="route-header compact">
        <button className="issues-back-button" onClick={onBack} type="button">
          <span>‹</span>
          <span>Back to Issues</span>
        </button>
        <span className="route-kicker">Issues</span>
        <h1>Issue Details</h1>
      </div>

      <div className="issues-detail-layout">
        <section className="surface-panel issues-detail-panel issues-detail-main-panel">
          <div className="issues-detail-title-row">
            <div className="issues-detail-title-block">
              <span className="route-kicker">
                {issue.identifier ?? issue.title}
              </span>
              <h2>{isEditingIssue ? "Edit Issue" : issue.title}</h2>
              {isEditingIssue ? (
                <p className="issues-edit-subtitle">
                  Update the issue title, routing, ownership, and execution
                  context from the editor body and the properties rail.
                </p>
              ) : issue.description ? (
                <p className="issues-detail-copy muted">
                  Keep the main thread focused on context, discussion, and
                  related work while the right rail owns the issue properties.
                </p>
              ) : null}
            </div>
          </div>

          {isEditingIssue ? (
            <section className="issue-edit-shell">
              <div className="issue-dialog-context">
                <div className="issue-dialog-context-chip">
                  <span className="issue-dialog-context-label">Issue</span>
                  <strong>{issue.identifier ?? issue.id}</strong>
                </div>
                <div className="issue-dialog-context-chip">
                  <span className="issue-dialog-context-label">
                    Current status
                  </span>
                  <strong>{priorityLabel(issue.status)}</strong>
                </div>
                <div className="issue-dialog-context-chip">
                  <span className="issue-dialog-context-label">
                    Current priority
                  </span>
                  <strong>{priorityLabel(issue.priority)}</strong>
                </div>
              </div>

              <label className="issue-dialog-field issue-dialog-field-full">
                <span className="issue-dialog-label">Title</span>
                <input
                  className="issue-dialog-input issue-edit-title-input"
                  onChange={(event) =>
                    onIssueDraftChange({
                      title: event.target.value,
                    })
                  }
                  placeholder="Issue title"
                  value={issueDraft.title}
                />
                <small className="issue-dialog-hint">
                  This is the main issue title and the default workspace label.
                </small>
              </label>

              <label className="issue-dialog-field issue-dialog-field-full">
                <span className="issue-dialog-label">Description</span>
                <textarea
                  className="issue-dialog-input issue-dialog-textarea issue-edit-description-input"
                  onChange={(event) =>
                    onIssueDraftChange({
                      description: event.target.value,
                    })
                  }
                  placeholder="What needs to happen, what context matters, and what should the assignee do next?"
                  value={issueDraft.description}
                />
                <small className="issue-dialog-hint">
                  Background, acceptance criteria, and bootstrap instructions
                  all live here.
                </small>
              </label>

              {issueEditorError ? (
                <div className="issue-dialog-alert">{issueEditorError}</div>
              ) : null}

              <div className="issue-edit-footer">
                <button
                  className="secondary-button"
                  disabled={isSavingIssue}
                  onClick={onCancelEditing}
                  type="button"
                >
                  Cancel
                </button>
                <button
                  className="primary-button"
                  disabled={!canSaveIssueEdits}
                  onClick={onSave}
                  type="button"
                >
                  {isSavingIssue ? "Saving..." : "Save Changes"}
                </button>
              </div>
            </section>
          ) : issue.description ? (
            <section className="issues-detail-section">
              <h3>Description</h3>
              <p className="issues-detail-copy">{issue.description}</p>
            </section>
          ) : (
            <section className="issues-detail-section">
              <h3>Description</h3>
              <p className="issues-detail-copy muted">
                No description yet. Add context here so the assignee and future
                runs have the full brief.
              </p>
            </section>
          )}

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
                  {comments.length ? (
                    <div className="issues-comment-list">
                      {comments.map((comment) => (
                        <article
                          className="issues-comment-card"
                          key={comment.id}
                        >
                          <p>{comment.body}</p>
                          <span>{formatIssueDate(comment.created_at)}</span>
                        </article>
                      ))}
                    </div>
                  ) : (
                    <p className="issues-detail-copy muted">No comments yet.</p>
                  )}

                  <div className="issues-comment-composer">
                    <textarea
                      onChange={(event) =>
                        onNewCommentBodyChange(event.target.value)
                      }
                      placeholder="Add a comment"
                      value={newCommentBody}
                    />
                    <button
                      className="secondary-button"
                      disabled={isWorking || !newCommentBody.trim()}
                      onClick={onAddComment}
                      type="button"
                    >
                      Add Comment
                    </button>
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
                        <article
                          className="issues-linked-run-card"
                          key={`${label}-${run.id}`}
                        >
                          <div className="issues-linked-run-header">
                            <div className="issues-linked-run-heading">
                              <span className="issues-linked-run-label">
                                {label}
                              </span>
                              <strong>{shortAgentRunTitle(run.id)}</strong>
                            </div>
                            <RunStatusBadge status={run.status} />
                          </div>
                          <p className="issues-linked-run-summary">
                            {agentRunSummary(run)}
                          </p>
                          <div className="issues-linked-run-meta">
                            <span>
                              {agentRunInvocationSourceLabel(
                                run.invocation_source
                              )}
                            </span>
                            <span>
                              {formatRelativeAgentRunDate(run.created_at)}
                            </span>
                            {run.wake_reason ? (
                              <span>
                                {agentRunWakeReasonLabel(run.wake_reason)}
                              </span>
                            ) : null}
                          </div>
                        </article>
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
                          {priorityLabel(child.status)}
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

        <aside className="surface-panel issues-detail-sidebar-panel">
          {!isEditingIssue ? (
            <section className="issues-sidebar-section">
              <h3>Actions</h3>
              <div className="issues-sidebar-actions">
                {canStartWorkspace ? (
                  <button
                    className="primary-button"
                    disabled={isWorking}
                    onClick={onStartWorkspace}
                    type="button"
                  >
                    Start Workspace
                  </button>
                ) : null}
                <button
                  className="secondary-button"
                  onClick={onBeginEditing}
                  type="button"
                >
                  Edit Issue
                </button>
              </div>
            </section>
          ) : (
            <section className="issues-sidebar-section">
              <h3>Editing</h3>
              <p className="issues-detail-copy muted">
                Linear-style issue properties live in the right rail while you
                edit the core brief on the left.
              </p>
            </section>
          )}

          <section className="issues-sidebar-section">
            <h3>Properties</h3>
            {isEditingIssue ? (
              <div className="issues-sidebar-fields">
                <IssueDialogSelectField
                  hint="Moves the issue through the board lifecycle."
                  label="Status"
                  onChange={(value) =>
                    onIssueDraftChange({
                      status: value,
                    })
                  }
                  value={issueDraft.status}
                >
                  {availableStatusOptions.map((status) => (
                    <option key={status} value={status}>
                      {priorityLabel(status)}
                    </option>
                  ))}
                </IssueDialogSelectField>

                <IssueDialogSelectField
                  hint="Controls ordering and urgency in issue views."
                  label="Priority"
                  onChange={(value) =>
                    onIssueDraftChange({
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
                </IssueDialogSelectField>

                <IssueDialogSelectField
                  hint="Optional project anchor for execution routing and repo context."
                  label="Project"
                  onChange={onProjectSelect}
                  value={issueDraft.projectId}
                >
                  <option value="">No project</option>
                  {projects.map((project) => (
                    <option key={project.id} value={project.id}>
                      {project.name ?? project.title ?? project.id}
                    </option>
                  ))}
                </IssueDialogSelectField>

                <IssueDialogSelectField
                  hint="Choose the agent who owns this work."
                  label="Assignee"
                  onChange={(value) =>
                    onIssueDraftChange({
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
                </IssueDialogSelectField>

                <IssueDialogSelectField
                  hint="Nest the issue under another issue or clear the parent."
                  label="Parent Issue"
                  onChange={onParentIssueSelect}
                  value={issueDraft.parentId}
                >
                  <option value="">No parent issue</option>
                  {selectableParentIssues.map((parentIssue) => (
                    <option key={parentIssue.id} value={parentIssue.id}>
                      {parentIssue.identifier ?? parentIssue.title}
                    </option>
                  ))}
                </IssueDialogSelectField>
              </div>
            ) : (
              <div className="surface-list">
                <DetailRow label="Status" value={priorityLabel(issue.status)} />
                <DetailRow
                  label="Priority"
                  value={priorityLabel(issue.priority)}
                />
                <DetailRow
                  label="Project"
                  value={projectLabel(issue.project_id)}
                />
                <DetailRow
                  label="Assignee"
                  value={assigneeLabel(issue.assignee_agent_id)}
                />
                <DetailRow
                  label="Parent"
                  value={parentIssueLabel(issue.parent_id)}
                />
              </div>
            )}
          </section>

          <section className="issues-sidebar-section">
            <h3>Metadata</h3>
            <div className="surface-list">
              <DetailRow label="Issue" value={issue.identifier ?? issue.id} />
              <DetailRow label="Depth" value={String(issue.request_depth)} />
              <DetailRow
                label="Created"
                value={formatBoardDate(issue.created_at)}
              />
              <DetailRow
                label="Updated"
                value={formatBoardDate(issue.updated_at)}
              />
            </div>
          </section>

          {linkedApprovals.length ? (
            <section className="issues-sidebar-section">
              <h3>Linked Approvals</h3>
              <div className="surface-list dense">
                {linkedApprovals.map((approval) => (
                  <button
                    className="file-list-button"
                    key={approval.id}
                    onClick={() => onLinkedApprovalSelect(approval.id)}
                    type="button"
                  >
                    <strong>
                      {priorityLabel(approval.approval_type ?? "approval")}
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
          ) : null}
        </aside>
      </div>
    </section>
  );
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
  onApprove: (approvalId: string) => void;
}) {
  return (
    <section className="route-scroll">
      <div className="route-header compact">
        <span className="route-kicker">Approvals</span>
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
                    disabled={isWorking}
                    onClick={() => onApprove(currentApproval.id)}
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
  const heartbeatLabel = formatTimestamp(agent.last_heartbeat_at);

  if (heartbeatLabel !== "n/a") {
    secondaryMeta.push(heartbeatLabel);
  }

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
  onSelectProject,
  onOpenCreateProject,
}: {
  projects: ProjectRecord[];
  goals: GoalRecord[];
  currentProject: ProjectRecord | null;
  onSelectProject: (projectId: string) => void;
  onOpenCreateProject: () => void;
}) {
  return (
    <section className="route-scroll">
      <div className="route-header compact projects-route-header">
        <div>
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
            Projects define the main repo anchor that issue workspaces run
            inside.
          </p>
        )}
      </section>

      {currentProject ? (
        <section className="surface-panel projects-panel">
          <div className="surface-header">
            <h3>Project Details</h3>
          </div>

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
        </section>
      ) : (
        <section className="surface-panel projects-panel">
          <div className="surface-header">
            <h3>Project Details</h3>
          </div>
          <div className="workspace-empty-state projects-empty-state-panel">
            <h3>Select a project</h3>
            <p>Project repo-anchor configuration appears here.</p>
          </div>
        </section>
      )}
    </section>
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
        className="project-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-header-copy">
            <span className="project-dialog-badge">PRO</span>
            <h2>New project</h2>
          </div>

          <button
            className="project-dialog-close"
            onClick={onClose}
            type="button"
          >
            ✕
          </button>
        </div>

        <div className="project-dialog-body">
          <div className="project-dialog-divider" />

          <div className="project-folder-row">
            <div className="project-folder-pill">
              <span>{repoPath || "Choose a project folder"}</span>
            </div>

            <button
              className="secondary-button"
              onClick={onChooseFolder}
              type="button"
            >
              Choose folder
            </button>
          </div>

          {errorMessage ? (
            <div className="status-banner">{errorMessage}</div>
          ) : null}

          <div className="project-dialog-controls">
            <div className="project-dialog-chip-row">
              <select
                onChange={(event) => onStatusChange(event.target.value)}
                value={selectedStatus}
              >
                {["planned", "active", "completed"].map((status) => (
                  <option key={status} value={status}>
                    {status}
                  </option>
                ))}
              </select>

              <select
                onChange={(event) => onGoalChange(event.target.value)}
                value={selectedGoalId}
              >
                <option value="">Goal</option>
                {goals.map((goal) => (
                  <option key={goal.id} value={goal.id}>
                    {goal.title}
                  </option>
                ))}
              </select>

              <input
                onChange={(event) => onTargetDateChange(event.target.value)}
                type="date"
                value={targetDate}
              />
            </div>

            <button
              className="project-dialog-create-button"
              disabled={!canCreate}
              onClick={onCreate}
              type="button"
            >
              {isSaving ? "Creating..." : "Create project"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function CreateIssueDialogView({
  title,
  description,
  selectedPriority,
  selectedProjectId,
  selectedStatus,
  selectedAssigneeAgentId,
  selectedParentIssueId,
  priorities,
  projects,
  agents,
  issues,
  isSaving,
  errorMessage,
  onTitleChange,
  onDescriptionChange,
  onPriorityChange,
  onProjectChange,
  onAssigneeChange,
  onParentIssueChange,
  onCreate,
  onClose,
}: {
  title: string;
  description: string;
  selectedPriority: string;
  selectedProjectId: string;
  selectedStatus: string;
  selectedAssigneeAgentId: string;
  selectedParentIssueId: string;
  priorities: string[];
  projects: ProjectRecord[];
  agents: AgentRecord[];
  issues: IssueRecord[];
  isSaving: boolean;
  errorMessage: string | null;
  onTitleChange: (value: string) => void;
  onDescriptionChange: (value: string) => void;
  onPriorityChange: (value: string) => void;
  onProjectChange: (value: string) => void;
  onAssigneeChange: (value: string) => void;
  onParentIssueChange: (value: string) => void;
  onCreate: () => void;
  onClose: () => void;
}) {
  const canCreate = !isSaving && title.trim().length > 0;
  const selectedProject =
    projects.find((project) => project.id === selectedProjectId) ?? null;
  const shouldShowRoutingContext =
    Boolean(selectedProject) ||
    normalizeBoardIssueValue(selectedStatus) !== "backlog";

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
          <div className="issue-dialog-header-copy">
            <span className="issue-dialog-badge">BOARD</span>
            <div className="issue-dialog-title-block">
              <h2 id="create-issue-dialog-title">Create issue</h2>
              <p>
                Create a new board issue with optional routing to a project,
                assignee, or parent issue.
              </p>
            </div>
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
          <div className="issue-dialog-divider" />

          {errorMessage ? (
            <div className="issue-dialog-alert">{errorMessage}</div>
          ) : null}

          {shouldShowRoutingContext ? (
            <div className="issue-dialog-context">
              {selectedProject ? (
                <div className="issue-dialog-context-chip">
                  <span className="issue-dialog-context-label">Project</span>
                  <strong>
                    {selectedProject.name ??
                      selectedProject.title ??
                      "Untitled project"}
                  </strong>
                </div>
              ) : null}
              <div className="issue-dialog-context-chip">
                <span className="issue-dialog-context-label">Column</span>
                <strong>{humanizeIssueValue(selectedStatus)}</strong>
              </div>
            </div>
          ) : null}

          <label className="issue-dialog-field issue-dialog-field-full">
            <span className="issue-dialog-label">Title</span>
            <input
              className="issue-dialog-input"
              onChange={(event) => onTitleChange(event.target.value)}
              placeholder="Investigate CI flake"
              value={title}
            />
            <small className="issue-dialog-hint">
              This becomes the main issue title and the default workspace label.
            </small>
          </label>

          <label className="issue-dialog-field issue-dialog-field-full">
            <span className="issue-dialog-label">Description</span>
            <textarea
              className="issue-dialog-input issue-dialog-textarea"
              onChange={(event) => onDescriptionChange(event.target.value)}
              placeholder="What needs to happen, how should success be measured, and what context should the assignee keep in mind?"
              value={description}
            />
            <small className="issue-dialog-hint">
              Optional background, acceptance criteria, or context for the
              assignee.
            </small>
          </label>

          <div className="issue-dialog-grid">
            <IssueDialogSelectField
              hint="Controls ordering and urgency in board views."
              label="Priority"
              onChange={onPriorityChange}
              value={selectedPriority}
            >
              {priorities.map((priority) => (
                <option key={priority} value={priority}>
                  {humanizeIssueValue(priority)}
                </option>
              ))}
            </IssueDialogSelectField>

            <IssueDialogSelectField
              hint="Optional project anchor for workspace routing and repo context."
              label="Project"
              onChange={onProjectChange}
              value={selectedProjectId}
            >
              <option value="">No project</option>
              {projects.map((project) => (
                <option key={project.id} value={project.id}>
                  {project.name}
                </option>
              ))}
            </IssueDialogSelectField>

            <IssueDialogSelectField
              hint="Optional agent owner for execution or follow-up."
              label="Assignee"
              onChange={onAssigneeChange}
              value={selectedAssigneeAgentId}
            >
              <option value="">Unassigned</option>
              {agents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name || agent.title || agent.role || agent.id}
                </option>
              ))}
            </IssueDialogSelectField>

            <IssueDialogSelectField
              hint="Use this to nest follow-up work under an existing issue."
              label="Parent issue"
              onChange={onParentIssueChange}
              value={selectedParentIssueId}
            >
              <option value="">No parent issue</option>
              {issues.map((issue) => (
                <option key={issue.id} value={issue.id}>
                  {issue.identifier ?? issue.title}
                </option>
              ))}
            </IssueDialogSelectField>
          </div>
        </div>

        <div className="issue-dialog-footer">
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
            {isSaving ? "Creating issue..." : "Create issue"}
          </button>
        </div>
      </div>
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

function RoutePlaceholder({ title, body }: { title: string; body: string }) {
  return (
    <section className="route-scroll">
      <div className="route-header compact">
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
          .join(" · ") || "Assigned workspace"}
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

function CompanyContextMenuIcon({ icon }: { icon: CompanyContextMenuIconKey }) {
  switch (icon) {
    case "dashboard":
      return (
        <svg
          aria-hidden="true"
          className="company-context-menu-icon"
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
    case "workspaces":
      return (
        <svg
          aria-hidden="true"
          className="company-context-menu-icon"
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
          className="company-context-menu-icon"
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
    case "agents":
      return (
        <svg
          aria-hidden="true"
          className="company-context-menu-icon"
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
    case "companySettings":
      return (
        <svg
          aria-hidden="true"
          className="company-context-menu-icon"
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
    case "stats":
      return "Stats";
    case "inbox":
      return "Inbox";
    case "workspaces":
      return "Workspaces";
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

function preferredViewSelectValue(view: string | null | undefined) {
  if (view === "settings") {
    return "settings";
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
  };
}

function settingsSectionIcon(section: SettingsSection) {
  switch (section) {
    case "general":
      return "gear";
    case "repositories":
      return "folder";
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
    status: "backlog",
    priority: "medium",
    projectId: "",
    assigneeAgentId: "",
    parentId: "",
  };
}

function createIssueDraft(issue: IssueRecord): IssueEditDraft {
  return {
    title: issue.title,
    description: issue.description ?? "",
    status: issue.status,
    priority: issue.priority,
    projectId: issue.project_id ?? "",
    assigneeAgentId: issue.assignee_agent_id ?? "",
    parentId: issue.parent_id ?? "",
  };
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

function normalizeBoardIssueValue(value: string | null | undefined) {
  const trimmed = value?.trim();
  if (!trimmed) {
    return "backlog";
  }

  return trimmed.toLowerCase().replaceAll(" ", "_");
}

function projectBoardColumnStatuses(issues: IssueRecord[]) {
  const statuses = ["backlog", "in_progress", "blocked", "done"];
  for (const issue of issues) {
    const normalizedStatus = normalizeBoardIssueValue(issue.status);
    if (!statuses.includes(normalizedStatus)) {
      statuses.push(normalizedStatus);
    }
  }
  return statuses;
}

function buildDashboardProjectBoards(
  projects: ProjectRecord[],
  issues: IssueRecord[]
): DashboardProjectBoardLayout[] {
  const columnCount = projects.length <= 1 ? 1 : 2;

  return projects.map((project, index) => {
    const col = index % columnCount;
    const row = Math.floor(index / columnCount);
    const projectIssues = issues.filter(
      (issue) => issue.project_id === project.id
    );
    const columns = projectBoardColumnStatuses(projectIssues).map((status) => ({
      status,
      issues: projectIssues.filter(
        (issue) => normalizeBoardIssueValue(issue.status) === status
      ),
    }));

    return {
      project,
      columns,
      issueCount: projectIssues.length,
      left:
        120 + col * (dashboardProjectBoardWidth + dashboardProjectBoardGapX),
      top:
        104 +
        row * (dashboardProjectBoardHeight + dashboardProjectBoardGapY) +
        (col === 1 ? 42 : 0),
    };
  });
}

function buildDashboardCanvasBounds(
  projectBoards: DashboardProjectBoardLayout[]
) {
  if (!projectBoards.length) {
    return { width: 2200, height: 1600 };
  }

  const maxRight = Math.max(
    ...projectBoards.map((board) => board.left + dashboardProjectBoardWidth)
  );
  const maxBottom = Math.max(
    ...projectBoards.map((board) => board.top + dashboardProjectBoardHeight)
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

function clampNumber(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function humanizeIssueValue(value: string) {
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (match) => match.toUpperCase());
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
      return "Heartbeat Timer";
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

function issuesListRowTitle(issue: IssueRecord) {
  if (!issue.identifier) {
    return issue.title;
  }

  return `${issue.identifier}  ${issue.title}`;
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
    return "Workspace attached";
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
