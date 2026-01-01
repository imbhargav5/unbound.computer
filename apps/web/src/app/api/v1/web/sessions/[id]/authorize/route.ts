import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  validateDeviceForWebAuth,
  validateWebSessionForAuth,
  WEB_SESSION_EXPIRY,
  WEB_SESSION_STATUS,
} from "@/lib/web-sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

interface RouteParams {
  params: Promise<{ id: string }>;
}

const authorizeSchema = z.object({
  deviceId: z.string().uuid(),
  encryptedSessionKey: z.string().min(32), // Base64 encrypted key
  responderPublicKey: z.string().min(32), // Base64 X25519 public key
});

/**
 * POST: Authorize a pending web session
 *
 * Called by a trusted device (CLI or mobile app) after scanning
 * the QR code. Provides the encrypted session key to unlock
 * the web session.
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

    const body = await req.json();
    const parseResult = authorizeSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400 }
      );
    }

    const { deviceId, encryptedSessionKey, responderPublicKey } =
      parseResult.data;

    // Validate device ownership
    const deviceCheck = await validateDeviceForWebAuth(
      supabase,
      user.id,
      deviceId
    );
    if (!deviceCheck.valid) {
      return NextResponse.json(
        { error: deviceCheck.error, code: deviceCheck.code },
        { status: 403 }
      );
    }

    // Validate session is pending and not expired
    const sessionCheck = await validateWebSessionForAuth(
      supabase,
      user.id,
      sessionId
    );
    if (!sessionCheck.valid) {
      return NextResponse.json(
        { error: sessionCheck.error, code: sessionCheck.code },
        { status: 400 }
      );
    }

    // Calculate new expiration (24 hours from authorization)
    const newExpiresAt = new Date(
      Date.now() + WEB_SESSION_EXPIRY.ACTIVE_HOURS * 60 * 60 * 1000
    );

    // Authorize the session
    const { data: session, error } = await supabase
      .from("web_sessions")
      .update({
        status: WEB_SESSION_STATUS.ACTIVE,
        authorizing_device_id: deviceId,
        encrypted_session_key: encryptedSessionKey,
        responder_public_key: responderPublicKey,
        authorized_at: new Date().toISOString(),
        expires_at: newExpiresAt.toISOString(),
        last_activity_at: new Date().toISOString(),
      })
      .eq("id", sessionId)
      .eq("user_id", user.id)
      .select(
        `
        id,
        status,
        authorized_at,
        expires_at,
        authorizing_device:devices!web_sessions_authorizing_device_id_fkey(
          id,
          name,
          device_type
        )
      `
      )
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      session: {
        id: session.id,
        status: session.status,
        authorizedAt: session.authorized_at,
        expiresAt: session.expires_at,
        authorizingDevice: session.authorizing_device,
      },
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
