import type { IssueRecord } from "../../lib/types";

type IssuesListTab = "new" | "all";

export function IssuesListView({
  activeTab,
  createLabel = "New conversation",
  emptyDescription = "Conversations own workspaces. Create one to start model work.",
  heading = "CONVERSATIONS",
  issues,
  selectedIssueId,
  summaryText,
  emptyTitle,
  onCreateIssue,
  onTabChange,
  onSelectIssue,
}: {
  activeTab: IssuesListTab;
  createLabel?: string;
  emptyDescription?: string;
  heading?: string;
  issues: IssueRecord[];
  selectedIssueId: string | null;
  summaryText: string;
  emptyTitle: string;
  onCreateIssue?: (() => void) | undefined;
  onTabChange: (tab: IssuesListTab) => void;
  onSelectIssue: (issueId: string) => void;
}) {
  return (
    <section className="issues-route">
      <div className="issues-route-header">
        <div className="issues-route-header-inner">
          <span>{heading}</span>
          {onCreateIssue ? (
            <button
              className="issues-route-create-button"
              onClick={onCreateIssue}
              type="button"
            >
              {createLabel}
            </button>
          ) : null}
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
                    className="issues-list-row-main"
                    style={{
                      paddingLeft: `${20 + issue.request_depth * 12}px`,
                    }}
                  >
                    <span className="issues-list-row-title">
                      {issuesListRowTitle(issue)}
                    </span>
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
            <p>{emptyDescription}</p>
          </div>
        )}
      </div>
    </section>
  );
}

function issuesListTabTitle(tab: IssuesListTab) {
  return tab === "new" ? "New" : "All";
}

function issuesListRowTitle(issue: IssueRecord) {
  if (!(issue.identifier && issue.identifier.trim())) {
    return issue.title;
  }

  return `${issue.identifier}  ${issue.title}`;
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
