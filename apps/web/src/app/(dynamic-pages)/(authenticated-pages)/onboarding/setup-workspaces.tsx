"use client";

import { Check } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useOnboarding } from "./onboarding-context";

export function SetupWorkspaces() {
  const { state, pendingInvitations, createWorkspace, goBack } =
    useOnboarding();

  const [selectedInvitations, setSelectedInvitations] = useState<Set<string>>(
    new Set()
  );

  const handleToggleInvitation = (invitationId: string) => {
    setSelectedInvitations((prev) => {
      const newSet = new Set(prev);
      if (newSet.has(invitationId)) {
        newSet.delete(invitationId);
      } else {
        newSet.add(invitationId);
      }
      return newSet;
    });
  };

  const handleConfirm = async () => {
    const acceptedIds =
      selectedInvitations.size > 0
        ? Array.from(selectedInvitations)
        : undefined;
    await createWorkspace(acceptedIds);
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="mb-2 font-semibold text-2xl text-foreground">
          Setup Your Workspace
        </h2>
        <p className="text-muted-foreground">
          We'll create a personal workspace for you
        </p>
      </div>

      {/* Personal workspace info */}
      <Card className="p-6">
        <div className="flex items-start gap-4">
          <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-lg bg-primary/10">
            <svg
              className="h-6 w-6 text-primary"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              viewBox="0 0 24 24"
            >
              <title>Workspace icon</title>
              <path
                d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </div>
          <div className="flex-1">
            <h3 className="mb-1 font-semibold text-foreground">
              Personal Workspace
            </h3>
            <p className="text-muted-foreground text-sm">
              A personal workspace will be created for you automatically. You
              can create team workspaces from the dashboard later.
            </p>
          </div>
        </div>
      </Card>

      {/* Pending invitations */}
      {pendingInvitations.length > 0 && (
        <div className="space-y-3">
          <div>
            <h3 className="mb-1 font-semibold text-foreground">
              Pending Invitations
            </h3>
            <p className="text-muted-foreground text-sm">
              You have {pendingInvitations.length} workspace{" "}
              {pendingInvitations.length === 1 ? "invitation" : "invitations"}.
              Accept the ones you want to join.
            </p>
          </div>

          <div className="space-y-2">
            {pendingInvitations.map((invitation) => {
              const isAccepted = selectedInvitations.has(invitation.id);

              return (
                <Card
                  className={`p-4 transition-all ${
                    isAccepted
                      ? "border-primary bg-primary/5"
                      : "hover:border-primary/50"
                  }`}
                  key={invitation.id}
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="font-medium text-foreground">
                        {invitation.workspace.name}
                      </div>
                      <div className="text-muted-foreground text-sm">
                        Workspace invitation
                      </div>
                    </div>
                    <Button
                      disabled={state.isLoading}
                      onClick={() => handleToggleInvitation(invitation.id)}
                      size="sm"
                      variant={isAccepted ? "default" : "outline"}
                    >
                      {isAccepted ? (
                        <>
                          Accepted <Check className="ml-2 h-4 w-4" />
                        </>
                      ) : (
                        "Accept"
                      )}
                    </Button>
                  </div>
                </Card>
              );
            })}
          </div>

          <p className="text-muted-foreground text-sm">
            Don't worry - you can always accept pending invitations later from
            your dashboard.
          </p>
        </div>
      )}

      {/* Navigation buttons */}
      <div className="flex gap-3 pt-4">
        <Button
          disabled={state.isLoading || !state.completedSteps.has(2)}
          onClick={goBack}
          type="button"
          variant="outline"
        >
          Back
        </Button>
        <Button
          className="flex-1"
          data-testid="finish-setup-button"
          disabled={state.isLoading}
          onClick={handleConfirm}
          size="lg"
        >
          {state.isLoading ? "Setting up..." : "Finish Setup"}
        </Button>
      </div>
    </div>
  );
}
