"use client";

import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/supabase-clients/anon/create-supabase-anon-browser-client";

/**
 * CLI Authentication Page
 *
 * This page initiates OAuth authentication for CLI users.
 *
 * SECURITY:
 * - Uses Supabase anon key (public key)
 * - Preserves login_id through OAuth flow
 * - PKCE flow prevents code interception
 * - Redirect URL validated by Supabase
 *
 * URL: /cli-auth?login_id=<uuid>
 *
 * FLOW:
 * 1. CLI opens browser to this page with unique login_id
 * 2. User clicks "Sign in with GitHub/Google/etc"
 * 3. OAuth provider authenticates user
 * 4. Provider redirects to /cli-auth/callback with code
 * 5. Callback exchanges code for session and stores in cli_logins
 * 6. CLI polls and retrieves session
 */
export default function CLIAuthPage() {
  const searchParams = useSearchParams();
  const loginId = searchParams.get("login_id");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // Validate login_id parameter
    if (!loginId) {
      setError(
        "Missing login_id parameter. Please try running 'unbound login' again."
      );
    }
  }, [loginId]);

  const handleOAuthLogin = async (provider: "github" | "google" | "gitlab") => {
    if (!loginId) {
      setError("Missing login_id parameter");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const supabase = createClient();

      // Construct callback URL with login_id
      const redirectTo = `${window.location.origin}/cli-auth/callback?login_id=${encodeURIComponent(loginId)}`;

      // Initiate OAuth flow with PKCE
      // SECURITY: PKCE prevents authorization code interception
      const { error: signInError } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo,
          skipBrowserRedirect: false,
        },
      });

      if (signInError) {
        setError(`Authentication failed: ${signInError.message}`);
        setLoading(false);
      }
      // Browser will redirect to OAuth provider
    } catch (err) {
      setError(
        `Unexpected error: ${err instanceof Error ? err.message : String(err)}`
      );
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
      <div className="w-full max-w-md space-y-8 rounded-lg bg-white p-8 shadow-lg dark:bg-gray-800">
        {/* Header */}
        <div className="text-center">
          <h1 className="font-bold text-3xl text-gray-900 dark:text-white">
            Unbound CLI
          </h1>
          <p className="mt-2 text-gray-600 text-sm dark:text-gray-400">
            Sign in to authenticate the CLI
          </p>
        </div>

        {/* Error Display */}
        {error && (
          <div className="rounded-md border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-900/20">
            <p className="text-red-800 text-sm dark:text-red-400">{error}</p>
          </div>
        )}

        {/* Login Buttons */}
        {loginId && !error && (
          <div className="space-y-4">
            <button
              className="flex w-full items-center justify-center gap-3 rounded-md border border-gray-300 bg-white px-4 py-3 font-medium text-gray-700 text-sm shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
              disabled={loading}
              onClick={() => handleOAuthLogin("github")}
              type="button"
            >
              <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                <path
                  clipRule="evenodd"
                  d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z"
                  fillRule="evenodd"
                />
              </svg>
              {loading ? "Signing in..." : "Continue with GitHub"}
            </button>

            <button
              className="flex w-full items-center justify-center gap-3 rounded-md border border-gray-300 bg-white px-4 py-3 font-medium text-gray-700 text-sm shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
              disabled={loading}
              onClick={() => handleOAuthLogin("google")}
              type="button"
            >
              <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10.2 8.6v3.3h4.6c-.2 1-1.3 3-4.6 3-2.8 0-5-2.3-5-5.1s2.2-5.1 5-5.1c1.6 0 2.6.7 3.2 1.3l2.6-2.5C14.4 2 12.5 1 10.2 1 5.6 1 2 4.6 2 9.2s3.6 8.2 8.2 8.2c4.7 0 7.9-3.3 7.9-8 0-.5-.1-1-.1-1.4H10.2z" />
              </svg>
              {loading ? "Signing in..." : "Continue with Google"}
            </button>

            <button
              className="flex w-full items-center justify-center gap-3 rounded-md border border-gray-300 bg-white px-4 py-3 font-medium text-gray-700 text-sm shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
              disabled={loading}
              onClick={() => handleOAuthLogin("gitlab")}
              type="button"
            >
              <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10 0L13.09 6.26L20 7.27L15 12.14L16.18 19.02L10 15.77L3.82 19.02L5 12.14L0 7.27L6.91 6.26L10 0Z" />
              </svg>
              {loading ? "Signing in..." : "Continue with GitLab"}
            </button>
          </div>
        )}

        {/* Info Section */}
        <div className="mt-6 border-gray-200 border-t pt-6 dark:border-gray-700">
          <p className="text-center text-gray-500 text-xs dark:text-gray-400">
            After signing in, you can close this window and return to your
            terminal.
          </p>
        </div>
      </div>
    </div>
  );
}
