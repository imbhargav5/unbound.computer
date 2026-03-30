export function CreateProjectDialogView({
  repoPath,
  derivedProjectName,
  isSaving,
  errorMessage,
  onChooseFolder,
  onCreate,
  onClose,
}: {
  repoPath: string;
  derivedProjectName: string;
  isSaving: boolean;
  errorMessage: string | null;
  onChooseFolder: () => void;
  onCreate: () => void;
  onClose: () => void;
}) {
  const canCreate = Boolean(derivedProjectName) && !isSaving;

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        aria-labelledby="create-project-dialog-title"
        aria-modal="true"
        className="project-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="create-project-dialog-title">New repository</h2>
            <p>Add a repository folder to your space.</p>
          </div>

          <button
            aria-label="Close create repository dialog"
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
                    {repoPath || "Choose a repository folder"}
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
                We&apos;ll use the selected folder name as the repository title.
              </small>
            </div>

            <div className="project-dialog-field project-dialog-field-full">
              <span className="issue-dialog-label">Repository name</span>
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
                You can rename the repository later from its detail page.
              </small>
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
            {isSaving ? "Adding repository..." : "Add repository"}
          </button>
        </div>
      </div>
    </div>
  );
}
