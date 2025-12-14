"use client";

import { format, startOfMonth } from "date-fns";
import { Button } from "@/components/ui/button";
import { useOnboarding } from "./onboarding-context";

export function TermsAcceptance() {
  const { state, acceptTerms } = useOnboarding();

  return (
    <div className="space-y-6">
      <div>
        <h2 className="mb-2 font-semibold text-2xl text-foreground">
          Welcome to Nextbase Ultimate
        </h2>
        <p className="text-muted-foreground">
          Please review our terms of service before proceeding
        </p>
      </div>

      {/* Terms content */}
      <div className="rounded-lg border bg-muted p-6">
        <h3 className="mb-2 font-semibold text-foreground">Terms of Service</h3>
        <p className="mb-4 text-muted-foreground text-sm">
          Last updated: {format(startOfMonth(new Date()), "MMMM d, yyyy")}
        </p>
        <div className="max-h-64 space-y-3 overflow-y-auto text-foreground text-sm">
          <p>
            Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam
            auctor, nunc id aliquam tincidunt, nisl nunc tincidunt nunc, nec
            tincidunt nunc nunc id nunc. Sed euismod, nunc id aliquam tincidunt,
            nisl nunc tincidunt nunc, nec tincidunt nunc nunc id nunc.
          </p>
          <p>
            Vestibulum ante ipsum primis in faucibus orci luctus et ultrices
            posuere cubilia curae; Donec velit neque, auctor sit amet aliquam
            vel, ullamcorper sit amet ligula. Proin eget tortor risus.
          </p>
          <p>
            Curabitur aliquet quam id dui posuere blandit. Curabitur arcu erat,
            accumsan id imperdiet et, porttitor at sem. Vivamus magna justo,
            lacinia eget consectetur sed, convallis at tellus.
          </p>
          <p>
            Nulla porttitor accumsan tincidunt. Pellentesque in ipsum id orci
            porta dapibus. Vestibulum ac diam sit amet quam vehicula elementum
            sed sit amet dui.
          </p>
        </div>
      </div>

      {/* Accept button */}
      <div className="flex justify-end pt-4">
        <Button
          data-testid="accept-terms-button"
          disabled={state.isLoading}
          onClick={acceptTerms}
          size="lg"
        >
          {state.isLoading ? "Accepting..." : "Accept & Continue"}
        </Button>
      </div>
    </div>
  );
}
