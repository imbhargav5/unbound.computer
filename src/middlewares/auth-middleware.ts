import { NextResponse } from "next/server";
import { createSupabaseMiddlewareClient } from "../supabase-clients/user/createSupabaseMiddlewareClient";
import { toSiteURL } from "../utils/helpers";
import { middlewareLogger } from "../utils/logger";
import { protectedPathsWithLocale } from "./paths";
import { MiddlewareConfig } from "./types";
import { withMaybeLocale } from "./utils";

export const authMiddleware: MiddlewareConfig = {
  matcher: protectedPathsWithLocale,
  middleware: async (request, maybeUser) => {
    middlewareLogger.log(
      "middleware protected paths with locale",
      request.nextUrl.pathname,
    );

    const { supabase, supabaseResponse } =
      createSupabaseMiddlewareClient(request);
    const { data: userData, error: userError } = await supabase.auth.getUser();

    if (userError) {
      middlewareLogger.log(
        "Error getting user",
        userError.message,
        request.nextUrl.pathname,
      );
      return [
        NextResponse.redirect(toSiteURL(withMaybeLocale(request, "/login"))),
        maybeUser,
      ];
    }

    if (!userData) {
      middlewareLogger.log(
        "User is not logged in. Redirecting to login.",
        request.nextUrl.pathname,
      );
      return [
        NextResponse.redirect(toSiteURL(withMaybeLocale(request, "/login"))),
        maybeUser,
      ];
    }

    middlewareLogger.log(
      "User is logged in. Continuing.",
      request.nextUrl.pathname,
    );
    return [supabaseResponse, userData.user];
  },
};
