import { type NextRequest, NextResponse } from "next/server";
import { isSessionExpired, isSessionIdle } from "@/lib/sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

/**
 * GET: Get session details by ID
 *
 * Returns full session information including:
 * - Session metadata
 * - Repository details
 * - Device details
 * - Computed fields (isIdle, isExpired)
 */
export async function GET(req: NextRequest, { params }: RouteParams) {
  try {
    const { id: sessionId } = await params;
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { data: session, error } = await supabase
      .from("agent_coding_sessions")
      .select(
        `
        *,
        repository:repositories(
          id,
          name,
          remote_url,
          local_path,
          default_branch,
          is_worktree,
          worktree_branch,
          parent:repositories!parent_repository_id(id, name)
        ),
        device:devices(id, name, device_type, hostname, is_active, last_seen_at)
      `
      )
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .single();

    if (error) {
      if (error.code === "PGRST116") {
        return NextResponse.json(
          { error: "Session not found", code: "SESSION_NOT_FOUND" },
          { status: 404 }
        );
      }
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Add computed fields
    const enrichedSession = {
      ...session,
      isIdle: isSessionIdle(session),
      isExpired: isSessionExpired(session),
      durationMs: session.session_ended_at
        ? new Date(session.session_ended_at).getTime() -
          new Date(session.session_started_at).getTime()
        : Date.now() - new Date(session.session_started_at).getTime(),
    };

    return NextResponse.json(enrichedSession);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
