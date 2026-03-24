import type { ReactNode } from "react";

export interface DashboardBreadcrumbItem {
  label: string;
  onClick?: () => void;
}

export function DashboardBreadcrumbs({
  items,
}: {
  items: DashboardBreadcrumbItem[];
}) {
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

export function MetricCard({
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

export function SummaryPill({
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

export function DetailRow({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="detail-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

export function RoutePlaceholder({
  body,
  title,
}: {
  body: string;
  title: string;
}) {
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

export function BoardPlaceholderView({
  message,
  title,
}: {
  message: string;
  title: string;
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

export function ProjectDialogSelectField({
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
