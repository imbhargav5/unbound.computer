import { type NextRequest, NextResponse } from "next/server";
import { SESSION_STATUS, validateSessionForOperation } from "@/lib/sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

/**
 * POST: Pause a running session
 *
 * Transitions session from 'active' to 'paused' state.
 * The actual pause command is sent to the device via Supabase Realtime
 * (devices subscribe to their session changes).
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
      [SESSION_STATUS.ACTIVE]
    );

    if (!validation.valid) {
      return NextResponse.json(
        { error: validation.error, code: validation.code },
        { status: validation.code === "SESSION_NOT_FOUND" ? 404 : 400 }
      );
    }

    // Update session status to paused
    const { data: session, error } = await supabase
      .from("coding_sessions")
      .update({
        status: SESSION_STATUS.PAUSED,
        updated_at: new Date().toISOString(),
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

    return NextResponse.json({
      success: true,
      session,
      message: "Session paused. Command will be sent to device via realtime.",
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
