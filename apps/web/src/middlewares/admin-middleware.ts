import { NextResponse } from "next/server";
import { toSiteURL } from "../utils/helpers";
import { isSupabaseUserClaimAppAdmin } from "../utils/is-supabase-user-app-admin";
import { middlewareLogger } from "../utils/logger";
import { appAdminPathsWithLocale } from "./paths";
import type { MiddlewareConfig } from "./types";
import { withMaybeLocale } from "./utils";

export const adminMiddleware: MiddlewareConfig = {
  matcher: appAdminPathsWithLocale,
  middleware: async (req, maybeUser) => {
    middlewareLogger.log(
      "middleware app admin paths with locale",
      req.nextUrl.pathname
    );
    const res = NextResponse.next();
    // here we are only checking the claims
    // deeper check will be done in the layout
    if (!(maybeUser && isSupabaseUserClaimAppAdmin(maybeUser))) {
      middlewareLogger.log(
        "User is not an app admin. Redirecting to dashboard.",
        req.nextUrl.pathname
      );
      return [
        NextResponse.redirect(toSiteURL(withMaybeLocale(req, "/dashboard")), {
          // 302 stands for temporary redirect
          status: 302,
        }),
        maybeUser,
      ];
    }

    return [res, maybeUser];
  },
};
