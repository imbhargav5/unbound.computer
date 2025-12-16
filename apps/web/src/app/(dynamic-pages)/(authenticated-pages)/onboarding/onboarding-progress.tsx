"use client";

import { Check } from "lucide-react";

type OnboardingStep = 1 | 2 | 3;

type OnboardingProgressProps = {
  currentStep: OnboardingStep;
  completedSteps: Set<number>;
};

const STEPS = [
  { number: 1, label: "Terms" },
  { number: 2, label: "Profile" },
  { number: 3, label: "Workspace" },
] as const;

export function OnboardingProgress({
  currentStep,
  completedSteps,
}: OnboardingProgressProps) {
  return (
    <div className="w-full">
      {/* Horizontal stepper */}
      <div className="flex items-center justify-center gap-2 sm:gap-4">
        {STEPS.map((step, index) => {
          const isCompleted = completedSteps.has(step.number);
          const isCurrent = currentStep === step.number;

          return (
            <div className="flex items-center" key={step.number}>
              {/* Step indicator */}
              <div className="flex flex-col items-center gap-2">
                <div
                  className={`flex items-center justify-center rounded-full transition-all ${
                    isCompleted
                      ? "h-8 w-8 bg-primary text-primary-foreground sm:h-10 sm:w-10"
                      : isCurrent
                        ? "h-10 w-10 bg-primary text-primary-foreground ring-4 ring-primary/20 sm:h-12 sm:w-12"
                        : "h-8 w-8 bg-muted text-muted-foreground sm:h-10 sm:w-10"
                  }`}
                >
                  {isCompleted ? (
                    <Check className="h-4 w-4 sm:h-5 sm:w-5" />
                  ) : (
                    <span className="font-semibold text-sm sm:text-base">
                      {step.number}
                    </span>
                  )}
                </div>
                <div
                  className={`whitespace-nowrap font-medium text-xs transition-colors sm:text-sm ${
                    isCompleted || isCurrent
                      ? "text-foreground"
                      : "text-muted-foreground"
                  }`}
                >
                  {step.label}
                </div>
              </div>

              {/* Connector line */}
              {index < STEPS.length - 1 && (
                <div
                  className={`mx-2 h-0.5 w-12 transition-colors sm:w-20 ${
                    isCompleted ? "bg-primary" : "bg-border"
                  }`}
                />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
