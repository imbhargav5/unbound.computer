"use client";

import { useEffect, useState } from "react";
import { useOnboarding } from "./onboarding-context";
import { OnboardingProgress } from "./onboarding-progress";
import { OnboardingShell } from "./onboarding-shell";
import { OnboardingSuccess } from "./onboarding-success";
import { ProfileUpdate } from "./profile-update";
import { SetupWorkspaces } from "./setup-workspaces";
import { TermsAcceptance } from "./terms-acceptance";

export function OnboardingFlowContent() {
  const { state, userProfile, avatarUrl } = useOnboarding();

  const [workspaceSlug, setWorkspaceSlug] = useState<string | undefined>();

  // Track workspace slug for redirect after success
  useEffect(() => {
    // This would be set after workspace creation
    // For now, we'll use a default or fetch from user's default workspace
    setWorkspaceSlug("personal");
  }, []);

  // Show success screen
  if (state.currentStep === "success") {
    return (
      <OnboardingSuccess
        avatarUrl={avatarUrl}
        fullName={userProfile.full_name ?? undefined}
        workspaceSlug={workspaceSlug}
      />
    );
  }

  // Get current step content
  let stepContent: React.ReactNode = null;
  if (state.currentStep === 1) {
    stepContent = <TermsAcceptance />;
  } else if (state.currentStep === 2) {
    stepContent = <ProfileUpdate />;
  } else if (state.currentStep === 3) {
    stepContent = <SetupWorkspaces />;
  }

  return (
    <OnboardingShell
      content={<div className="onboarding-step-transition">{stepContent}</div>}
      progress={
        <OnboardingProgress
          completedSteps={state.completedSteps}
          currentStep={state.currentStep as 1 | 2 | 3}
        />
      }
    />
  );
}
