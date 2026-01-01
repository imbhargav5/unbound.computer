import { notFound } from "next/navigation";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { SessionViewerClient } from "./session-viewer-client";

interface SessionPageProps {
  params: Promise<{ sessionId: string }>;
}

export const metadata = {
  title: "Session Viewer",
  description: "View a real-time Claude Code session",
};

/**
 * Generate a short-lived viewer token for the session
 * This is a placeholder - in production, use a proper token service
 */
async function generateViewerToken(
  userId: string,
  sessionId: string
): Promise<string> {
  // Create a simple JWT-like token for development
  // In production, this should use Unkey or another token service
  const payload = {
    sub: userId,
    sessionId,
    type: "viewer",
    iat: Date.now(),
    exp: Date.now() + 30 * 60 * 1000, // 30 minutes
  };

  // For now, just base64 encode - replace with proper signing
  return Buffer.from(JSON.stringify(payload)).toString("base64");
}

async function SessionPageContent({
  params,
}: {
  params: Promise<{ sessionId: string }>;
}) {
  const { sessionId } = await params;

  // Validate session ID format
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(sessionId)) {
    notFound();
  }

  const supabase = await createSupabaseUserServerComponentClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return <div>Please log in to view this session.</div>;
  }

  // Fetch the coding session with related data
  const { data: session, error } = await supabase
    .from("coding_sessions")
    .select(
      `
      *,
      repository:repositories(id, name, remote_url, default_branch, worktree_branch, is_worktree),
      device:devices(id, name, device_type)
    `
    )
    .eq("id", sessionId)
    .eq("user_id", user.id)
    .single();

  if (error || !session) {
    notFound();
  }

  // Get the relay URL from environment
  const relayUrl = process.env.NEXT_PUBLIC_RELAY_URL ?? "ws://localhost:8080";

  // Get a viewer token for this session
  // In a real implementation, this would be a short-lived token
  const viewerToken = await generateViewerToken(user.id, sessionId);

  // Determine the branch name based on whether it's a worktree
  const branchName = session.repository?.is_worktree
    ? (session.repository?.worktree_branch ?? "main")
    : (session.repository?.default_branch ?? "main");

  return (
    <div className="flex h-screen flex-col">
      <SessionViewerClient
        branchName={branchName}
        deviceName={session.device?.name ?? "Unknown Device"}
        relayUrl={relayUrl}
        repositoryName={session.repository?.name ?? "Unknown Repository"}
        sessionId={sessionId}
        status={session.status as "active" | "paused" | "ended"}
        viewerId={user.id}
        viewerToken={viewerToken}
      />
    </div>
  );
}

export default async function SessionPage({ params }: SessionPageProps) {
  return (
    <Suspense
      fallback={
        <div className="flex h-screen flex-col">
          <Skeleton className="h-16 w-full" />
          <div className="flex-1 p-4">
            <Skeleton className="h-full w-full" />
          </div>
        </div>
      }
    >
      <SessionPageContent params={params} />
    </Suspense>
  );
}
