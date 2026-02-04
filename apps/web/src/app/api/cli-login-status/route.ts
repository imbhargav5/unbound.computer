import { type NextRequest, NextResponse } from "next/server";
import { createSupabaseAdminRouteHandlerClient } from "@/supabase-clients/admin/create-supabase-admin-route-handler-client";

/**
 * GET /api/cli-login-status?login_id=<uuid>
 *
 * Polling endpoint for CLI to check if browser auth completed
 *
 * SECURITY:
 * - Uses service role key (never exposed to CLI)
 * - login_id is a random UUID (unpredictable)
 * - Login attempts expire after 10 minutes
 * - RLS policies prevent unauthorized access
 *
 * FLOW:
 * 1. CLI generates login_id and opens browser
 * 2. CLI polls this endpoint with login_id
 * 3. Browser completes auth and stores session in cli_logins table
 * 4. This endpoint returns session when available
 * 5. CLI stores tokens securely and deletes the login entry
 */
export async function GET(req: NextRequest) {
  try {
    const searchParams = req.nextUrl.searchParams;
    const loginIdParam = searchParams.get("login_id");

    // Validate login_id parameter
    if (!loginIdParam) {
      return NextResponse.json(
        { error: "login_id parameter is required" },
        { status: 400 }
      );
    }

    // Store validated login_id for type safety
    const loginId = loginIdParam;

    // Use admin client with service role key to query cli_logins
    // SECURITY: Service role key only used server-side, never sent to CLI
    const supabase = await createSupabaseAdminRouteHandlerClient();

    // Query for the login entry
    const { data: login, error: queryError } = await supabase
      .from("cli_logins")
      .select("user_id, access_token, refresh_token, expires_at, created_at")
      .eq("login_id", loginId)
      .maybeSingle();

    if (queryError) {
      console.error("Error querying cli_logins:", queryError);
      return NextResponse.json(
        { error: "Database query failed" },
        { status: 500 }
      );
    }

    // If no login found, return pending status
    if (!login) {
      return NextResponse.json({ status: "pending" });
    }

    // Check if login attempt expired (older than 10 minutes)
    const createdAt = new Date(login.created_at);
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);

    if (createdAt < tenMinutesAgo) {
      // Delete expired login attempt
      await supabase.from("cli_logins").delete().eq("login_id", loginId);

      return NextResponse.json(
        { status: "expired", error: "Login attempt expired" },
        { status: 410 }
      );
    }

    // Login successful - return session tokens
    // SECURITY: Tokens transmitted over HTTPS only
    const response = NextResponse.json({
      status: "success",
      session: {
        access_token: login.access_token,
        refresh_token: login.refresh_token,
        expires_at: login.expires_at,
        user_id: login.user_id,
      },
    });

    // Delete the login entry after successful retrieval
    // This ensures one-time use and prevents token leakage
    await supabase.from("cli_logins").delete().eq("login_id", loginId);

    return response;
  } catch (error) {
    console.error("CLI login status error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
