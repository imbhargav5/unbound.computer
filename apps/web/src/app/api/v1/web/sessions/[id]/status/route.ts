import { type NextRequest, NextResponse } from "next/server";
import { WEB_SESSION_STATUS } from "@/lib/web-sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

/**
 * GET: Get web session status
 *
 * Used by the web client to poll for authorization status.
 * Returns session status and, if authorized, the encrypted session key.
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
        created_at,
        expires_at,
        authorized_at,
        encrypted_session_key,
        responder_public_key,
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

    // Check if session has expired
    const expiresAt = new Date(session.expires_at);
    if (
      expiresAt < new Date() &&
      session.status !== WEB_SESSION_STATUS.EXPIRED &&
      session.status !== WEB_SESSION_STATUS.REVOKED
    ) {
      // Mark as expired
      await supabase
        .from("web_sessions")
        .update({ status: WEB_SESSION_STATUS.EXPIRED })
        .eq("id", sessionId);

      session.status = WEB_SESSION_STATUS.EXPIRED;
    }

    return NextResponse.json({
      id: session.id,
      status: session.status,
      createdAt: session.created_at,
      expiresAt: session.expires_at,
      authorizedAt: session.authorized_at,
      // Only include sensitive data if session is active
      encryptedSessionKey:
        session.status === WEB_SESSION_STATUS.ACTIVE
          ? session.encrypted_session_key
          : null,
      responderPublicKey:
        session.status === WEB_SESSION_STATUS.ACTIVE
          ? session.responder_public_key
          : null,
      authorizingDevice: session.authorizing_device ?? null,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
