"use client";

import { GeistSans } from "geist/font/sans";
import { AlertCircle } from "lucide-react";
import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Typography } from "@/components/ui/typography-ui";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log the error to console for debugging
    console.error("Global error:", error);
    if (error.digest) {
      console.error("Error digest:", error.digest);
    }
  }, [error]);

  return (
    <html className={GeistSans.className} lang="en">
      <body className="flex min-h-screen flex-col bg-background">
        <div className="flex min-h-screen flex-col items-center justify-center px-4">
          <div className="flex max-w-md flex-col items-center space-y-6 text-center">
            <div className="flex items-center justify-center">
              <AlertCircle className="h-16 w-16 text-muted-foreground" />
            </div>
            <Typography.H1>Something went wrong!</Typography.H1>
            <Typography.P>
              We encountered an unexpected error. Please try again or contact
              support if the problem persists.
            </Typography.P>
            {error.digest && (
              <Typography.Subtle className="font-mono text-xs">
                Error ID: {error.digest}
              </Typography.Subtle>
            )}
            <Button className="mt-4" onClick={() => reset()} size="lg">
              Try again
            </Button>
          </div>
        </div>
      </body>
    </html>
  );
}
