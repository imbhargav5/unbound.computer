"use client";

import { useOnboarding } from "./onboarding-context";
import { OnboardingProgress } from "./onboarding-progress";
import { OnboardingShell } from "./onboarding-shell";
import { OnboardingSuccess } from "./onboarding-success";
import { ProfileUpdate } from "./profile-update";
import { TermsAcceptance } from "./terms-acceptance";

export function OnboardingFlowContent() {
  const { state, userProfile, avatarUrl } = useOnboarding();

  // Show success screen
  if (state.currentStep === "success") {
    return (
      <OnboardingSuccess
        avatarUrl={avatarUrl}
        fullName={userProfile.full_name ?? undefined}
      />
    );
  }

  // Get current step content
  let stepContent: React.ReactNode = null;
  if (state.currentStep === 1) {
    stepContent = <TermsAcceptance />;
  } else if (state.currentStep === 2) {
    stepContent = <ProfileUpdate />;
  }

  return (
    <OnboardingShell
      content={<div className="onboarding-step-transition">{stepContent}</div>}
      progress={
        <OnboardingProgress
          completedSteps={state.completedSteps}
          currentStep={state.currentStep as 1 | 2}
        />
      }
    />
  );
}
