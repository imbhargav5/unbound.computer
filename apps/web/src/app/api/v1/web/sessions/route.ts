import { type NextRequest, NextResponse } from "next/server";
import { WEB_SESSION_STATUS } from "@/lib/web-sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

/**
 * GET: List user's web sessions
 *
 * Query parameters:
 * - status: Filter by status (pending, active, expired, revoked)
 * - limit: Number of results (default 20, max 100)
 */
export async function GET(req: NextRequest) {
  try {
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { searchParams } = new URL(req.url);
    const statusParam = searchParams.get("status");

    // Validate status is a valid enum value
    const validStatuses = Object.values(WEB_SESSION_STATUS);
    const status =
      statusParam &&
      validStatuses.includes(statusParam as (typeof validStatuses)[number])
        ? (statusParam as (typeof validStatuses)[number])
        : null;

    const limit = Math.min(
      Number.parseInt(searchParams.get("limit") ?? "20", 10),
      100
    );

    let query = supabase
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
        authorizing_device:devices!web_sessions_authorizing_device_id_fkey(
          id,
          name,
          device_type
        )
      `
      )
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (status) {
      query = query.eq("status", status);
    }

    const { data, error } = await query;

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Transform to camelCase
    const sessions = data.map((session) => ({
      id: session.id,
      status: session.status,
      userAgent: session.user_agent,
      ipAddress: session.ip_address,
      createdAt: session.created_at,
      authorizedAt: session.authorized_at,
      expiresAt: session.expires_at,
      lastActivityAt: session.last_activity_at,
      authorizingDevice: session.authorizing_device ?? null,
    }));

    return NextResponse.json({ sessions });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
