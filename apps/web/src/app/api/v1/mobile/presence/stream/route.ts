import { createHmac, randomBytes } from "node:crypto";
import { type NextRequest, NextResponse } from "next/server";
import {
  normalizePresenceIdentifier,
  presenceScopeDefault,
} from "@/lib/presence/schema";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
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

export async function GET(req: NextRequest) {
  try {
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

    const presenceBaseUrl = process.env.PRESENCE_DO_BASE_URL?.trim();
    if (!presenceBaseUrl) {
      return NextResponse.json(
        buildPresenceError(
          "unavailable",
          "Presence DO base URL is not configured"
        ),
        { status: 503, headers: corsHeaders }
      );
    }

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

    const requestUrl = new URL(req.url);
    const userId = normalizePresenceIdentifier(
      requestUrl.searchParams.get("user_id") ?? ""
    );

    if (!userId) {
      return NextResponse.json(
        buildPresenceError("invalid_payload", "Missing user_id"),
        { status: 400, headers: corsHeaders }
      );
    }

    const normalizedUserId = normalizePresenceIdentifier(user.id);
    if (userId !== normalizedUserId) {
      return NextResponse.json(buildPresenceError("forbidden", "Forbidden"), {
        status: 403,
        headers: corsHeaders,
      });
    }

    const issuedAtMs = Date.now();
    const presenceToken = createPresenceToken(
      {
        token_id: randomBytes(16).toString("hex"),
        user_id: normalizedUserId,
        device_id: normalizedUserId,
        scope: Array.from(presenceScopeDefault),
        exp_ms: issuedAtMs + TOKEN_TTL_MS,
        issued_at_ms: issuedAtMs,
      },
      signingKey
    );

    const upstreamUrl = new URL(
      "/api/v1/mobile/presence/stream",
      presenceBaseUrl
    );
    upstreamUrl.searchParams.set("user_id", userId);

    const upstreamResponse = await fetch(upstreamUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${presenceToken}`,
      },
    });

    if (!upstreamResponse.ok) {
      const errorBody = await upstreamResponse.text();
      return new NextResponse(
        errorBody ||
          JSON.stringify(
            buildPresenceError("unavailable", "Presence stream unavailable")
          ),
        {
          status: upstreamResponse.status,
          headers: {
            ...corsHeaders,
            "Content-Type":
              upstreamResponse.headers.get("Content-Type") ??
              "application/json",
          },
        }
      );
    }

    return new NextResponse(upstreamResponse.body, {
      status: upstreamResponse.status,
      headers: {
        ...corsHeaders,
        "Content-Type":
          upstreamResponse.headers.get("Content-Type") ?? "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  } catch (error) {
    return NextResponse.json(buildPresenceError("unavailable", String(error)), {
      status: 500,
      headers: corsHeaders,
    });
  }
}
