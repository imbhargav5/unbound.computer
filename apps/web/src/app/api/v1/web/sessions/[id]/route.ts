import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { WEB_SESSION_STATUS } from "@/lib/web-sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

const revokeSchema = z.object({
  reason: z.string().optional(),
});

/**
 * GET: Get web session details
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
      .from("web_sessions")
      .select(
        `
        id,
        status,
        user_agent,
        ip_address,
        created_at,
        authorized_at,
        expires_at,
        last_activity_at,
        revoked_at,
        revoked_reason,
        authorizing_device:devices!web_sessions_authorizing_device_id_fkey(
          id,
          name,
          device_type
        )
      `
      )
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .single();

    if (error) {
      return NextResponse.json({ error: "Session not found" }, { status: 404 });
    }

    return NextResponse.json({
      id: session.id,
      status: session.status,
      userAgent: session.user_agent,
      ipAddress: session.ip_address,
      createdAt: session.created_at,
      authorizedAt: session.authorized_at,
      expiresAt: session.expires_at,
      lastActivityAt: session.last_activity_at,
      revokedAt: session.revoked_at,
      revokedReason: session.revoked_reason,
      authorizingDevice: session.authorizing_device ?? null,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}

/**
 * DELETE: Revoke a web session
 */
export async function DELETE(req: NextRequest, { params }: RouteParams) {
  try {
    const { id: sessionId } = await params;
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Parse optional reason from body
    let reason: string | undefined;
    try {
      const body = await req.json();
      const parseResult = revokeSchema.safeParse(body);
      if (parseResult.success) {
        reason = parseResult.data.reason;
      }
    } catch {
      // No body or invalid JSON - that's fine
    }

    const { data: session, error } = await supabase
      .from("web_sessions")
      .update({
        status: WEB_SESSION_STATUS.REVOKED,
        revoked_at: new Date().toISOString(),
        revoked_reason: reason ?? null,
      })
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .in("status", [WEB_SESSION_STATUS.PENDING, WEB_SESSION_STATUS.ACTIVE])
      .select("id, status, revoked_at")
      .single();

    if (error) {
      return NextResponse.json(
        { error: "Session not found or already revoked" },
        { status: 404 }
      );
    }

    return NextResponse.json({
      success: true,
      session: {
        id: session.id,
        status: session.status,
        revokedAt: session.revoked_at,
      },
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}

/**
 * PATCH: Update last activity (touch session)
 */
export async function PATCH(req: NextRequest, { params }: RouteParams) {
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
      .from("web_sessions")
      .update({
        last_activity_at: new Date().toISOString(),
      })
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .eq("status", WEB_SESSION_STATUS.ACTIVE)
      .gt("expires_at", new Date().toISOString())
      .select("id, last_activity_at")
      .single();

    if (error) {
      return NextResponse.json(
        { error: "Session not found or not active" },
        { status: 404 }
      );
    }

    return NextResponse.json({
      success: true,
      lastActivityAt: session.last_activity_at,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
