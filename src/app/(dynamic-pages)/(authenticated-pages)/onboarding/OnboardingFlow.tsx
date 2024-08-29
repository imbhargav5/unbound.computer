"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";

import { Card } from "@/components/ui/card";

import { OrganizationCreation } from "./OrganizationCreation";
import { ProfileUpdate } from "./ProfileUpdate";
import { TermsAcceptance } from "./TermsAcceptance";

import { Skeleton } from "@/components/ui/skeleton";
import type { Table } from "@/types";
import type { AuthUserMetadata } from "@/utils/zod-schemas/authUserMetadata";

type FLOW_STATE = "TERMS" | "PROFILE" | "ORGANIZATION" | "COMPLETE";

type UserOnboardingFlowProps = {
  userProfile: Table<"user_profiles">;
  onboardingStatus: AuthUserMetadata;
  userEmail: string | undefined;
};

const MotionCard = motion(Card);

function OnboardingComplete() {
  const router = useRouter();
  useEffect(() => {
    router.push("/dashboard");
  }, [router]);
  return <div data-testid="onboarding-complete">
    <Skeleton className="w-full max-w-md" />
  </div>;
}

export function UserOnboardingFlow({
  userProfile,
  onboardingStatus,
  userEmail,
}: UserOnboardingFlowProps) {
  const flowStates = useMemo(() => getAllFlowStates(onboardingStatus), [onboardingStatus]);
  const [currentStep, setCurrentStep] = useState<FLOW_STATE>(
    getInitialFlowState(flowStates, onboardingStatus)
  );

  const nextStep = useCallback(() => {
    setCurrentStep((prevStep) => {
      const currentIndex = flowStates.indexOf(prevStep);
      if (currentIndex < flowStates.length - 1) {
        return flowStates[currentIndex + 1];
      }
      return prevStep;
    });
  }, [currentStep, flowStates]);




  const cardVariants = {
    hidden: { opacity: 0, y: 50 },
    visible: { opacity: 1, y: 0 },
    exit: { opacity: 0, y: -50 },
  };

  return (
    <AnimatePresence mode="wait">
      <MotionCard
        key={currentStep}
        variants={cardVariants}
        initial="hidden"
        animate="visible"
        exit="exit"
        transition={{ duration: 0.3 }}
        className="w-full max-w-md"
      >
        {currentStep === "TERMS" && <TermsAcceptance onSuccess={nextStep} />}
        {currentStep === "PROFILE" && (
          <ProfileUpdate
            userEmail={userEmail}
            userProfile={userProfile}
            onSuccess={nextStep}
          />
        )}
        {currentStep === "ORGANIZATION" && (
          <OrganizationCreation onSuccess={nextStep} />
        )}
        {currentStep === "COMPLETE" && <OnboardingComplete />}
      </MotionCard>
    </AnimatePresence>
  );
}

function getAllFlowStates(onboardingStatus: AuthUserMetadata): FLOW_STATE[] {
  const {
    onboardingHasAcceptedTerms,
    onboardingHasCompletedProfile,
    onboardingHasCreatedOrganization,
  } = onboardingStatus;
  const flowStates: FLOW_STATE[] = [];

  if (!onboardingHasAcceptedTerms) {
    flowStates.push("TERMS");
  }
  if (!onboardingHasCompletedProfile) {
    flowStates.push("PROFILE");
  }
  if (!onboardingHasCreatedOrganization) {
    flowStates.push("ORGANIZATION");
  }
  flowStates.push("COMPLETE");

  return flowStates;
}

function getInitialFlowState(
  flowStates: FLOW_STATE[],
  onboardingStatus: AuthUserMetadata
): FLOW_STATE {
  const {
    onboardingHasAcceptedTerms,
    onboardingHasCompletedProfile,
    onboardingHasCreatedOrganization,
  } = onboardingStatus;

  if (!onboardingHasAcceptedTerms && flowStates.includes("TERMS")) {
    return "TERMS";
  }

  if (!onboardingHasCompletedProfile && flowStates.includes("PROFILE")) {
    return "PROFILE";
  }

  if (
    !onboardingHasCreatedOrganization &&
    flowStates.includes("ORGANIZATION")
  ) {
    return "ORGANIZATION";
  }

  return "COMPLETE";
}
