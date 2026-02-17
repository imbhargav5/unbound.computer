import { type NextRequest, NextResponse } from "next/server";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

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

    return NextResponse.json(
      buildPresenceError(
        "unavailable",
        "Presence stream is not configured yet"
      ),
      { status: 503, headers: corsHeaders }
    );
  } catch (error) {
    return NextResponse.json(buildPresenceError("unavailable", String(error)), {
      status: 500,
      headers: corsHeaders,
    });
  }
}
