import { NextResponse } from "next/server";
import { toSiteURL } from "../utils/helpers";
import { middlewareLogger } from "../utils/logger";
import { dashboardRoutesWithLocale, onboardingPathsWithLocale } from "./paths";
import { MiddlewareConfig } from "./types";
import { shouldOnboardUser, withMaybeLocale } from "./utils";

export const dashboardOnboardingMiddleware: MiddlewareConfig = {
  matcher: dashboardRoutesWithLocale,
  middleware: async (req, maybeUser) => {
    middlewareLogger.log(
      "middleware dashboard paths with locale",
      req.nextUrl.pathname,
    );
    const res = NextResponse.next();

    if (!maybeUser) {
      throw new Error("User is not logged in");
    }

    if (shouldOnboardUser(maybeUser)) {
      middlewareLogger.log(
        "User should onboard. Redirecting to onboarding.",
        req.nextUrl.pathname,
      );
      return [
        NextResponse.redirect(toSiteURL(withMaybeLocale(req, "/onboarding"))),
        maybeUser,
      ];
    }

    return [res, maybeUser];
  },
};

export const onboardingRedirectMiddleware: MiddlewareConfig = {
  matcher: onboardingPathsWithLocale,
  middleware: async (req, maybeUser) => {
    middlewareLogger.log(
      "middleware onboarding paths with locale",
      req.nextUrl.pathname,
    );
    const res = NextResponse.next();

    if (!maybeUser) {
      throw new Error("User is not logged in");
    }

    if (!shouldOnboardUser(maybeUser)) {
      middlewareLogger.log(
        "User should not onboard. Redirecting to dashboard.",
        req.nextUrl.pathname,
      );
      return [
        NextResponse.redirect(toSiteURL(withMaybeLocale(req, "/dashboard"))),
        maybeUser,
      ];
    }

    return [res, maybeUser];
  },
};
