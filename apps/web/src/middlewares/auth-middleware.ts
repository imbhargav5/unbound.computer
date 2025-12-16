import { NextResponse } from "next/server";
import { userClaimsSchema } from "@/utils/zod-schemas/user-claims-schema";
import { createSupabaseMiddlewareClient } from "../supabase-clients/user/create-supabase-middleware-client";
import { toSiteURL } from "../utils/helpers";
import { middlewareLogger } from "../utils/logger";
import { protectedPaths } from "./paths";
import type { MiddlewareConfig } from "./types";

export const authMiddleware: MiddlewareConfig = {
  matcher: protectedPaths,
  middleware: async (request, maybeUser) => {
    middlewareLogger.log(
      "middleware protected paths",
      request.nextUrl.pathname
    );

    const { supabase, supabaseResponse } =
      createSupabaseMiddlewareClient(request);

    const { data: claimsData, error: claimsError } =
      await supabase.auth.getClaims();

    if (claimsError) {
      middlewareLogger.log(
        "Error getting claims",
        claimsError.message,
        request.nextUrl.pathname
      );
      return [NextResponse.redirect(toSiteURL("/login")), maybeUser];
    }

    if (!claimsData?.claims) {
      middlewareLogger.log(
        "User is not logged in. Redirecting to login.",
        request.nextUrl.pathname
      );
      return [NextResponse.redirect(toSiteURL("/login")), maybeUser];
    }

    const userClaims = userClaimsSchema.parse(claimsData.claims);

    middlewareLogger.log(
      "User is logged in. Continuing.",
      request.nextUrl.pathname
    );

    return [supabaseResponse, userClaims];
  },
};
