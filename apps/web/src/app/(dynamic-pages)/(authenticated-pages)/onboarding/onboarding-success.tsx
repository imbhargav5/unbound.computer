"use client";

import confetti from "canvas-confetti";
import { ArrowRight, CheckCircle2 } from "lucide-react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";

type OnboardingSuccessProps = {
  avatarUrl?: string;
  fullName?: string;
};

export function OnboardingSuccess({
  avatarUrl,
  fullName,
}: OnboardingSuccessProps) {
  const router = useRouter();
  const [isPrefetched, setIsPrefetched] = useState(false);

  useEffect(() => {
    // Trigger confetti celebration
    const duration = 2500;
    const end = Date.now() + duration;

    const frame = () => {
      confetti({
        particleCount: 2,
        angle: 60,
        spread: 55,
        origin: { x: 0 },
      });

      confetti({
        particleCount: 2,
        angle: 120,
        spread: 55,
        origin: { x: 1 },
      });

      if (Date.now() < end) {
        requestAnimationFrame(frame);
      }
    };

    frame();

    // Prefetch dashboard route
    router.prefetch("/dashboard");
    setIsPrefetched(true);
  }, [router]);

  const handleContinue = () => {
    router.push("/dashboard");
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-6">
      <div className="w-full max-w-md space-y-8 text-center">
        {/* Success icon and avatar */}
        <div className="flex flex-col items-center gap-4">
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-primary/10">
            <CheckCircle2 className="h-12 w-12 text-primary" />
          </div>
          {avatarUrl ? (
            <div className="relative h-16 w-16 overflow-hidden rounded-full border-2 border-border">
              <Image
                alt={fullName || "Profile"}
                className="object-cover"
                fill
                src={avatarUrl}
              />
            </div>
          ) : null}
        </div>

        {/* Success message */}
        <div className="space-y-3">
          <h1 className="font-bold text-3xl text-foreground">
            You're all set{fullName ? `, ${fullName.split(" ")[0]}` : ""}!
          </h1>
          <p className="text-lg text-muted-foreground">
            Your account is ready to go. Let's get started!
          </p>
        </div>

        {/* Continue button */}
        <div className="pt-4">
          <Button
            className="group"
            data-testid="go-to-dashboard-button"
            disabled={!isPrefetched}
            onClick={handleContinue}
            size="lg"
          >
            Go to Dashboard
            <ArrowRight className="ml-2 h-5 w-5 transition-transform group-hover:translate-x-1" />
          </Button>
        </div>

        {/* Subtle hint */}
        <p className="text-muted-foreground text-sm">
          You can always update your profile and settings later
        </p>
      </div>
    </div>
  );
}
