import type { IssueRecord } from "../../lib/types";
import { DashboardBreadcrumbs } from "../shared/routePrimitives";

type IssuesListTab = "new" | "all";

export function IssuesListView({
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
          <DashboardBreadcrumbs items={[{ label: "Conversations" }]} />
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
              Conversations hold the context, and model worktrees spin up when a
              run starts.
            </p>
          </div>
        )}
      </div>
    </section>
  );
}

function IssueListStatusIcon({ status }: { status: string }) {
  switch (status) {
    case "done":
      return "✓";
    case "in_progress":
      return "↗";
    case "blocked":
      return "!";
    case "cancelled":
      return "×";
    default:
      return "•";
  }
}

function issuesListTabTitle(tab: IssuesListTab) {
  return tab === "new" ? "New" : "All";
}

function normalizeBoardIssueValue(value: string | null | undefined) {
  const normalized = (value ?? "").trim().toLowerCase().replaceAll(" ", "_");

  if (!normalized) {
    return "backlog";
  }

  if (normalized === "todo") {
    return "todo";
  }

  if (normalized === "to_do") {
    return "todo";
  }

  if (normalized === "inprogress") {
    return "in_progress";
  }

  if (normalized === "cancelled" || normalized === "canceled") {
    return "cancelled";
  }

  return normalized;
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
