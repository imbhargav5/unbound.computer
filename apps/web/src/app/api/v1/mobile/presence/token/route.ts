import { createHmac, randomBytes } from "node:crypto";
import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  normalizePresenceIdentifier,
  presenceScopeDefault,
} from "@/lib/presence/schema";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

const requestSchema = z.object({
  deviceId: z.string().uuid(),
  scope: z.array(z.string().min(1)).optional(),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const TOKEN_TTL_MS = 15 * 60 * 1000;

function buildPresenceError(error: string, details: string) {
  return { error, details };
}

function base64UrlEncode(input: string | Buffer): string {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function createPresenceToken(
  payload: Record<string, unknown>,
  signingKey: string
): string {
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = base64UrlEncode(
    createHmac("sha256", signingKey).update(encodedPayload).digest()
  );
  return `${encodedPayload}.${signature}`;
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function POST(req: NextRequest) {
  try {
    const signingKey = process.env.PRESENCE_DO_TOKEN_SIGNING_KEY?.trim();
    if (!signingKey) {
      return NextResponse.json(
        buildPresenceError(
          "unavailable",
          "Presence DO token signing key is not configured"
        ),
        { status: 503, headers: corsHeaders }
      );
    }

    const supabaseClient = createSupabaseMobileClient(req);
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      return NextResponse.json(
        buildPresenceError("unauthorized", "Unauthorized"),
        {
          status: 401,
          headers: corsHeaders,
        }
      );
    }

    const body = await req.json();
    const parseResult = requestSchema.safeParse(body);
    if (!parseResult.success) {
      return NextResponse.json(
        buildPresenceError("invalid_payload", "Invalid request body"),
        { status: 400, headers: corsHeaders }
      );
    }

    const requesterDeviceId = normalizePresenceIdentifier(
      parseResult.data.deviceId
    );

    const { data: requesterDevice, error: requesterDeviceError } =
      await supabaseClient
        .from("devices")
        .select("id, user_id")
        .eq("id", requesterDeviceId)
        .single();

    if (requesterDeviceError || !requesterDevice) {
      return NextResponse.json(
        buildPresenceError("invalid_payload", "Device not found"),
        {
          status: 404,
          headers: corsHeaders,
        }
      );
    }

    if (requesterDevice.user_id !== user.id) {
      return NextResponse.json(buildPresenceError("forbidden", "Forbidden"), {
        status: 403,
        headers: corsHeaders,
      });
    }

    const scope = parseResult.data.scope?.length
      ? parseResult.data.scope
      : Array.from(presenceScopeDefault);

    const issuedAtMs = Date.now();
    const expiresAtMs = issuedAtMs + TOKEN_TTL_MS;
    const tokenPayload = {
      token_id: randomBytes(16).toString("hex"),
      user_id: normalizePresenceIdentifier(user.id),
      device_id: requesterDeviceId,
      scope,
      exp_ms: expiresAtMs,
      issued_at_ms: issuedAtMs,
    };

    const token = createPresenceToken(tokenPayload, signingKey);

    return NextResponse.json(
      {
        token,
        expires_at_ms: expiresAtMs,
        user_id: tokenPayload.user_id,
        device_id: requesterDeviceId,
        scope,
      },
      { headers: corsHeaders }
    );
  } catch (error) {
    return NextResponse.json(buildPresenceError("unavailable", String(error)), {
      status: 500,
      headers: corsHeaders,
    });
  }
}
