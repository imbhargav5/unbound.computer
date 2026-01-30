import { NextResponse } from "next/server";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

/**
 * GET /cli-auth/callback
 *
 * OAuth callback handler for CLI authentication flow
 *
 * SECURITY DESIGN:
 * - Uses Supabase anon key (not service role)
 * - RLS policies enforce user can only insert their own sessions
 * - login_id prevents token interception (CLI generates unique UUID)
 * - One-time use: tokens deleted after CLI retrieves them
 *
 * FLOW:
 * 1. User completes OAuth in browser
 * 2. OAuth provider redirects here with code + login_id
 * 3. Exchange code for session using exchangeCodeForSession()
 * 4. Store session in cli_logins table (RLS enforced)
 * 5. CLI polls /api/cli-login-status and retrieves session
 * 6. Show success page to user
 */
export async function GET(request: Request) {
  try {
    const requestUrl = new URL(request.url);
    const code = requestUrl.searchParams.get("code");
    const loginId = requestUrl.searchParams.get("login_id");
    const error = requestUrl.searchParams.get("error");
    const errorDescription = requestUrl.searchParams.get("error_description");

    // Handle OAuth errors
    if (error) {
      const errorUrl = new URL("/cli-auth/error", requestUrl.origin);
      errorUrl.searchParams.set("error", error);
      if (errorDescription) {
        errorUrl.searchParams.set("description", errorDescription);
      }
      return NextResponse.redirect(errorUrl);
    }

    // Validate required parameters
    if (!(code && loginId)) {
      const errorUrl = new URL("/cli-auth/error", requestUrl.origin);
      errorUrl.searchParams.set("error", "missing_parameters");
      errorUrl.searchParams.set(
        "description",
        "Missing required parameters: code or login_id"
      );
      return NextResponse.redirect(errorUrl);
    }

    // Create Supabase client with user context (uses anon key)
    const supabase = await createSupabaseUserRouteHandlerClient();

    // Exchange OAuth code for session
    // SECURITY: This uses PKCE flow - code can only be exchanged once
    const { data: sessionData, error: sessionError } =
      await supabase.auth.exchangeCodeForSession(code);

    if (sessionError || !sessionData.session) {
      console.error("Failed to exchange code for session:", sessionError);
      const errorUrl = new URL("/cli-auth/error", requestUrl.origin);
      errorUrl.searchParams.set("error", "session_exchange_failed");
      errorUrl.searchParams.set(
        "description",
        sessionError?.message || "Failed to create session"
      );
      return NextResponse.redirect(errorUrl);
    }

    const { session, user } = sessionData;

    // Store session in cli_logins table for CLI to retrieve
    // SECURITY: RLS policy ensures user can only insert their own sessions
    const { error: insertError } = await supabase.from("cli_logins").insert({
      login_id: loginId,
      user_id: user.id,
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_at: new Date(
        Date.now() + session.expires_in * 1000
      ).toISOString(),
    });

    if (insertError) {
      console.error("Failed to store CLI login:", insertError);
      const errorUrl = new URL("/cli-auth/error", requestUrl.origin);
      errorUrl.searchParams.set("error", "storage_failed");
      errorUrl.searchParams.set(
        "description",
        "Failed to store authentication tokens"
      );
      return NextResponse.redirect(errorUrl);
    }

    // Redirect to success page
    const successUrl = new URL("/cli-auth/success", requestUrl.origin);
    return NextResponse.redirect(successUrl);
  } catch (error) {
    console.error("CLI auth callback error:", error);
    const errorUrl = new URL(request.url);
    errorUrl.pathname = "/cli-auth/error";
    errorUrl.searchParams.set("error", "internal_error");
    errorUrl.searchParams.set(
      "description",
      "An unexpected error occurred during authentication"
    );
    return NextResponse.redirect(errorUrl);
  }
}
