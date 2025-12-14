"use client";

import { useAction } from "next-cool-action/hooks";
import { useRef } from "react";
import { toast } from "sonner";
import { T } from "@/components/ui/typography-ui";
import {
  approveProjectAction,
  markProjectAsCompletedAction,
  rejectProjectAction,
  submitProjectForApprovalAction,
} from "@/data/user/projects";
import type { Enum } from "@/types";
import { getSafeActionErrorMessage } from "@/utils/error-message";
import { ConfirmApproveProjectDialog } from "./confirm-approve-project-dialog";
import { ConfirmMarkProjectAsCompleteDialog } from "./confirm-mark-project-as-complete-dialog";
import { ConfirmRejectProjectDialog } from "./confirm-reject-project-dialog";
import { SubmitProjectForApprovalDialog } from "./submit-project-for-approval-dialog";

type ProjectStatus = Enum<"project_status">;

interface ApprovalControlActionsProps {
  projectId: string;
  projectSlug: string;
  canManage: boolean;
  canOnlyEdit: boolean;
  projectStatus: ProjectStatus;
}

export function ApprovalControlActions({
  projectId,
  projectSlug,
  canManage,
  canOnlyEdit,
  projectStatus,
}: ApprovalControlActionsProps) {
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: submitProjectForApproval } = useAction(
    submitProjectForApprovalAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Submitting project for approval...");
      },
      onSuccess: () => {
        toast.success("Project submitted for approval!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        toast.error(
          getSafeActionErrorMessage(
            error,
            "Failed to submit project for approval"
          ),
          { id: toastRef.current }
        );
        toastRef.current = undefined;
      },
    }
  );

  const { execute: markProjectAsCompleted } = useAction(
    markProjectAsCompletedAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Marking project as complete...");
      },
      onSuccess: () => {
        toast.success("Project marked as complete!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        toast.error(
          getSafeActionErrorMessage(
            error,
            "Failed to mark project as complete"
          ),
          { id: toastRef.current }
        );
        toastRef.current = undefined;
      },
    }
  );

  const { execute: approveProject } = useAction(approveProjectAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Approving project...");
    },
    onSuccess: () => {
      toast.success("Project approved!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        getSafeActionErrorMessage(error, "Failed to approve project"),
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
  });

  const { execute: rejectProject } = useAction(rejectProjectAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Rejecting project...");
    },
    onSuccess: () => {
      toast.success("Project rejected!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        getSafeActionErrorMessage(error, "Failed to reject project"),
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
  });

  return (
    <>
      {projectStatus === "draft" ? (
        canManage ? (
          <ConfirmMarkProjectAsCompleteDialog
            onConfirm={() => markProjectAsCompleted({ projectId, projectSlug })}
          />
        ) : canOnlyEdit ? (
          <SubmitProjectForApprovalDialog
            onSubmit={() =>
              submitProjectForApproval({ projectId, projectSlug })
            }
          />
        ) : null
      ) : null}
      {!canManage && projectStatus === "pending_approval" ? (
        <T.P className="text-green-600 text-xs italic">Awaiting approval</T.P>
      ) : null}
      {canManage && projectStatus === "pending_approval" && (
        <>
          <ConfirmApproveProjectDialog
            onConfirm={() => approveProject({ projectId, projectSlug })}
          />
          <ConfirmRejectProjectDialog
            onConfirm={() => rejectProject({ projectId, projectSlug })}
          />
        </>
      )}
      {projectStatus === "approved" && canManage ? (
        <ConfirmMarkProjectAsCompleteDialog
          onConfirm={() => markProjectAsCompleted({ projectId, projectSlug })}
        />
      ) : null}
    </>
  );
}
