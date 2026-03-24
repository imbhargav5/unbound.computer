import type { GoalRecord } from "../../lib/types";
import { ProjectDialogSelectField } from "../shared/routePrimitives";

export function CreateProjectDialogView({
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

function humanizeIssueValue(value: string) {
  const normalized = value.replaceAll("_", " ");
  switch (normalized.toLowerCase()) {
    case "issue":
      return "Conversation";
    case "issues":
      return "Conversations";
    case "sub issue":
      return "Queued Message";
    case "sub issues":
      return "Queued Messages";
    case "company":
      return "Space";
    case "companies":
      return "Spaces";
    case "company settings":
      return "Space Settings";
    default:
      return normalized.replace(/\b\w/g, (match) => match.toUpperCase());
  }
}
