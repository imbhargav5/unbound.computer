// @vitest-environment jsdom

import { act, type ReactElement, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

vi.mock("@xterm/xterm", () => ({
  Terminal: class Terminal {},
}));

import {
  BirdsEyeQuickCreateRow,
  IssueWorkspaceDetailView,
  WorkspaceChatComposer,
  WorkspaceInspectorSidebar,
  WorkspaceRuntimeStatusLine,
} from "./app";
import type {
  GitLogResult,
  GitStatusResult,
  WorkspaceRecord,
} from "./lib/types";

(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true;

describe("issue detail parity components", () => {
  let container: HTMLDivElement | null = null;
  let root: Root | null = null;

  beforeAll(() => {
    Object.defineProperty(HTMLCanvasElement.prototype, "getContext", {
      configurable: true,
      value: vi.fn(() => ({})),
    });
  });

  const render = (element: ReactElement) => {
    container = document.createElement("div");
    document.body.appendChild(container);
    root = createRoot(container);
    act(() => {
      root?.render(element);
    });
    return container;
  };

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    vi.restoreAllMocks();
  });

  it("expands the composer, updates runtime controls, and triggers send", () => {
    const onAddAttachment = vi.fn();
    const onSend = vi.fn();

    function Harness() {
      const [value, setValue] = useState("");
      const [provider, setProvider] = useState("claude");
      const [model, setModel] = useState("default");
      const [thinking, setThinking] = useState("medium");
      const [planMode, setPlanMode] = useState(false);

      return (
        <>
          <WorkspaceChatComposer
            disabled={false}
            isPlanMode={planMode}
            isStreaming={false}
            latestCompletionSummary={{
              durationMs: null,
              outcomeLabel: "end_turn",
              summaryText: "Done",
              totalCostUSD: 0.02,
              totalTokens: 1240,
              turns: 1,
            }}
            modelOptions={["default", "sonnet"]}
            onAddAttachment={onAddAttachment}
            onChange={setValue}
            onModelChange={setModel}
            onPlanModeChange={setPlanMode}
            onProviderChange={setProvider}
            onSend={onSend}
            onThinkingEffortChange={setThinking}
            providerOptions={[
              { label: "Claude", value: "claude" },
              { label: "Codex", value: "codex" },
            ]}
            selectedModel={model}
            selectedProvider={provider}
            selectedThinkingEffort={thinking}
            thinkingEffortOptions={["low", "medium", "high", "max"]}
            value={value}
          />
          <span data-testid="composer-value">{value}</span>
        </>
      );
    }

    const view = render(<Harness />);
    expect(view.textContent).toContain("What do you want to build?");

    act(() => {
      view
        .querySelector(".workspace-chat-composer")
        ?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    const textarea = view.querySelector("textarea");
    expect(textarea).not.toBeNull();

    act(() => {
      textarea?.dispatchEvent(new FocusEvent("focus", { bubbles: true }));
      if (textarea instanceof HTMLTextAreaElement) {
        const valueSetter = Object.getOwnPropertyDescriptor(
          HTMLTextAreaElement.prototype,
          "value"
        )?.set;
        valueSetter?.call(textarea, "Ship the update");
      }
      textarea?.dispatchEvent(new Event("input", { bubbles: true }));
      textarea?.dispatchEvent(new Event("change", { bubbles: true }));
    });
    expect(
      view.querySelector('[data-testid="composer-value"]')?.textContent
    ).toBe("Ship the update");

    expect(view.textContent).toContain("1.2k tokens");
    expect(view.textContent).toContain("$0.02");

    const plusButton = view.querySelector(
      'button[aria-label="Composer actions"]'
    );
    act(() => {
      plusButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(view.textContent).toContain("Add Attachments");
    expect(view.textContent).toContain("Plan mode");

    const planToggleButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.textContent?.includes("Plan mode")
    );
    act(() => {
      planToggleButton?.dispatchEvent(
        new MouseEvent("click", { bubbles: true })
      );
    });
    expect(view.textContent).toContain(
      "Plan mode — Claude will create a plan before making changes"
    );

    const attachmentButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.textContent?.includes("Add Attachments")
    );
    act(() => {
      attachmentButton?.dispatchEvent(
        new MouseEvent("click", { bubbles: true })
      );
    });
    expect(onAddAttachment).toHaveBeenCalledTimes(1);

    const sendButton = view.querySelector('button[aria-label="Send prompt"]');
    expect(sendButton).not.toBeNull();
    act(() => {
      sendButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onSend).toHaveBeenCalledTimes(1);
  });

  it("shows the stop control while streaming", () => {
    const onCancel = vi.fn();
    const view = render(
      <WorkspaceChatComposer
        disabled={false}
        isPlanMode={false}
        isStreaming
        modelOptions={["default"]}
        onCancel={onCancel}
        onChange={() => undefined}
        onModelChange={() => undefined}
        onPlanModeChange={() => undefined}
        onSend={() => undefined}
        onThinkingEffortChange={() => undefined}
        selectedModel="default"
        selectedProvider="claude"
        selectedThinkingEffort="medium"
        thinkingEffortOptions={["low", "medium", "high", "max"]}
        value="Streaming in progress"
      />
    );

    const stopButton = view.querySelector('button[aria-label="Stop response"]');
    expect(stopButton).not.toBeNull();
    act(() => {
      stopButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("shows provider-specific options in birds eye quick create", () => {
    const onDraftChange = vi.fn();

    const view = render(
      <BirdsEyeQuickCreateRow
        dependencyCheck={null}
        draft={{
          command: "claude",
          enableChrome: false,
          model: "sonnet",
          planMode: true,
          priority: "medium",
          projectId: "project-1",
          skipPermissions: false,
          status: "backlog",
          thinkingEffort: "max",
          workspaceTargetMode: "main",
          workspaceWorktreeBranch: "",
          workspaceWorktreeName: "",
          workspaceWorktreePath: "",
        }}
        errorMessage={null}
        folder={{ label: "Repo root" } as any}
        inputRef={() => undefined}
        isSaving={false}
        onCancel={() => undefined}
        onDraftChange={onDraftChange}
        onSubmit={(event) => event.preventDefault()}
        onTitleChange={() => undefined}
        sourceNode={null}
        title="Follow up"
      />
    );

    const providerSelect = view.querySelector(
      'select[aria-label="New chat provider"]'
    );
    const modelSelect = view.querySelector(
      'select[aria-label="New chat model"]'
    );
    const effortSelect = view.querySelector(
      'select[aria-label="New chat reasoning effort"]'
    );

    expect(providerSelect).not.toBeNull();
    expect(modelSelect).not.toBeNull();
    expect(effortSelect).not.toBeNull();
    expect(
      Array.from(providerSelect?.querySelectorAll("option") ?? []).map(
        (option) => option.textContent
      )
    ).toEqual(["Claude", "Codex"]);
    expect(
      Array.from(modelSelect?.querySelectorAll("option") ?? []).map(
        (option) => option.value
      )
    ).toEqual(expect.arrayContaining(["default", "sonnet", "opus", "haiku"]));
    expect(
      Array.from(effortSelect?.querySelectorAll("option") ?? []).map(
        (option) => option.textContent
      )
    ).toEqual(["Low", "Medium", "High", "Max"]);

    act(() => {
      if (providerSelect instanceof HTMLSelectElement) {
        const valueSetter = Object.getOwnPropertyDescriptor(
          HTMLSelectElement.prototype,
          "value"
        )?.set;
        valueSetter?.call(providerSelect, "codex");
      }
      providerSelect?.dispatchEvent(new Event("change", { bubbles: true }));
    });

    expect(onDraftChange).toHaveBeenCalledWith({
      command: "codex",
      model: "default",
      thinkingEffort: "xhigh",
      planMode: false,
    });
  });

  it("renders the sidebar shell with git actions and the issue tab", () => {
    const onSelectSidebarTab = vi.fn();
    const onGitCommit = vi.fn();
    const workspace = {
      agent_name: "Founding Engineer",
      id: "workspace-1",
      issue_identifier: "FUN-5",
      project_name: "imbhargav5",
      workspace_branch: "feature/readme",
      workspace_repo_path: "/tmp/repo",
    } as unknown as WorkspaceRecord;

    const gitState = {
      files: [],
      is_clean: false,
    } as GitStatusResult;

    const gitHistory = {
      commits: [],
      has_more: false,
    } as GitLogResult;

    const view = render(
      <WorkspaceInspectorSidebar
        currentBranch={null}
        currentBranchName="feature/readme"
        fileEntries={[]}
        fileTreeCacheKey="session-1"
        gitCommitMessage="Ship README change"
        gitHistory={gitHistory}
        gitState={gitState}
        hasUncommittedChanges
        hasUnpushedCommits={false}
        issueMeta={<div>Issue metadata</div>}
        isWorking={false}
        onGitCommit={onGitCommit}
        onGitCommitMessageChange={() => undefined}
        onGitPush={() => undefined}
        onOpenDiff={() => undefined}
        onLoadDirectoryChildren={async () => []}
        onOpenFile={() => undefined}
        onRefreshSidebar={() => undefined}
        onSelectSidebarTab={onSelectSidebarTab}
        selectedDiff={null}
        selectedFilePath={null}
        workspace={workspace}
        workspaceSidebarTab="changes"
      />
    );

    expect(view.textContent).not.toContain("Workspace Details");
    expect(view.textContent).toContain("feature/readme");
    expect(view.textContent).toContain("Issue");

    const filesTab = Array.from(view.querySelectorAll("button")).find(
      (button) => button.textContent?.includes("Files")
    );
    act(() => {
      filesTab?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onSelectSidebarTab).toHaveBeenCalledWith("files");

    const toggleButton = view.querySelector(
      'button[aria-label="Commit actions"]'
    );
    act(() => {
      toggleButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(view.textContent).toContain("Commit + Push");

    const dropdownAction = Array.from(view.querySelectorAll("button")).find(
      (button) => button.textContent?.includes("Commit + Push")
    );
    act(() => {
      dropdownAction?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onGitCommit).toHaveBeenCalledWith(true);
  });

  it("renders the compact changes list and refresh control", () => {
    const onOpenDiff = vi.fn();
    const onRefreshSidebar = vi.fn();

    const view = render(
      <WorkspaceInspectorSidebar
        currentBranch={null}
        currentBranchName="feature/readme"
        fileEntries={[]}
        fileTreeCacheKey="session-1"
        gitCommitMessage=""
        gitHistory={{ commits: [], has_more: false } as GitLogResult}
        gitState={
          {
            files: [
              {
                additions: 12,
                deletions: 3,
                path: "apps/web/src/app.tsx",
                status: "modified",
              },
              {
                additions: 4,
                deletions: 0,
                path: "packages/runtime/config.ts",
                status: "untracked",
              },
            ],
            is_clean: false,
          } as GitStatusResult
        }
        hasUncommittedChanges
        hasUnpushedCommits={false}
        isWorking={false}
        onGitCommit={() => undefined}
        onGitCommitMessageChange={() => undefined}
        onGitPush={() => undefined}
        onOpenDiff={onOpenDiff}
        onLoadDirectoryChildren={async () => []}
        onOpenFile={() => undefined}
        onRefreshSidebar={onRefreshSidebar}
        onSelectSidebarTab={() => undefined}
        selectedDiff={null}
        selectedFilePath={null}
        workspace={null}
        workspaceSidebarTab="changes"
      />
    );

    expect(view.textContent).toContain("Changes");
    expect(view.textContent).toContain("apps/web/src/app.tsx");
    expect(view.textContent).toContain("+12");
    expect(view.textContent).toContain("-3");
    expect(view.textContent).not.toContain("Commit message");

    const rowButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.getAttribute("title") === "apps/web/src/app.tsx"
    );
    act(() => {
      rowButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onOpenDiff).toHaveBeenCalledWith("apps/web/src/app.tsx");

    const refreshButton = view.querySelector(
      'button[aria-label="Refresh repository panel"]'
    );
    act(() => {
      refreshButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });
    expect(onRefreshSidebar).toHaveBeenCalled();
  });

  it("renders repository files as a collapsible tree", async () => {
    const onOpenFile = vi.fn();
    const onLoadDirectoryChildren = vi
      .fn<(...args: [string]) => Promise<any[]>>()
      .mockImplementation(async (path: string) => {
        if (path === "apps") {
          return [
            {
              has_children: false,
              is_dir: false,
              name: "page.tsx",
              path: "apps/page.tsx",
            },
            {
              has_children: true,
              is_dir: true,
              name: "components",
              path: "apps/components",
            },
          ];
        }

        if (path === "apps/components") {
          return [
            {
              has_children: false,
              is_dir: false,
              name: "AppShell.tsx",
              path: "apps/components/AppShell.tsx",
            },
          ];
        }

        return [];
      });

    const view = render(
      <WorkspaceInspectorSidebar
        currentBranch={null}
        currentBranchName="feature/readme"
        fileEntries={[
          {
            has_children: true,
            is_dir: true,
            name: "apps",
            path: "apps",
          },
          {
            has_children: true,
            is_dir: true,
            name: "node_modules",
            path: "node_modules",
          },
          {
            has_children: false,
            is_dir: false,
            name: "package.json",
            path: "package.json",
          },
        ]}
        fileTreeCacheKey="session-1"
        gitCommitMessage=""
        gitHistory={{ commits: [], has_more: false } as GitLogResult}
        gitState={{ files: [], is_clean: false } as GitStatusResult}
        hasUncommittedChanges={false}
        hasUnpushedCommits={false}
        isWorking={false}
        onGitCommit={() => undefined}
        onGitCommitMessageChange={() => undefined}
        onGitPush={() => undefined}
        onLoadDirectoryChildren={onLoadDirectoryChildren}
        onOpenDiff={() => undefined}
        onOpenFile={onOpenFile}
        onRefreshSidebar={() => undefined}
        onSelectSidebarTab={() => undefined}
        selectedDiff={null}
        selectedFilePath={null}
        workspace={null}
        workspaceSidebarTab="files"
      />
    );

    expect(view.textContent).toContain("apps");
    expect(view.textContent).toContain("node_modules");
    expect(view.textContent).toContain("package.json");
    expect(view.textContent).not.toContain("Repository Files");
    expect(view.querySelector(".workspace-file-tree-separator")).not.toBeNull();

    const appsButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.getAttribute("title") === "apps"
    );
    expect(appsButton).not.toBeNull();

    await act(async () => {
      appsButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(onLoadDirectoryChildren).toHaveBeenCalledWith("apps");
    expect(view.textContent).toContain("components");
    expect(view.textContent).toContain("page.tsx");

    const componentFolderButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.getAttribute("title") === "apps/components"
    );
    expect(componentFolderButton).not.toBeNull();

    await act(async () => {
      componentFolderButton?.dispatchEvent(
        new MouseEvent("click", { bubbles: true })
      );
    });

    expect(onLoadDirectoryChildren).toHaveBeenCalledWith("apps/components");
    expect(view.textContent).toContain("AppShell.tsx");

    const packageFileButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.getAttribute("title") === "package.json"
    );
    expect(packageFileButton).not.toBeNull();

    act(() => {
      packageFileButton?.dispatchEvent(
        new MouseEvent("click", { bubbles: true })
      );
    });

    expect(onOpenFile).toHaveBeenCalledWith("package.json");
  });

  it("renders the runtime line like the chat shell", () => {
    const view = render(
      <div>
        <WorkspaceRuntimeStatusLine
          detail="Daemon connected"
          status="running"
          tone="running"
        />
      </div>
    );

    expect(view.textContent).toContain("running");
    expect(view.textContent).toContain("Daemon connected");
  });

  it("opens the workspace inspector in a right-side sheet on compact screens", () => {
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      writable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        addEventListener: () => undefined,
        addListener: () => undefined,
        dispatchEvent: () => true,
        matches: query === "(max-width: 1280px)",
        media: query,
        onchange: null,
        removeEventListener: () => undefined,
        removeListener: () => undefined,
      })),
    });

    const view = render(
      <IssueWorkspaceDetailView
        agents={[]}
        availableStatusOptions={[]}
        dependencyCheck={null}
        issue={
          {
            id: "issue-1",
            project_id: "project-1",
            title: "Mobile inspector",
          } as any
        }
        issueDraft={
          {
            command: "claude",
            model: "default",
            planMode: false,
            projectId: "project-1",
            thinkingEffort: "medium",
            title: "",
          } as any
        }
        issueEditorError={null}
        issueWorkspaceSidebar={
          <aside className="workspace-inspector">
            <div>Inspector body</div>
          </aside>
        }
        isSavingIssue={false}
        isWorking={false}
        latestCompletionSummary={null}
        onAddAttachment={() => undefined}
        onBack={() => undefined}
        onCommitIssuePatch={() => undefined}
        onIssueDraftChange={() => undefined}
        onPromptChange={() => undefined}
        onRespondToQuestion={() => undefined}
        onRevealRepo={() => undefined}
        onRunTerminal={(event) => event.preventDefault()}
        onSelectWorkspaceCenterTab={() => undefined}
        onSendPrompt={() => undefined}
        onStopSession={() => undefined}
        onStopTerminal={() => undefined}
        onTerminalCommandChange={() => undefined}
        previewTabLabel="Preview"
        projectLabel={() => "Project"}
        projects={[]}
        prompt=""
        selectableParentIssues={[]}
        selectedDiff={null}
        selectedFile={null}
        selectedFilePath={null}
        session={null}
        sessionErrorMessage={null}
        sessionLoading={false}
        sessionRows={[]}
        statusLabel={() => "Backlog"}
        runtimeStatusValue="idle"
        terminalCommand=""
        terminalContainerRef={{ current: null }}
        terminalStatusValue="idle"
        workspace={{ session_id: "session-1" } as any}
        workspaceCenterTab="conversation"
        workspaceTargetErrorMessage={null}
        workspaceTargetLoading={false}
        workspaceTargetWorktrees={[]}
      />
    );

    expect(view.querySelector(".workspace-conversation-feed")).not.toBeNull();
    expect(view.querySelector(".workspace-conversation-footer")).not.toBeNull();
    expect(
      view.querySelector(
        ".workspace-conversation-footer .workspace-chat-composer"
      )
    ).not.toBeNull();
    expect(view.textContent).not.toContain("Inspector body");

    const toggleButton = view.querySelector(
      'button[aria-label="Open workspace inspector"]'
    );
    expect(toggleButton).not.toBeNull();

    act(() => {
      toggleButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(document.body.textContent).toContain("Inspector body");
    expect(document.body.querySelector('[data-slot="sheet-content"]')).not.toBeNull();
  });
});
