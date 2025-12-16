"use client";

import { Check, X } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { T } from "@/components/type-system";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  acceptInvitationAction,
  declineInvitationAction,
} from "@/data/user/invitation";

interface InvitationContentProps {
  invitationId: string;
  inviterName: string;
  workspaceName: string;
  inviteeRole: string;
  status: "active" | "finished_accepted" | "finished_declined" | "inactive";
}

export function InvitationContent({
  invitationId,
  inviterName,
  workspaceName,
  inviteeRole,
  status,
}: InvitationContentProps) {
  const [acceptDialogOpen, setAcceptDialogOpen] = useState(false);
  const [declineDialogOpen, setDeclineDialogOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);
  const { execute: acceptInvitation, isPending: isAccepting } = useAction(
    acceptInvitationAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Accepting invitation...");
      },
      onNavigation: () => {
        toast.success("Invitation accepted!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to accept invitation";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setAcceptDialogOpen(false);
      },
    }
  );

  const { execute: declineInvitation, isPending: isDeclining } = useAction(
    declineInvitationAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Declining invitation...");
      },
      onNavigation: () => {
        toast.success("Invitation declined", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage =
          error.serverError ?? "Failed to decline invitation";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setDeclineDialogOpen(false);
      },
    }
  );

  // Handle different invitation statuses
  switch (status) {
    case "finished_accepted":
      return (
        <div className="mx-auto max-w-md space-y-4 text-center">
          <div className="flex justify-center">
            <div className="rounded-full bg-green-100 p-4 dark:bg-green-900/30">
              <svg
                className="h-12 w-12 text-green-600 dark:text-green-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  d="M5 13l4 4L19 7"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                />
              </svg>
            </div>
          </div>
          <T.Heading2>Invitation Already Accepted</T.Heading2>
          <T.Text>
            You have already accepted the invitation to join{" "}
            <strong>{workspaceName}</strong>.
          </T.Text>
          <T.Text className="text-muted-foreground text-sm">
            You should be redirected to the workspace shortly. If not, please
            navigate to your workspace from the dashboard.
          </T.Text>
        </div>
      );

    case "finished_declined":
      return (
        <div className="mx-auto max-w-md space-y-4 text-center">
          <div className="flex justify-center">
            <div className="rounded-full bg-gray-100 p-4 dark:bg-gray-800">
              <svg
                className="h-12 w-12 text-gray-600 dark:text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  d="M6 18L18 6M6 6l12 12"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                />
              </svg>
            </div>
          </div>
          <T.Heading2>Invitation Declined</T.Heading2>
          <T.Text>
            You have declined the invitation to join{" "}
            <strong>{workspaceName}</strong>.
          </T.Text>
          <T.Text className="text-muted-foreground text-sm">
            If you change your mind, please contact {inviterName} for a new
            invitation.
          </T.Text>
        </div>
      );

    case "inactive":
      return (
        <div className="mx-auto max-w-md space-y-4 text-center">
          <div className="flex justify-center">
            <div className="rounded-full bg-orange-100 p-4 dark:bg-orange-900/30">
              <svg
                className="h-12 w-12 text-orange-600 dark:text-orange-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                />
              </svg>
            </div>
          </div>
          <T.Heading2>Invitation No Longer Valid</T.Heading2>
          <T.Text>
            This invitation to join <strong>{workspaceName}</strong> is no
            longer active.
          </T.Text>
          <T.Text className="text-muted-foreground text-sm">
            The invitation may have been revoked or expired. Please contact{" "}
            {inviterName} if you believe this is an error.
          </T.Text>
        </div>
      );

    case "active":
    default:
      // Show active invitation with action buttons
      return (
        <div className="mx-auto max-w-md space-y-4">
          <T.Heading2>Invitation from {inviterName}</T.Heading2>
          <div className="space-y-4">
            <div className="rounded-lg border bg-card p-4">
              <T.Text>
                You have been invited to join{" "}
                <strong className="text-lg">{workspaceName}</strong> as a{" "}
                <span className="inline-flex items-center rounded-md bg-primary/10 px-2 py-1 font-medium text-primary text-sm ring-1 ring-primary/20 ring-inset">
                  {inviteeRole}
                </span>
              </T.Text>
            </div>
            <div className="flex gap-2">
              {/* Accept Dialog */}
              <Dialog
                onOpenChange={setAcceptDialogOpen}
                open={acceptDialogOpen}
              >
                <DialogTrigger asChild>
                  <Button
                    data-testid="dialog-accept-invitation-trigger"
                    size="default"
                    variant="default"
                  >
                    <Check className="mr-2 h-5 w-5" /> Accept Invitation
                  </Button>
                </DialogTrigger>
                <DialogContent
                  className="sm:max-w-[425px]"
                  data-testid="dialog-accept-invitation-content"
                >
                  <DialogHeader>
                    <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
                      <Check className="h-6 w-6" />
                    </div>
                    <div className="p-1">
                      <DialogTitle className="text-lg">
                        Accept Invitation
                      </DialogTitle>
                      <DialogDescription className="text-base">
                        Are you sure you want to accept this invitation?
                      </DialogDescription>
                    </div>
                  </DialogHeader>
                  <DialogFooter className="mt-4">
                    <Button
                      data-testid="cancel"
                      disabled={isAccepting}
                      onClick={() => setAcceptDialogOpen(false)}
                      type="button"
                      variant="outline"
                    >
                      Cancel
                    </Button>
                    <Button
                      data-testid="confirm"
                      disabled={isAccepting}
                      onClick={() => {
                        acceptInvitation({ invitationId });
                      }}
                      type="button"
                      variant="default"
                    >
                      {isAccepting ? "Accepting..." : "Accept"}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>

              {/* Decline Dialog */}
              <Dialog
                onOpenChange={setDeclineDialogOpen}
                open={declineDialogOpen}
              >
                <DialogTrigger asChild>
                  <Button
                    data-testid="dialog-decline-invitation-trigger"
                    size="default"
                    variant="outline"
                  >
                    <X className="mr-2 h-5 w-5" /> Decline Invitation
                  </Button>
                </DialogTrigger>
                <DialogContent
                  className="sm:max-w-[425px]"
                  data-testid="dialog-decline-invitation-content"
                >
                  <DialogHeader>
                    <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
                      <X className="h-6 w-6" />
                    </div>
                    <div className="p-1">
                      <DialogTitle className="text-lg">
                        Decline Invitation
                      </DialogTitle>
                      <DialogDescription className="text-base">
                        Are you sure you want to decline this invitation?
                      </DialogDescription>
                    </div>
                  </DialogHeader>
                  <DialogFooter className="mt-4">
                    <Button
                      data-testid="cancel"
                      disabled={isDeclining}
                      onClick={() => setDeclineDialogOpen(false)}
                      type="button"
                      variant="outline"
                    >
                      Cancel
                    </Button>
                    <Button
                      data-testid="confirm"
                      disabled={isDeclining}
                      onClick={() => {
                        declineInvitation({ invitationId });
                      }}
                      type="button"
                      variant="destructive"
                    >
                      {isDeclining ? "Declining..." : "Decline"}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </div>
          </div>
        </div>
      );
  }
}
