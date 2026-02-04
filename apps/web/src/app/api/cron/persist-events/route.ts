import { type NextRequest, NextResponse } from "next/server";
import { persistConversationEvents } from "@/lib/workers/persist-conversation-events";

/**
 * POST /api/cron/persist-events
 *
 * Background job to persist Redis stream events to Supabase.
 * Triggered by Vercel Cron (every minute).
 *
 * @see vercel.json for cron configuration
 */
export async function POST(request: NextRequest) {
  try {
    // Verify cron secret (Vercel Cron adds Authorization header)
    const authHeader = request.headers.get("authorization");
    const expectedAuth = `Bearer ${process.env.CRON_SECRET}`;

    if (authHeader !== expectedAuth) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Validate required environment variables
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const redisUrl = process.env.UPSTASH_REDIS_REST_URL;
    const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN;

    if (!(supabaseUrl && supabaseServiceKey && redisUrl && redisToken)) {
      console.error("[Cron] Missing required environment variables");
      return NextResponse.json(
        { error: "Configuration error" },
        { status: 500 }
      );
    }

    // Run persistence worker
    const result = await persistConversationEvents({
      supabaseUrl,
      supabaseServiceKey,
      redisUrl,
      redisToken,
    });

    return NextResponse.json({
      success: true,
      timestamp: new Date().toISOString(),
      ...result,
    });
  } catch (error) {
    console.error("[Cron] Error persisting events:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

