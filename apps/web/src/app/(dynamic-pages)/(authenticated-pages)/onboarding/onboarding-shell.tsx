import type { ReactNode } from "react";
import { Card } from "@/components/ui/card";

type OnboardingShellProps = {
  progress: ReactNode;
  content: ReactNode;
  className?: string;
};

export function OnboardingShell({
  progress,
  content,
  className = "",
}: OnboardingShellProps) {
  return (
    <div
      className={`flex min-h-screen items-center justify-center bg-background p-4 sm:p-6 lg:p-8 ${className}`}
    >
      <div className="w-full max-w-2xl space-y-6">
        {/* Progress indicator */}
        {progress}

        {/* Main card */}
        <Card className="p-6 sm:p-8 lg:p-10">{content}</Card>
      </div>
    </div>
  );
}
