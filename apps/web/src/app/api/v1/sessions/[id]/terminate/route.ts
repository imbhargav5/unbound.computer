import { type NextRequest, NextResponse } from "next/server";
import { SESSION_STATUS, validateSessionForOperation } from "@/lib/sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

/**
 * POST: Terminate a session
 *
 * Transitions session from 'active' or 'paused' to 'ended' state.
 * The actual terminate command is sent to the device via Supabase Realtime
 * (devices subscribe to their session changes).
 *
 * This ends the session without creating a PR. For PR creation, use /complete.
 */
export async function POST(req: NextRequest, { params }: RouteParams) {
  try {
    const { id: sessionId } = await params;
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Validate session exists, belongs to user, and is in valid state
    const validation = await validateSessionForOperation(
      supabase,
      user.id,
      sessionId,
      [SESSION_STATUS.ACTIVE, SESSION_STATUS.PAUSED]
    );

    if (!validation.valid) {
      return NextResponse.json(
        { error: validation.error, code: validation.code },
        { status: validation.code === "SESSION_NOT_FOUND" ? 404 : 400 }
      );
    }

    const now = new Date().toISOString();

    // Update session status to ended
    const { data: session, error } = await supabase
      .from("agent_coding_sessions")
      .update({
        status: SESSION_STATUS.ENDED,
        session_ended_at: now,
        updated_at: now,
      })
      .eq("id", sessionId)
      .select(
        `
        *,
        repository:repositories(id, name),
        device:devices(id, name, device_type)
      `
      )
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Calculate session duration
    const durationMs =
      new Date(session.session_ended_at!).getTime() -
      new Date(session.session_started_at).getTime();

    return NextResponse.json({
      success: true,
      session,
      durationMs,
      message:
        "Session terminated. Command will be sent to device via realtime.",
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
