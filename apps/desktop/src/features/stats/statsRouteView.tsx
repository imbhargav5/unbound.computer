import { useMemo } from "react";

import type {
  AgentRecord,
  Company,
  CompanySnapshot,
  DesktopBootstrapStatus,
  IssueRecord,
  IssueRunCardUpdateRecord,
  RuntimeCapabilities,
  WorkspaceRecord,
} from "../../lib/types";
import {
  DashboardBreadcrumbs,
  MetricCard,
  SummaryPill,
} from "../shared/routePrimitives";

type BirdsEyeIssueLike = Pick<
  IssueRecord,
  "assignee_adapter_overrides" | "assignee_agent_id"
>;

export function StatsRouteView({
  bootstrap,
  company,
  dependencyCheck,
  issueRunCardUpdatesByIssueId,
  onCheckDependencies,
  onOpenWorkspace,
  repositoriesCount,
  snapshot,
}: {
  bootstrap: DesktopBootstrapStatus;
  company: Company | null;
  dependencyCheck: RuntimeCapabilities | null;
  issueRunCardUpdatesByIssueId: Record<string, IssueRunCardUpdateRecord>;
  onCheckDependencies: () => void;
  onOpenWorkspace: (workspace: WorkspaceRecord) => void;
  repositoriesCount: number;
  snapshot: CompanySnapshot | null;
}) {
  const agents = snapshot?.agents ?? [];
  const issues = snapshot?.issues ?? [];
  const workspaces = snapshot?.workspaces ?? [];
  const issueById = useMemo(
    () => new Map(issues.map((issue) => [issue.id, issue])),
    [issues]
  );
  const visibleConversations = useMemo(
    () =>
      issues.filter(
        (issue) => !issue.hidden_at && isRootConversationIssue(issue)
      ),
    [issues]
  );
  const queuedMessages = useMemo(
    () =>
      issues.filter(
        (issue) => !(issue.hidden_at || isRootConversationIssue(issue))
      ),
    [issues]
  );
  const modelSummaries = useMemo(() => {
    const summaries = new Map<
      string,
      {
        activeRunCount: number;
        conversationIds: Set<string>;
        latestActivityAt: Date | null;
        workspaceCount: number;
      }
    >();

    const ensureSummary = (label: string) => {
      const existing = summaries.get(label);
      if (existing) {
        return existing;
      }

      const next = {
        activeRunCount: 0,
        conversationIds: new Set<string>(),
        latestActivityAt: null as Date | null,
        workspaceCount: 0,
      };
      summaries.set(label, next);
      return next;
    };

    for (const issue of visibleConversations) {
      ensureSummary(issueModelLabel(issue, agents)).conversationIds.add(
        issue.id
      );
    }

    for (const workspace of workspaces) {
      const issue = workspace.issue_id
        ? issueById.get(workspace.issue_id)
        : null;
      ensureSummary(
        issue
          ? issueModelLabel(issue, agents)
          : agentModelLabelById(agents, workspace.agent_id)
      ).workspaceCount += 1;
    }

    for (const update of Object.values(issueRunCardUpdatesByIssueId)) {
      const issue = issueById.get(update.issue_id);
      const summary = ensureSummary(
        issue
          ? issueModelLabel(issue, agents)
          : agentModelLabelById(agents, update.agent_id)
      );
      summary.conversationIds.add(update.issue_id);
      if (update.run_status === "queued" || update.run_status === "running") {
        summary.activeRunCount += 1;
      }
      const activityAt = parseIssueDate(update.last_activity_at);
      if (
        activityAt &&
        (!summary.latestActivityAt ||
          activityAt.getTime() > summary.latestActivityAt.getTime())
      ) {
        summary.latestActivityAt = activityAt;
      }
    }

    return Array.from(summaries.entries())
      .map(([label, summary]) => ({
        label,
        activeRunCount: summary.activeRunCount,
        conversationCount: summary.conversationIds.size,
        latestActivityAt: summary.latestActivityAt,
        workspaceCount: summary.workspaceCount,
      }))
      .sort((left, right) => {
        if (right.activeRunCount !== left.activeRunCount) {
          return right.activeRunCount - left.activeRunCount;
        }
        if (right.conversationCount !== left.conversationCount) {
          return right.conversationCount - left.conversationCount;
        }
        if (right.workspaceCount !== left.workspaceCount) {
          return right.workspaceCount - left.workspaceCount;
        }
        return left.label.localeCompare(right.label);
      });
  }, [
    agents,
    issueById,
    issueRunCardUpdatesByIssueId,
    visibleConversations,
    workspaces,
  ]);
  const recentModelUpdates = useMemo(() => {
    return Object.values(issueRunCardUpdatesByIssueId)
      .map((update) => ({
        issue: issueById.get(update.issue_id) ?? null,
        update,
      }))
      .filter(
        (
          entry
        ): entry is { issue: IssueRecord; update: IssueRunCardUpdateRecord } =>
          entry.issue !== null && entry.issue.hidden_at == null
      )
      .sort((left, right) => {
        const leftDate =
          parseIssueDate(left.update.last_activity_at)?.getTime() ?? 0;
        const rightDate =
          parseIssueDate(right.update.last_activity_at)?.getTime() ?? 0;
        return rightDate - leftDate;
      })
      .slice(0, 6);
  }, [issueById, issueRunCardUpdatesByIssueId]);
  const activeModelCount = modelSummaries.filter(
    (summary) => summary.activeRunCount > 0
  ).length;

  return (
    <section className="route-scroll">
      <div className="route-header">
        <DashboardBreadcrumbs items={[{ label: "Stats" }]} />
        <span className="route-kicker">Stats</span>
        <h1>{company?.name ?? "Unbound"}</h1>
        <p>
          {company?.description ??
            "A quick view of conversation volume, queued follow-ups, active worktrees, and which models are doing the work."}
        </p>
      </div>

      <div className="metric-grid">
        <MetricCard label="Conversations" value={visibleConversations.length} />
        <MetricCard label="Queued Messages" value={queuedMessages.length} />
        <MetricCard label="Models" value={modelSummaries.length} />
        <MetricCard label="Active Models" value={activeModelCount} />
        <MetricCard label="Projects" value={snapshot?.projects.length ?? 0} />
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
          <h3>Models</h3>
          {modelSummaries.length ? (
            <div className="surface-list">
              {modelSummaries.map((summary) => (
                <div className="surface-list-row" key={summary.label}>
                  <div>
                    <strong>{summary.label}</strong>
                    <span>
                      {summary.conversationCount}{" "}
                      {summary.conversationCount === 1
                        ? "conversation"
                        : "conversations"}{" "}
                      touched · {summary.workspaceCount} worktrees
                    </span>
                  </div>
                  <span>
                    {summary.activeRunCount > 0
                      ? `${summary.activeRunCount} live`
                      : summary.latestActivityAt
                        ? formatRelativeIssueDate(
                            summary.latestActivityAt.toISOString()
                          )
                        : "Idle"}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="surface-empty-copy">
              Models will appear here after the first configured run.
            </p>
          )}
        </section>

        <section className="surface-panel">
          <h3>Recent Model Work</h3>
          {recentModelUpdates.length ? (
            <div className="surface-list">
              {recentModelUpdates.map(({ issue, update }) => (
                <div className="surface-list-row" key={update.run_id}>
                  <div>
                    <strong>{issueModelLabel(issue, agents)}</strong>
                    <span>
                      {issue.identifier ?? issue.title} ·{" "}
                      {issueRunCardUpdateSummary(update)}
                    </span>
                  </div>
                  <span>
                    {formatCompactIssueTimestamp(update.last_activity_at)}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="surface-empty-copy">
              Model activity will appear here once runs start landing.
            </p>
          )}
        </section>

        <section className="surface-panel">
          <h3>Active Worktrees</h3>
          {workspaces.length ? (
            <div className="surface-list">
              {workspaces.map((workspace) => (
                <button
                  className="file-list-button"
                  key={workspace.id}
                  onClick={() => onOpenWorkspace(workspace)}
                  type="button"
                >
                  <strong>
                    {workspace.issue_identifier ?? workspace.title}
                  </strong>
                  <span>
                    {[
                      workspace.issue_title,
                      workspace.project_name,
                      workspace.issue_id
                        ? issueModelLabel(
                            issueById.get(workspace.issue_id) ?? null,
                            agents
                          )
                        : agentModelLabelById(agents, workspace.agent_id),
                    ]
                      .filter(Boolean)
                      .join(" · ") ||
                      workspace.workspace_status ||
                      "worktree"}
                  </span>
                </button>
              ))}
            </div>
          ) : (
            <p className="surface-empty-copy">
              Worktrees appear here once a conversation launches a run.
            </p>
          )}
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
            ? (capability.path ?? "Installed and ready")
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

function isRootConversationIssue(issue: IssueRecord) {
  return (issue.parent_id?.trim() ?? "").length === 0;
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

function issueModelLabel(
  issue: BirdsEyeIssueLike | null | undefined,
  agents: AgentRecord[]
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

function agentModelLabelById(agents: AgentRecord[], agentId?: string | null) {
  if (!agentId) {
    return "Unknown model";
  }

  const agent = agents.find((entry) => entry.id === agentId);
  return agent ? agentModelLabel(agent) : agentId;
}

function agentModelLabel(agent: AgentRecord) {
  const mergedRuntimeConfig = {
    ...objectFromUnknown(agent.adapter_config),
    ...objectFromUnknown(agent.runtime_config),
  };
  return runtimeModelLabel(mergedRuntimeConfig);
}

function runtimeModelLabel(
  runtimeConfig: Record<string, unknown> | null | undefined
) {
  const configuredModel = stringFromUnknown(runtimeConfig?.model).trim();
  if (configuredModel && configuredModel.toLowerCase() !== "default") {
    return configuredModel;
  }

  return providerLabelForRuntimeConfig(
    stringFromUnknown(runtimeConfig?.command),
    configuredModel
  );
}

function providerLabelForRuntimeConfig(
  command: string | null | undefined,
  model: string | null | undefined
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

function detectAgentCliProvider(
  command: string | null | undefined,
  model: string | null | undefined
) {
  const normalizedCommand = String(command ?? "").toLowerCase();
  const normalizedModel = String(model ?? "").toLowerCase();

  if (
    normalizedCommand.includes("codex") ||
    normalizedModel.includes("gpt") ||
    normalizedModel.includes("codex") ||
    normalizedModel.includes("o1") ||
    normalizedModel.includes("o3") ||
    normalizedModel.includes("o4")
  ) {
    return "codex";
  }

  if (
    normalizedCommand.includes("claude") ||
    normalizedModel.includes("claude")
  ) {
    return "claude";
  }

  return "default";
}

function objectFromUnknown(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object") {
    return {};
  }
  return value as Record<string, unknown>;
}

function stringFromUnknown(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}
