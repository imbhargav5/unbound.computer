import { createWebSessionQRData, hashSessionToken } from "@unbound/crypto";
import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  checkWebSessionRateLimit,
  WEB_SESSION_EXPIRY,
  WEB_SESSION_STATUS,
} from "@/lib/web-sessions";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

const initSchema = z.object({
  publicKey: z.string().min(32), // Base64 X25519 public key
  userAgent: z.string().optional(),
});

/**
 * POST: Initialize a new pending web session
 *
 * Creates a pending web session and returns QR code data
 * for the user to scan with their trusted device.
 */
export async function POST(req: NextRequest) {
  try {
    const supabase = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await req.json();
    const parseResult = initSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400 }
      );
    }

    const { publicKey, userAgent } = parseResult.data;

    // Check rate limit
    const rateLimitCheck = await checkWebSessionRateLimit(supabase, user.id);
    if (!rateLimitCheck.valid) {
      return NextResponse.json(
        { error: rateLimitCheck.error, code: rateLimitCheck.code },
        { status: 429 }
      );
    }

    // Generate session token
    const sessionToken = crypto.randomUUID();
    const sessionTokenHash = hashSessionToken(sessionToken);

    // Calculate expiration (5 minutes for pending)
    const expiresAt = new Date(
      Date.now() + WEB_SESSION_EXPIRY.PENDING_MINUTES * 60 * 1000
    );

    // Get client IP
    const forwardedFor = req.headers.get("x-forwarded-for");
    const ipAddress = forwardedFor?.split(",")[0].trim() ?? null;

    // Create pending session
    const { data: session, error } = await supabase
      .from("web_sessions")
      .insert({
        user_id: user.id,
        session_token_hash: sessionTokenHash,
        web_public_key: publicKey,
        user_agent: userAgent ?? req.headers.get("user-agent") ?? null,
        ip_address: ipAddress,
        status: WEB_SESSION_STATUS.PENDING,
        expires_at: expiresAt.toISOString(),
      })
      .select("id, expires_at")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // Generate QR code data
    const qrData = createWebSessionQRData(
      session.id,
      publicKey,
      expiresAt.getTime()
    );

    return NextResponse.json(
      {
        sessionId: session.id,
        sessionToken, // Client stores this to authenticate later
        qrData, // Display as QR code
        expiresAt: session.expires_at,
      },
      { status: 201 }
    );
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
