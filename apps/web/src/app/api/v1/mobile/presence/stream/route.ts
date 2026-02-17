import { type NextRequest, NextResponse } from "next/server";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";
import { normalizePresenceIdentifier } from "@/lib/presence/schema";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function buildPresenceError(error: string, details: string) {
  return { error, details };
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
        buildPresenceError("unavailable", "Presence DO base URL is not configured"),
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

    const upstreamUrl = new URL("/api/v1/mobile/presence/stream", presenceBaseUrl);
    upstreamUrl.searchParams.set("user_id", userId);

    const upstreamResponse = await fetch(upstreamUrl, {
      method: "GET",
      headers: {
        Authorization: req.headers.get("Authorization") ?? "",
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
              upstreamResponse.headers.get("Content-Type") ?? "application/json",
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
