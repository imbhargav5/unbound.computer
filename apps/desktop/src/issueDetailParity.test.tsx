// @vitest-environment jsdom

import { act, type ReactElement, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

vi.mock("@xterm/xterm", () => ({
  Terminal: class Terminal {},
}));

import {
  BirdsEyeQuickCreateRow,
  WorkspaceChatComposer,
  WorkspaceInspectorSidebar,
  WorkspaceRuntimeStatusLine,
  WorkspaceSessionHeaderCard,
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
      const [thinking, setThinking] = useState("auto");
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
            thinkingEffortOptions={["auto", "high"]}
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
        selectedThinkingEffort="auto"
        thinkingEffortOptions={["auto"]}
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
          thinkingEffort: "auto",
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

    expect(providerSelect).not.toBeNull();
    expect(modelSelect).not.toBeNull();
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
        currentDirectory="/tmp/repo"
        fileEntries={[]}
        gitCommitMessage="Ship README change"
        gitHistory={gitHistory}
        gitState={gitState}
        hasUncommittedChanges
        hasUnpushedCommits={false}
        issueMeta={<div>Issue metadata</div>}
        isWorking={false}
        onDiscardFile={() => undefined}
        onGitCommit={onGitCommit}
        onGitCommitMessageChange={() => undefined}
        onGitPush={() => undefined}
        onOpenDiff={() => undefined}
        onOpenDirectory={() => undefined}
        onOpenFile={() => undefined}
        onSelectSidebarTab={onSelectSidebarTab}
        onStageFile={() => undefined}
        onUnstageFile={() => undefined}
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

  it("renders the session header and runtime line like the chat shell", () => {
    const view = render(
      <div>
        <WorkspaceSessionHeaderCard
          agentLabel="Founding Engineer"
          issueLabel="Add descriptions to README"
          renderedCount={12}
          sessionId="session-123"
          title="FUN-5"
        />
        <WorkspaceRuntimeStatusLine
          detail="Daemon connected"
          status="running"
          tone="running"
        />
      </div>
    );

    expect(view.textContent).toContain("Rendered");
    expect(view.textContent).toContain("running");
    expect(view.textContent).toContain("Daemon connected");
  });
});
