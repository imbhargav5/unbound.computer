import { Terminal } from "@xterm/xterm";
import {
  type FormEvent,
  type ReactNode,
  startTransition,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  boardCompanySnapshot,
  boardCreateCompany,
  boardCreateIssue,
  boardCreateProject,
  boardListCompanies,
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

type BoardRootLayout = "companyDashboard" | "workspace" | "settings";
type WorkspaceCenterTab = "conversation" | "terminal" | "preview";
type WorkspaceSidebarTab = "changes" | "files" | "commits";

const primaryBoardSections: Array<{ title: string; screens: AppScreen[] }> = [
  { title: "Work", screens: ["issues", "approvals", "workspaces"] },
  { title: "Projects", screens: ["projects", "goals"] },
];

const companyBoardSection: { title: string; screens: AppScreen[] } = {
  title: "Company",
  screens: ["activity", "costs", "companySettings"],
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

export function App() {
  const [bootstrap, setBootstrap] = useState<DesktopBootstrapStatus | null>(null);
  const [settings, setSettings] = useState<DesktopSettings>(defaultSettings);
  const [selectedScreen, setSelectedScreen] = useState<AppScreen>("dashboard");
  const [selectedSettingsSection, setSelectedSettingsSection] =
    useState<SettingsSection>("appearance");
  const [companies, setCompanies] = useState<Company[]>([]);
  const [repositories, setRepositories] = useState<RepositoryRecord[]>([]);
  const [selectedCompanyId, setSelectedCompanyId] = useState<string | null>(null);
  const [selectedRepositoryId, setSelectedRepositoryId] = useState<string | null>(null);
  const [selectedBoardWorkspaceId, setSelectedBoardWorkspaceId] = useState<string | null>(null);
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [companySnapshot, setCompanySnapshot] = useState<CompanySnapshot | null>(null);
  const [sessions, setSessions] = useState<SessionRecord[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  const [gitState, setGitState] = useState<GitStatusResult | null>(null);
  const [gitHistory, setGitHistory] = useState<GitLogResult | null>(null);
  const [branchState, setBranchState] = useState<GitBranchesResult | null>(null);
  const [fileEntries, setFileEntries] = useState<FileEntry[]>([]);
  const [currentDirectory, setCurrentDirectory] = useState("");
  const [selectedFilePath, setSelectedFilePath] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<FileReadResult | null>(null);
  const [selectedDiff, setSelectedDiff] = useState<GitDiffResult | null>(null);
  const [dependencyCheck, setDependencyCheck] = useState<Record<string, unknown> | null>(null);
  const [claudeStatusState, setClaudeStatusState] = useState<Record<string, unknown> | null>(null);
  const [terminalStatusState, setTerminalStatusState] = useState<Record<string, unknown> | null>(null);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [workspaceCenterTab, setWorkspaceCenterTab] =
    useState<WorkspaceCenterTab>("conversation");
  const [workspaceSidebarTab, setWorkspaceSidebarTab] =
    useState<WorkspaceSidebarTab>("changes");
  const [gitCommitMessage, setGitCommitMessage] = useState("");
  const [prompt, setPrompt] = useState("");
  const [terminalCommand, setTerminalCommand] = useState("");
  const [newProjectTitle, setNewProjectTitle] = useState("");
  const [newIssueTitle, setNewIssueTitle] = useState("");
  const [isWorking, setIsWorking] = useState(false);

  const terminalContainerRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const refreshTimeoutRef = useRef<number | null>(null);

  const deferredMessages = useDeferredValue(messages);
  const selectedRepository = repositories.find(
    (repository) => repository.id === selectedRepositoryId
  );
  const selectedCompany = companySnapshot?.company ?? null;
  const companyWorkspaces = companySnapshot?.workspaces ?? [];
  const selectedBoardWorkspace =
    companyWorkspaces.find((workspace) => workspace.id === selectedBoardWorkspaceId) ??
    companyWorkspaces[0] ??
    null;
  const selectedAgent =
    (companySnapshot?.agents ?? []).find((agent) => agent.id === selectedAgentId) ??
    companySnapshot?.agents[0] ??
    null;
  const selectedCompanyCeo =
    findCompanyCeo(companySnapshot?.agents ?? [], selectedCompany?.ceo_agent_id ?? null);
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
    ? selectedFilePath.split("/").filter(Boolean).at(-1) ?? "Preview"
    : "Preview";
  const currentBranchName = branchState?.current ?? gitState?.branch ?? "main";
  const currentBranch =
    branchState?.local.find((branch) => branch.name === currentBranchName) ?? null;
  const hasUncommittedChanges = (gitState?.files.length ?? 0) > 0;
  const hasUnpushedCommits = (currentBranch?.ahead ?? 0) > 0;
  const layout = boardRootLayout(selectedScreen);

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

        const [loadedSettings, loadedCompanies, loadedRepositories] = await Promise.all([
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
          nextSettings.preferred_company_id ??
          companiesValue[0]?.id ??
          null;
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
          setStatusMessage(error instanceof Error ? error.message : String(error));
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
          setStatusMessage(error instanceof Error ? error.message : String(error));
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

    setSelectedBoardWorkspaceId((current) => {
      if (current && nextWorkspaces.some((workspace) => workspace.id === current)) {
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
  }, [companySnapshot]);

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
        const nextSessions = (await sessionList(selectedRepositoryId)) as SessionRecord[];
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
              nextSessions.some((session) => session.id === boardWorkspaceSessionId)
            ) {
              return boardWorkspaceSessionId;
            }
            if (current && nextSessions.some((session) => session.id === current)) {
              return current;
            }
            return nextSessions[0]?.id ?? null;
          });
        });
      } catch (error) {
        if (!cancelled) {
          setStatusMessage(error instanceof Error ? error.message : String(error));
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
        const [nextMessages, nextFiles, nextGit, nextHistory, nextBranches, nextClaudeStatus, nextTerminalStatus] =
          await Promise.all([
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
          setStatusMessage(error instanceof Error ? error.message : String(error));
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
        const [loadedSettings, loadedCompanies, loadedRepositories] = await Promise.all([
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
          nextSettings.preferred_repository_id ?? repositoriesValue[0]?.id ?? null;

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
    setSelectedScreen(screen);
    void persistSettings({
      ...settings,
      preferred_view: preferredViewForScreen(screen),
    });
  };

  const handleSelectCompany = (companyId: string) => {
    startTransition(() => {
      setSelectedCompanyId(companyId);
      setSelectedScreen("dashboard");
    });
    void persistSettings({
      ...settings,
      preferred_company_id: companyId,
      preferred_view: preferredViewForScreen("dashboard"),
    });
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

  const handleOpenDirectory = async (relativePath: string) => {
    if (!selectedSessionId) {
      return;
    }

    try {
      const entries = await repositoryListFiles(selectedSessionId, relativePath);
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

  const handleCreateProject = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedCompanyId || !newProjectTitle.trim()) {
      return;
    }

    setIsWorking(true);
    try {
      await boardCreateProject({
        company_id: selectedCompanyId,
        name: newProjectTitle.trim(),
      });
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setNewProjectTitle("");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  };

  const handleCreateIssue = async (event: FormEvent) => {
    event.preventDefault();
    if (!selectedCompanyId || !newIssueTitle.trim()) {
      return;
    }

    setIsWorking(true);
    try {
      await boardCreateIssue({
        company_id: selectedCompanyId,
        title: newIssueTitle.trim(),
      });
      const snapshot = await boardCompanySnapshot(selectedCompanyId);
      setCompanySnapshot(snapshot);
      setNewIssueTitle("");
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
      setSelectedRepositoryId(latestRepository?.id ?? nextRepositories[0]?.id ?? null);

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
    await runGitMutation(() => gitStage([file.path], selectedSessionId ?? undefined));
  };

  const handleUnstageFile = async (file: GitStatusFile) => {
    await runGitMutation(() => gitUnstage([file.path], selectedSessionId ?? undefined));
  };

  const handleDiscardFile = async (file: GitStatusFile) => {
    await runGitMutation(() => gitDiscard([file.path], selectedSessionId ?? undefined));
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
          <p>Checking for a compatible daemon and loading your local workspace.</p>
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
            <button className="primary-button" onClick={() => void retryBootstrap()} type="button">
              Retry
            </button>
            <button
              className="secondary-button"
              onClick={() =>
                void desktopOpenExternal("https://github.com/unbound-computer/unbound")
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

  return (
    <div className="swift-shell">
      <aside className="company-rail">
        <div className="company-rail-brand">
          <span>u</span>
        </div>
        <div className="company-rail-list">
          {companies.map((company) => (
            <button
              className={
                company.id === selectedCompanyId
                  ? "company-rail-button active"
                  : "company-rail-button"
              }
              key={company.id}
              onClick={() => handleSelectCompany(company.id)}
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

      {layout === "companyDashboard" ? (
        <>
          <aside className="board-sidebar">
            <div className="board-sidebar-header">
              <div>
                <strong>{selectedCompany?.name ?? "Company"}</strong>
                <span>Local board</span>
              </div>
              <button className="icon-button" onClick={() => void refreshBoardData()} type="button">
                ↻
              </button>
            </div>

            <div className="board-sidebar-scroll">
              <div className="board-sidebar-section">
                <BoardSidebarButton
                  active={selectedScreen === "dashboard"}
                  label="Dashboard"
                  onClick={() => handleSelectScreen("dashboard")}
                />
                <BoardSidebarButton
                  active={selectedScreen === "inbox"}
                  label="Inbox"
                  onClick={() => handleSelectScreen("inbox")}
                />
                <form className="sidebar-inline-form" onSubmit={handleCreateIssue}>
                  <input
                    onChange={(event) => setNewIssueTitle(event.target.value)}
                    placeholder="New issue"
                    value={newIssueTitle}
                  />
                  <button className="icon-button" type="submit">
                    +
                  </button>
                </form>
              </div>

              {primaryBoardSections.map((section) => (
                <div className="board-sidebar-section" key={section.title}>
                  <span className="sidebar-section-title">{section.title}</span>
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
                        selectedScreen === "agents" && selectedAgentId === agent.id
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
                <span className="sidebar-section-title">{companyBoardSection.title}</span>
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

          <main className="board-content">
            {statusMessage ? <div className="status-banner">{statusMessage}</div> : null}

            {selectedScreen === "dashboard" ? (
              <section className="route-scroll">
                <div className="route-header">
                  <span className="route-kicker">Dashboard</span>
                  <h1>{selectedCompany?.name ?? "Unbound"}</h1>
                  <p>
                    {selectedCompany?.description ??
                      "The Tauri shell now follows the same multi-column board flow as the Swift app."}
                  </p>
                </div>

                <div className="metric-grid">
                  <MetricCard label="Issues" value={companySnapshot?.issues.length ?? 0} />
                  <MetricCard label="Projects" value={companySnapshot?.projects.length ?? 0} />
                  <MetricCard label="Agents" value={companySnapshot?.agents.length ?? 0} />
                  <MetricCard label="Approvals" value={companySnapshot?.approvals.length ?? 0} />
                  <MetricCard label="Workspaces" value={companySnapshot?.workspaces.length ?? 0} />
                  <MetricCard label="Repositories" value={repositories.length} />
                </div>

                <div className="surface-grid">
                  <section className="surface-panel wide">
                    <div className="surface-header">
                      <h3>Production boundary preserved</h3>
                      <button className="secondary-button" onClick={() => void loadDependencies()} type="button">
                        Check dependencies
                      </button>
                    </div>
                    <p>
                      `unbound-daemon` stays separately installed and version-checked.
                      The desktop app only connects over the existing local socket boundary.
                    </p>
                    <div className="summary-grid">
                      <SummaryPill label="Daemon" value={bootstrap.daemon_info?.daemon_version ?? "unknown"} />
                      <SummaryPill label="Protocol" value={bootstrap.daemon_info?.protocol_version ?? "unknown"} />
                      <SummaryPill label="App" value={bootstrap.expected_app_version} />
                    </div>
                    {dependencyCheck ? <pre>{JSON.stringify(dependencyCheck, null, 2)}</pre> : null}
                  </section>

                  <section className="surface-panel">
                    <h3>Projects</h3>
                    <form className="stack-form" onSubmit={handleCreateProject}>
                      <input
                        onChange={(event) => setNewProjectTitle(event.target.value)}
                        placeholder="Create project"
                        value={newProjectTitle}
                      />
                      <button className="secondary-button" type="submit">
                        Create
                      </button>
                    </form>
                    <div className="surface-list">
                      {(companySnapshot?.projects ?? []).map((project) => (
                        <div className="surface-list-row" key={project.id}>
                          <strong>{project.name ?? project.title ?? "Untitled project"}</strong>
                          <span>{project.status ?? "pending"}</span>
                        </div>
                      ))}
                    </div>
                  </section>

                  <section className="surface-panel">
                    <h3>Agents</h3>
                    <div className="surface-list">
                      {(companySnapshot?.agents ?? []).map((agent) => (
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
                      {(companySnapshot?.workspaces ?? []).map((workspace) => (
                        <button
                          className="file-list-button"
                          key={workspace.id}
                          onClick={() => handleSelectBoardWorkspace(workspace)}
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
                              .join(" · ") || workspace.workspace_status || "workspace"}
                          </span>
                        </button>
                      ))}
                    </div>
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "inbox" ? (
              <RoutePlaceholder
                body="Inbox routing exists in the shell now. Use Approvals and Issues while the daemon inbox surface catches up."
                title="Inbox"
              />
            ) : null}

            {selectedScreen === "agents" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <span className="route-kicker">Agents</span>
                  <h1>{selectedAgent?.name ?? "Company roster"}</h1>
                </div>
                <div className="surface-grid single">
                  <section className="surface-panel">
                    {selectedAgent ? (
                      <>
                        <div className="summary-grid">
                          <SummaryPill label="Role" value={selectedAgent.title ?? selectedAgent.role ?? "Agent"} />
                          <SummaryPill label="Status" value={String(selectedAgent.status ?? "active")} />
                          <SummaryPill label="Company" value={selectedCompany?.name ?? "Unbound"} />
                        </div>
                        <div className="surface-list">
                          {(companySnapshot?.agents ?? []).map((agent) => (
                            <button
                              className={
                                agent.id === selectedAgentId
                                  ? "file-list-button active"
                                  : "file-list-button"
                              }
                              key={agent.id}
                              onClick={() => handleSelectAgent(agent.id)}
                              type="button"
                            >
                              <strong>{agent.name}</strong>
                              <span>{agent.title ?? agent.role ?? "Agent"}</span>
                            </button>
                          ))}
                        </div>
                      </>
                    ) : (
                      <p>No agents are available for this company yet.</p>
                    )}
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "issues" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <span className="route-kicker">Issues</span>
                  <h1>Open work</h1>
                </div>
                <div className="surface-grid">
                  <section className="surface-panel">
                    <h3>Create issue</h3>
                    <form className="stack-form" onSubmit={handleCreateIssue}>
                      <input
                        onChange={(event) => setNewIssueTitle(event.target.value)}
                        placeholder="New issue title"
                        value={newIssueTitle}
                      />
                      <button className="secondary-button" type="submit">
                        Create
                      </button>
                    </form>
                  </section>
                  <section className="surface-panel wide">
                    <h3>Issue list</h3>
                    <div className="surface-list">
                      {(companySnapshot?.issues ?? []).map((issue) => (
                        <div className="surface-list-row" key={issue.id}>
                          <strong>{issue.title}</strong>
                          <span>
                            {issue.status ?? "backlog"}
                            {issue.priority ? ` · ${issue.priority}` : ""}
                          </span>
                        </div>
                      ))}
                    </div>
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "approvals" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <span className="route-kicker">Approvals</span>
                  <h1>Board approvals</h1>
                </div>
                <div className="surface-grid single">
                  <section className="surface-panel">
                    <div className="surface-list">
                      {(companySnapshot?.approvals ?? []).map((approval) => (
                        <div className="surface-list-row" key={approval.id}>
                          <strong>{approval.type ?? "Approval"}</strong>
                          <span>{approval.status ?? "pending"}</span>
                        </div>
                      ))}
                    </div>
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "projects" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <span className="route-kicker">Projects</span>
                  <h1>Active projects</h1>
                </div>
                <div className="surface-grid">
                  <section className="surface-panel">
                    <h3>Create project</h3>
                    <form className="stack-form" onSubmit={handleCreateProject}>
                      <input
                        onChange={(event) => setNewProjectTitle(event.target.value)}
                        placeholder="Project name"
                        value={newProjectTitle}
                      />
                      <button className="secondary-button" type="submit">
                        Create
                      </button>
                    </form>
                  </section>
                  <section className="surface-panel wide">
                    <h3>Project list</h3>
                    <div className="surface-list">
                      {(companySnapshot?.projects ?? []).map((project) => (
                        <div className="surface-list-row" key={project.id}>
                          <strong>{project.name ?? project.title ?? "Untitled project"}</strong>
                          <span>{project.status ?? "pending"}</span>
                        </div>
                      ))}
                    </div>
                  </section>
                </div>
              </section>
            ) : null}

            {selectedScreen === "goals" ? (
              <RoutePlaceholder
                body="The Goals route is present in the shell. Goal-specific daemon UI parity still needs dedicated data surfaces."
                title="Goals"
              />
            ) : null}

            {selectedScreen === "companySettings" ? (
              <section className="route-scroll">
                <div className="route-header compact">
                  <span className="route-kicker">Company settings</span>
                  <h1>{selectedCompany?.name ?? "Company settings"}</h1>
                  <p>
                    Board-specific company details and policies live here. Device and app settings
                    stay behind the rail gear.
                  </p>
                </div>

                <div className="surface-grid">
                  <section className="surface-panel wide">
                    <h3>Company profile</h3>
                    <p>
                      This route follows the board/company admin surface rather than the desktop
                      preferences shell.
                    </p>
                    <div className="surface-list">
                      <DetailRow label="Company Name" value={selectedCompany?.name ?? "n/a"} />
                      <DetailRow
                        label="Description"
                        value={selectedCompany?.description ?? "No description"}
                      />
                      <DetailRow
                        label="Brand Color"
                        value={selectedCompany?.brand_color ?? "Default board accent"}
                      />
                      <DetailRow
                        label="Issue Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                    </div>
                  </section>

                  <section className="surface-panel">
                    <h3>Board policy</h3>
                    <div className="summary-grid">
                      <SummaryPill
                        label="Issue Prefix"
                        value={selectedCompany?.issue_prefix ?? "n/a"}
                      />
                      <SummaryPill
                        label="Monthly Budget"
                        value={formatCents(selectedCompany?.budget_monthly_cents)}
                      />
                      <SummaryPill
                        label="Monthly Spend"
                        value={formatCents(selectedCompany?.spent_monthly_cents)}
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
                      <DetailRow label="Status" value={String(selectedCompany?.status ?? "active")} />
                      <DetailRow
                        label="CEO"
                        value={selectedCompanyCeo?.name ?? selectedCompany?.ceo_agent_id ?? "Unassigned"}
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
              <RoutePlaceholder
                body="Activity is positioned where the Swift app expects it. The Tauri shell keeps the same route even though the activity feed is not wired yet."
                title="Activity"
              />
            ) : null}

            {selectedScreen === "costs" ? (
              <RoutePlaceholder
                body="Cost summaries are still a placeholder, but the screen now sits in the same company-shell flow as the Swift app."
                title="Costs"
              />
            ) : null}
          </main>
        </>
      ) : null}

      {layout === "workspace" ? (
        <>
          <aside className="workspace-sidebar">
            <div className="workspace-sidebar-header">
              <div>
                <h2>Workspaces</h2>
                <span>{selectedCompany?.name ?? "Company"} board</span>
              </div>
              <button className="icon-button" onClick={() => void refreshBoardData()} type="button">
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
                <p>Workspaces appear automatically when an assigned agent starts an issue.</p>
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
                      {selectedBoardWorkspace.issue_title ?? selectedBoardWorkspace.title}
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
                    <SummaryPill label="Claude" value={stringifyStatus(claudeStatusState)} />
                    <SummaryPill label="Terminal" value={stringifyStatus(terminalStatusState)} />
                  </div>
                </div>

                {statusMessage ? <div className="status-banner">{statusMessage}</div> : null}

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
                      <button className="primary-button" disabled={isWorking} type="submit">
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
                    <div className="terminal-frame" ref={terminalContainerRef} />
                    <form className="workspace-terminal-form" onSubmit={handleRunTerminal}>
                      <input
                        onChange={(event) => setTerminalCommand(event.target.value)}
                        placeholder="Run a shell command in the selected session"
                        value={terminalCommand}
                      />
                      <button className="primary-button" disabled={isWorking} type="submit">
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
                          <SummaryPill label="Added" value={selectedDiff.additions} />
                          <SummaryPill label="Deleted" value={selectedDiff.deletions} />
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
                <p>Issue-owned coding sessions appear here. The main repo path is used directly.</p>
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
                    value={selectedBoardWorkspace.workspace_repo_path ?? "Missing"}
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
                      onChange={(event) => setGitCommitMessage(event.target.value)}
                      placeholder="Describe this change"
                      value={gitCommitMessage}
                    />
                  </label>

                  <GitChangeSection
                    activePath={selectedDiff ? selectedFilePath : null}
                    files={(gitState?.files ?? []).filter((file) => file.staged)}
                    onDiscard={(file) => void handleDiscardFile(file)}
                    onOpen={(file) => void handleOpenDiff(file.path)}
                    onPrimaryAction={(file) => void handleUnstageFile(file)}
                    primaryActionLabel="Unstage"
                    title="Staged"
                  />
                  <GitChangeSection
                    activePath={selectedDiff ? selectedFilePath : null}
                    files={(gitState?.files ?? []).filter((file) => !file.staged)}
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
                    <SummaryPill label="Clean" value={gitState?.is_clean ? "yes" : "no"} />
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
        </>
      ) : null}

      {layout === "settings" ? (
        <>
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
            {statusMessage ? <div className="status-banner">{statusMessage}</div> : null}

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
                        onSelect={() => void applySettingsPatch({ theme_mode: mode })}
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
                        isSelected={(settings.font_size_preset ?? "medium") === preset}
                        key={preset}
                        onSelect={() => void applySettingsPatch({ font_size_preset: preset })}
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
                    <form className="settings-form" onSubmit={handleSettingsSubmit}>
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
                        <span>Show raw JSON for structured session messages</span>
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
                          value={preferredViewSelectValue(settings.preferred_view)}
                        >
                          <option value="dashboard">Dashboard</option>
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
                    <button className="secondary-button" onClick={() => void handleAddRepository()} type="button">
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
                          onClick={() => void desktopRevealInFinder(repository.path)}
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
        </>
      ) : null}
    </div>
  );
}

function MetricCard({ label, value }: { label: string; value: number | string }) {
  return (
    <section className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </section>
  );
}

function SummaryPill({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="summary-pill">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
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
      className={active ? "board-sidebar-button active" : "board-sidebar-button"}
      onClick={onClick}
      type="button"
    >
      {label}
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
      className={isSelected ? "settings-option-card active" : "settings-option-card"}
      onClick={onSelect}
      type="button"
    >
      <FontSizePreview preset={preset} />
      <div className="settings-option-label">
        <span className="settings-option-icon">{fontSizePresetSymbol(preset)}</span>
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
      className={active ? "workspace-board-item active" : "workspace-board-item"}
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
        {[workspace.project_name, workspace.agent_name].filter(Boolean).join(" · ") || "Assigned workspace"}
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
      className={active ? "workspace-sidebar-tab active" : "workspace-sidebar-tab"}
      onClick={onClick}
      type="button"
    >
      <span>{label}</span>
      {count ? <small>{count}</small> : null}
    </button>
  );
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
            className={activePath === file.path ? "git-change-row active" : "git-change-row"}
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

  if (screen === "appSettings") {
    return "settings";
  }

  if (screen === "companySettings") {
    return "company_settings";
  }

  return "dashboard";
}

function normalizeScreen(view: string | null | undefined): AppScreen {
  if (view === "settings") {
    return "appSettings";
  }

  if (view === "company_settings") {
    return "companySettings";
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

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
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

function findCompanyCeo<
  T extends { id: string; role?: string | null }
>(agents: T[], ceoAgentId: string | null) {
  if (ceoAgentId) {
    const ceoAgent = agents.find((agent) => agent.id === ceoAgentId);
    if (ceoAgent) {
      return ceoAgent;
    }
  }

  return (
    agents.find((agent) => agent.role?.toLowerCase() === "ceo") ?? null
  );
}

function orderSidebarAgents<
  T extends { id: string; role?: string | null }
>(agents: T[], ceoAgentId: string | null) {
  if (ceoAgentId) {
    const ceoAgent = agents.find((agent) => agent.id === ceoAgentId);
    if (ceoAgent) {
      return [ceoAgent, ...agents.filter((agent) => agent.id !== ceoAgentId)];
    }
  }

  const ceoAgent = agents.find(
    (agent) => agent.role?.toLowerCase() === "ceo"
  );
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

function buildTerminalTranscript(messages: SessionMessage[]) {
  const lines = messages.flatMap((message) => {
    const content = normalizeMessageContent(message.content);
    if (typeof content !== "object" || content === null) {
      return [];
    }

    if (content.type === "terminal_output" && typeof content.content === "string") {
      return [`[${String(content.stream ?? "stdout")}] ${content.content}`];
    }

    if (content.type === "terminal_finished") {
      return [`[exit ${String(content.exit_code ?? "unknown")}]`];
    }

    return [];
  });

  return lines.join("\n");
}

function normalizeMessageContent(value: unknown): Record<string, unknown> | string {
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
