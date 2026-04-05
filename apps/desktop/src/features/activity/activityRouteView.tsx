import { useMemo } from "react";

import type {
  AgentRecord,
  IssueCommentRecord,
  IssueRecord,
  IssueRunCardUpdateRecord,
} from "../../lib/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DashboardBreadcrumbs } from "../shared/routePrimitives";

type ActivityFeedTarget = { kind: "issue"; issueId: string };

interface ActivityFeedItem {
  id: string;
  subtitle: string;
  target: ActivityFeedTarget;
  timestamp: Date;
  title: string;
  trailingLabel: string;
}

type BirdsEyeIssueLike = Pick<
  IssueRecord,
  "assignee_adapter_overrides" | "assignee_agent_id"
>;

export function ActivityRouteView({
  agents,
  issues,
  issueCommentsByIssueId,
  issueRunCardUpdatesByIssueId,
  onOpenIssue,
}: {
  agents: AgentRecord[];
  issues: IssueRecord[];
  issueCommentsByIssueId: Record<string, IssueCommentRecord[]>;
  issueRunCardUpdatesByIssueId: Record<string, IssueRunCardUpdateRecord>;
  onOpenIssue: (issueId: string) => void;
}) {
  const feedItems = useMemo(
    () =>
      buildActivityFeedItems(
        issues,
        issueCommentsByIssueId,
        issueRunCardUpdatesByIssueId,
        agents,
      ),
    [agents, issueCommentsByIssueId, issueRunCardUpdatesByIssueId, issues],
  );

  return (
    <section className="flex-1 overflow-y-auto p-6">
      <div className="space-y-2 pb-6">
        <DashboardBreadcrumbs items={[{ label: "Activity" }]} />
        <span className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Activity
        </span>
        <h1 className="text-2xl font-semibold tracking-tight">
          Model activity and conversation messages
        </h1>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Activity</CardTitle>
        </CardHeader>
        <CardContent>
          {feedItems.length ? (
            <div className="divide-y divide-border">
              {feedItems.map((item) => (
                <ActivityFeedRow
                  item={item}
                  key={item.id}
                  onClick={() => onOpenIssue(item.target.issueId)}
                />
              ))}
            </div>
          ) : (
            <p className="py-8 text-center text-sm text-muted-foreground">
              Model runs and conversation messages will appear here.
            </p>
          )}
        </CardContent>
      </Card>
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
    <button
      className="flex w-full items-center justify-between gap-4 px-1 py-3 text-left transition-colors hover:bg-muted/50"
      onClick={onClick}
      type="button"
    >
      <div className="min-w-0 flex-1 space-y-0.5">
        <strong className="block truncate text-sm font-medium">
          {item.title}
        </strong>
        <span className="block truncate text-xs text-muted-foreground">
          {item.subtitle}
        </span>
      </div>
      <Badge variant="outline" className="shrink-0">
        {item.trailingLabel.replaceAll("_", " ")}
      </Badge>
    </button>
  );
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

function detectAgentCliProvider(
  command: string | null | undefined,
  model: string | null | undefined,
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
