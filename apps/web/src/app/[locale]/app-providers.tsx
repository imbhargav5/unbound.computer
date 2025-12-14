"use client";
import dynamic from "next/dynamic";
import { AppProgressBar as ProgressBar } from "next-nprogress-bar";
import { Suspense } from "react";
import { Toaster } from "@/components/ui/sonner";
import { PHProvider } from "@/contexts/post-hog-provider";
import { useMyReportWebVitals } from "./report-web-vitals";

const PostHogPageView = dynamic(() => import("./post-hog-page-view"), {
  ssr: false,
});

/**
 * This is a wrapper for the app that provides the supabase client, the router event wrapper
 * supabase listener, and the navigation progress bar.
 *
 * The listener is used to listen for changes to the user's session and update the UI accordingly.
 */
export function AppProviders() {
  useMyReportWebVitals();

  return (
    <PHProvider>
      <Suspense>
        <ProgressBar
          color="#0047ab"
          height="4px"
          options={{ showSpinner: false }}
          shallowRouting
        />
        <PostHogPageView />
        <Toaster />
      </Suspense>
    </PHProvider>
  );
}
