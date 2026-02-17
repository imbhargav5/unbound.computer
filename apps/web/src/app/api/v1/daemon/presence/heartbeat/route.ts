import { type NextRequest, NextResponse } from "next/server";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function buildPresenceError(error: string, details: string) {
  return { error, details };
}

function parseBearerToken(header: string | null) {
  if (!header) return "";
  const [type, value] = header.split(" ");
  if (!type || type.toLowerCase() !== "bearer") return "";
  return value ?? "";
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function POST(req: NextRequest) {
  try {
    const presenceBaseUrl = process.env.PRESENCE_DO_BASE_URL?.trim();
    const ingestToken = process.env.PRESENCE_DO_INGEST_TOKEN?.trim();
    const daemonToken = process.env.PRESENCE_DO_DAEMON_TOKEN?.trim();

    if (!presenceBaseUrl || !ingestToken || !daemonToken) {
      return NextResponse.json(
        buildPresenceError(
          "unavailable",
          "Presence DO environment is not configured"
        ),
        { status: 503, headers: corsHeaders }
      );
    }

    const authHeader = parseBearerToken(req.headers.get("Authorization"));
    if (!authHeader || authHeader !== daemonToken) {
      return NextResponse.json(buildPresenceError("unauthorized", "Unauthorized"), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const payload = await req.text();
    if (!payload) {
      return NextResponse.json(
        buildPresenceError("invalid_payload", "Missing request body"),
        { status: 400, headers: corsHeaders }
      );
    }

    const upstreamUrl = new URL(
      "/api/v1/daemon/presence/heartbeat",
      presenceBaseUrl
    );

    const upstreamResponse = await fetch(upstreamUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${ingestToken}`,
      },
      body: payload,
    });

    const responseBody = await upstreamResponse.text();
    if (!responseBody) {
      return new NextResponse(null, {
        status: upstreamResponse.status,
        headers: corsHeaders,
      });
    }

    return new NextResponse(responseBody, {
      status: upstreamResponse.status,
      headers: {
        ...corsHeaders,
        "Content-Type":
          upstreamResponse.headers.get("Content-Type") ?? "application/json",
      },
    });
  } catch (error) {
    return NextResponse.json(buildPresenceError("unavailable", String(error)), {
      status: 500,
      headers: corsHeaders,
    });
  }
}
