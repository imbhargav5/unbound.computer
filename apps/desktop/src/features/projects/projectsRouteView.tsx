import { useEffect, useState } from "react";

import type { GoalRecord, ProjectRecord } from "../../lib/types";
import { DashboardBreadcrumbs, DetailRow } from "../shared/routePrimitives";

type ProjectDefaultNewChatArea = "repo_root" | "new_worktree";

type SelectOption<T extends string> = {
  label: string;
  value: T;
};

const projectDefaultNewChatAreaOptions: Array<
  SelectOption<ProjectDefaultNewChatArea>
> = [
  { label: "Repo root", value: "repo_root" },
  { label: "New worktree", value: "new_worktree" },
];

export function ProjectsRouteView({
  goals,
  currentProject,
  currentProjectIssueCount,
  currentProjectWorkspaceCount,
  onDeleteProject,
  onOpenCreateProject,
  onUpdateProjectDefaultNewChatArea,
}: {
  goals: GoalRecord[];
  currentProject: ProjectRecord | null;
  currentProjectIssueCount: number;
  currentProjectWorkspaceCount: number;
  onDeleteProject: (projectId: string) => Promise<void>;
  onOpenCreateProject: () => void;
  onUpdateProjectDefaultNewChatArea: (
    projectId: string,
    defaultNewChatArea: ProjectDefaultNewChatArea,
  ) => Promise<void>;
}) {
  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false);
  const [isDeletingProject, setIsDeletingProject] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [isSavingProjectSettings, setIsSavingProjectSettings] = useState(false);
  const [projectSettingsError, setProjectSettingsError] = useState<
    string | null
  >(null);
  const [projectDefaultNewChatAreaDraft, setProjectDefaultNewChatAreaDraft] =
    useState<ProjectDefaultNewChatArea>("repo_root");

  useEffect(() => {
    setIsDeleteDialogOpen(false);
    setIsDeletingProject(false);
    setDeleteError(null);
    setIsSavingProjectSettings(false);
    setProjectSettingsError(null);
    setProjectDefaultNewChatAreaDraft(
      projectDefaultNewChatArea(currentProject),
    );
  }, [
    currentProject?.execution_workspace_policy,
    currentProject?.id,
    currentProject?.updated_at,
  ]);

  const handleConfirmProjectDelete = async () => {
    if (!currentProject || isDeletingProject) {
      return;
    }

    setDeleteError(null);
    setIsDeletingProject(true);

    try {
      await onDeleteProject(currentProject.id);
      setIsDeleteDialogOpen(false);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : String(error));
      setIsDeletingProject(false);
    }
  };

  const handleProjectDefaultNewChatAreaChange = async (value: string) => {
    if (!currentProject || isSavingProjectSettings) {
      return;
    }

    const nextValue = normalizeProjectDefaultNewChatArea(value);
    const previousValue = projectDefaultNewChatArea(currentProject);
    setProjectDefaultNewChatAreaDraft(nextValue);
    setProjectSettingsError(null);

    if (nextValue === previousValue) {
      return;
    }

    setIsSavingProjectSettings(true);
    try {
      await onUpdateProjectDefaultNewChatArea(currentProject.id, nextValue);
    } catch (error) {
      setProjectDefaultNewChatAreaDraft(previousValue);
      setProjectSettingsError(
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setIsSavingProjectSettings(false);
    }
  };

  return (
    <>
      <section className="route-scroll">
        <div className="route-header compact projects-route-header">
          <div>
            <DashboardBreadcrumbs
              items={
                currentProject
                  ? [
                      { label: "Projects" },
                      {
                        label:
                          currentProject.name ??
                          currentProject.title ??
                          "Project",
                      },
                    ]
                  : [{ label: "Projects" }]
              }
            />
            <span className="route-kicker">Projects</span>
            <h1>Repo anchors and ownership</h1>
          </div>

          <button
            className="primary-button"
            onClick={onOpenCreateProject}
            type="button"
          >
            New Project
          </button>
        </div>

        <section className="surface-panel projects-panel">
          <div className="surface-header projects-detail-header">
            <h3>Project Details</h3>
            {currentProject ? (
              <button
                className="secondary-button compact-button destructive-button"
                onClick={() => setIsDeleteDialogOpen(true)}
                type="button"
              >
                Delete Project
              </button>
            ) : null}
          </div>

          {currentProject ? (
            <div className="projects-detail-stack">
              <h2>{currentProject.name}</h2>

              {currentProject.description ? (
                <section className="projects-detail-section">
                  <h3>Description</h3>
                  <p>{currentProject.description}</p>
                </section>
              ) : null}

              <div className="projects-detail-grid">
                <DetailRow label="Status" value={currentProject.status} />
                <DetailRow
                  label="Goal"
                  value={goalTitleForProject(goals, currentProject.goal_id)}
                />
                <DetailRow
                  label="Conversations"
                  value={String(currentProjectIssueCount)}
                />
                <DetailRow
                  label="Worktrees"
                  value={String(currentProjectWorkspaceCount)}
                />
                <DetailRow
                  label="Repo Path"
                  value={currentProject.primary_workspace?.cwd ?? "Missing"}
                />
                <DetailRow
                  label="Repo URL"
                  value={
                    currentProject.primary_workspace?.repo_url ?? "Local only"
                  }
                />
                <DetailRow
                  label="Repo Ref"
                  value={currentProject.primary_workspace?.repo_ref ?? "main"}
                />
              </div>

              <section className="projects-detail-section">
                <h3>Project Settings</h3>
                {projectSettingsError ? (
                  <div className="issue-dialog-alert">
                    {projectSettingsError}
                  </div>
                ) : null}
                <div className="settings-shadcn-form">
                  <div className="settings-shadcn-field settings-shadcn-field-select">
                    <div className="settings-shadcn-field-copy">
                      <strong>Default new chat area</strong>
                      <p>
                        Choose whether new chats for this project start in the
                        repo root or spin up a fresh worktree by default.
                      </p>
                    </div>
                    <div className="settings-shadcn-field-control">
                      <div className="issue-dialog-select-shell">
                        <select
                          className="issue-dialog-select"
                          disabled={isSavingProjectSettings}
                          onChange={(event) =>
                            void handleProjectDefaultNewChatAreaChange(
                              event.target.value,
                            )
                          }
                          value={projectDefaultNewChatAreaDraft}
                        >
                          {projectDefaultNewChatAreaOptions.map((option) => (
                            <option key={option.value} value={option.value}>
                              {option.label}
                            </option>
                          ))}
                        </select>
                        <span
                          aria-hidden="true"
                          className="issue-dialog-select-arrow"
                        >
                          v
                        </span>
                      </div>
                      {isSavingProjectSettings ? (
                        <p className="projects-settings-saving">Saving…</p>
                      ) : null}
                    </div>
                  </div>
                </div>
              </section>
            </div>
          ) : (
            <div className="workspace-empty-state projects-empty-state-panel">
              <h3>Select a project</h3>
              <p>Project repo-anchor configuration appears here.</p>
            </div>
          )}
        </section>
      </section>

      {isDeleteDialogOpen && currentProject ? (
        <DeleteProjectDialogView
          errorMessage={deleteError}
          isDeleting={isDeletingProject}
          issueCount={currentProjectIssueCount}
          onClose={() => {
            if (!isDeletingProject) {
              setIsDeleteDialogOpen(false);
            }
          }}
          onConfirm={() => void handleConfirmProjectDelete()}
          project={currentProject}
          workspaceCount={currentProjectWorkspaceCount}
        />
      ) : null}
    </>
  );
}

export function DeleteProjectDialogView({
  errorMessage,
  isDeleting,
  issueCount,
  onClose,
  onConfirm,
  project,
  workspaceCount,
}: {
  errorMessage: string | null;
  isDeleting: boolean;
  issueCount: number;
  onClose: () => void;
  onConfirm: () => void;
  project: ProjectRecord;
  workspaceCount: number;
}) {
  return (
    <div
      className="modal-backdrop"
      onClick={() => {
        if (!isDeleting) {
          onClose();
        }
      }}
      role="presentation"
    >
      <div
        aria-describedby="delete-project-dialog-description"
        aria-labelledby="delete-project-dialog-title"
        aria-modal="true"
        className="project-dialog project-delete-dialog"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
      >
        <div className="project-dialog-header">
          <div className="project-dialog-title-block">
            <h2 id="delete-project-dialog-title">
              Delete {project.name ?? project.title ?? "project"}?
            </h2>
            <p id="delete-project-dialog-description">
              This will permanently delete this project, all related
              conversations, and all related worktrees. This action cannot be
              undone.
            </p>
          </div>
          <button
            aria-label="Close delete project dialog"
            className="project-dialog-close"
            disabled={isDeleting}
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

          <div className="project-delete-impact-grid">
            <div className="project-delete-impact-card">
              <strong>{issueCount}</strong>
              <span>Conversations will be deleted</span>
            </div>
            <div className="project-delete-impact-card">
              <strong>{workspaceCount}</strong>
              <span>Worktrees will be deleted</span>
            </div>
          </div>

          <p className="project-delete-warning">
            Repository records stay intact, but every board conversation and
            worktree anchored to this project will be removed.
          </p>
        </div>

        <div className="issue-dialog-footer project-dialog-footer">
          <button
            className="secondary-button"
            disabled={isDeleting}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="secondary-button destructive-button"
            disabled={isDeleting}
            onClick={onConfirm}
            type="button"
          >
            {isDeleting ? "Deleting..." : "Delete Project"}
          </button>
        </div>
      </div>
    </div>
  );
}

function normalizeProjectDefaultNewChatArea(
  value: string,
): ProjectDefaultNewChatArea {
  return value === "new_worktree" ? "new_worktree" : "repo_root";
}

function projectDefaultNewChatArea(project: ProjectRecord | null | undefined) {
  return normalizeProjectDefaultNewChatArea(
    project?.execution_workspace_policy === "new_worktree"
      ? "new_worktree"
      : "repo_root",
  );
}

function goalTitleForProject(goals: GoalRecord[], goalId?: string | null) {
  if (!goalId) {
    return "None";
  }

  const goal = goals.find((entry) => entry.id === goalId);
  return goal?.title ?? goalId;
}
