import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
// const matchAppAdmin = match('/app_admin_preview/(.*)?');
import { User } from "@supabase/supabase-js";
import createMiddleware from "next-intl/middleware";
import { match } from "path-to-regexp";
import urlJoin from "url-join";
import {
  DEFAULT_LOCALE,
  LOCALES,
  LOCALE_GLOB_PATTERN,
  isValidLocale,
} from "./constants";
import { updateSession } from "./supabase-clients/middleware";
import { createSupabaseMiddlewareClient } from "./supabase-clients/user/createSupabaseMiddlewareClient";
import { toSiteURL } from "./utils/helpers";
import { isSupabaseUserAppAdmin } from "./utils/isSupabaseUserAppAdmin";
import { middlewareLogger } from "./utils/logger";
import { authUserMetadataSchema } from "./utils/zod-schemas/authUserMetadata";

/**
 * Using a middleware to protect pages from unauthorized access
 * may seem repetitive however it massively increases the security
 * and performance of your application. This is because the middleware
 * runs first on the server and can bail out early before the
 * server component is even rendered. This means no database queries
 * or other expensive operations are run if the user is not authorized.
 */

/**
 * Public paths are paths that are accessible to everyone.
 * They don't require the user to be logged in.
 */
const publicPaths = [
  `/`,
  `/changelog`,
  `/feedback(/.*)?`,
  `/roadmap`,
  `/auth(/.*)?`,
  `/confirm-delete-user(/.*)?`,
  `/forgot-password(/.*)?`,
  `/login(/.*)?`,
  `/sign-up(/.*)?`,
  `/update-password(/.*)?`,
  `/roadmap`,
  `/version2`,
  `/blog(/.*)?`,
  `/docs(/.*)?`,
  `/terms`,
  `/waitlist(/.*)?`,
  `/500(/.*)?`,
];

/**
 * Dashboard routes are paths that are accessible to logged in users.
 * They require the user to be logged in.
 */
const dashboardRoutes = [
  `/dashboard(/.*)?`,
  `/settings(/.*)?`,
  `/profile(/.*)?`,
  `/workspace(/.*)?`,
  `/project(/.*)?`,
  `/home(/.*)?`,
  `/settings(/.*)?`,
  `/user(/.*)?`,
  `/logout`,
];

/**
 * Onboarding paths are paths that are accessible to users who are not onboarded.
 * They require the user to be logged in.
 * However, if the user is not onboard, the dashboard routes are not accessible.
 */
const onboardingPaths = [`/onboarding(/.*)?`];

/**
 * App admin paths are paths that are accessible to app admins.
 * They require the user to be logged in.
 */
const appAdminPaths = [`/app_admin(/.*)?`];

/**
 * All routes which require login including dashboard, onboarding and app admin.
 */
const protectedPaths = [
  ...dashboardRoutes,
  ...onboardingPaths,
  ...appAdminPaths,
];

const rootPaths = ["/"];

const allPaths = [...publicPaths, ...protectedPaths];

const publicPathsWithLocale = publicPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);
const dashboardRoutesWithLocale = dashboardRoutes.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

const onboardingPathsWithLocale = onboardingPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);
const appAdminPathsWithLocale = appAdminPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);
const protectedPathsWithLocale = [
  ...dashboardRoutesWithLocale,
  ...onboardingPathsWithLocale,
  ...appAdminPathsWithLocale,
];

const rootPathsWithLocale = rootPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

const allSubPathsWithLocale = [
  ...rootPathsWithLocale,
  ...publicPathsWithLocale,
  ...protectedPathsWithLocale,
];

type MiddlewareFunction = (request: NextRequest) => Promise<NextResponse>;

interface MiddlewareConfig {
  matcher: string | string[];
  middleware: MiddlewareFunction;
}

function withMaybeLocale(request: NextRequest, subPath: string) {
  const currentLocale = request.cookies.get("NEXT_LOCALE")?.value;
  if (currentLocale) {
    return urlJoin(currentLocale, subPath);
  }
  return subPath;
}

const middlewares: MiddlewareConfig[] = [
  // if locale doesn't exist on a valid path, redirect to the default locale
  {
    matcher: ["/", ...allPaths],
    middleware: async (request) => {
      middlewareLogger.log(
        "middleware without locale paths",
        request.nextUrl.pathname,
      );
      // redirect to /en if the locale is not /en or /
      const currentLocale = request.cookies.get("NEXT_LOCALE")?.value;
      const searchParams = request.nextUrl.searchParams;
      const pathname = request.nextUrl.pathname;
      if (currentLocale) {
        const parsedLocale = isValidLocale(currentLocale);
        if (parsedLocale) {
          return NextResponse.redirect(
            urlJoin(
              request.nextUrl.origin,
              currentLocale,
              pathname,
              `?${searchParams.toString()}`,
            ),
          );
        }
      }
      const response = NextResponse.redirect(
        urlJoin(
          request.nextUrl.origin,
          DEFAULT_LOCALE,
          pathname,
          `?${searchParams.toString()}`,
        ),
      );
      response.cookies.set("NEXT_LOCALE", DEFAULT_LOCALE);
      return response;
    },
  },

  {
    matcher: allSubPathsWithLocale,
    middleware: async (request) => {
      middlewareLogger.log("all i18n paths", request.nextUrl.pathname);
      const localeFromPath = request.nextUrl.pathname.split("/")[1];

      // Step 2: Create and call the next-intl middleware (example)
      const handleI18nRouting = createMiddleware({
        locales: LOCALES,
        defaultLocale: DEFAULT_LOCALE,
      });
      const response = handleI18nRouting(request);
      middlewareLogger.log("Locale from path:", localeFromPath);
      if (isValidLocale(localeFromPath)) {
        // save cookie if needed
        const currentLocale = request.cookies.get("NEXT_LOCALE")?.value;
        if (currentLocale !== localeFromPath) {
          middlewareLogger.log(
            `Saving locale to cookie: ${localeFromPath}`,
            `Previous locale: ${currentLocale}`,
          );
          response.cookies.set("NEXT_LOCALE", localeFromPath);
        } else {
          middlewareLogger.log(
            `Locale already saved to cookie: ${localeFromPath}. Nothing to do.`,
          );
        }
      } else {
        middlewareLogger.log(
          `Invalid locale: ${localeFromPath}. Deleting cookie.`,
        );
        response.cookies.delete("NEXT_LOCALE");
      }
      return response;
    },
  },
  {
    // protected routes
    matcher: protectedPathsWithLocale,
    middleware: async (req) => {
      middlewareLogger.log(
        "middleware protected paths with locale",
        req.nextUrl.pathname,
      );
      const res = NextResponse.next();
      // since all the middlewares are executed in order, we can update the session here once
      // for all the protected routes
      await updateSession(req);
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (!maybeUser) {
        middlewareLogger.log(
          "User is not logged in. Redirecting to login.",
          req.nextUrl.pathname,
        );
        return NextResponse.redirect(toSiteURL(withMaybeLocale(req, "/login")));
      }
      middlewareLogger.log(
        "User is logged in. Continuing.",
        req.nextUrl.pathname,
      );
      return res;
    },
  },
  {
    matcher: dashboardRoutesWithLocale,
    middleware: async (req) => {
      middlewareLogger.log(
        "middleware dashboard paths with locale",
        req.nextUrl.pathname,
      );
      const res = NextResponse.next();
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (!maybeUser) {
        throw new Error("User is not logged in");
      }
      if (shouldOnboardUser(maybeUser)) {
        middlewareLogger.log(
          "User should onboard. Redirecting to onboarding.",
          req.nextUrl.pathname,
        );
        return NextResponse.redirect(
          toSiteURL(withMaybeLocale(req, "/onboarding")),
        );
      }
      middlewareLogger.log(
        "User should not onboard. Continuing.",
        req.nextUrl.pathname,
      );
      return res;
    },
  },
  {
    matcher: onboardingPathsWithLocale,
    middleware: async (req) => {
      middlewareLogger.log(
        "middleware onboarding paths with locale",
        req.nextUrl.pathname,
      );
      const res = NextResponse.next();
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      // if onboarding is required, continue
      // else redirect to dashboard
      if (!maybeUser) {
        throw new Error("User is not logged in");
      }
      if (!shouldOnboardUser(maybeUser)) {
        middlewareLogger.log(
          "User should not onboard. Redirecting to dashboard.",
          req.nextUrl.pathname,
        );
        return NextResponse.redirect(
          toSiteURL(withMaybeLocale(req, "/dashboard")),
        );
      }
      middlewareLogger.log(
        "User should onboard. Continuing.",
        req.nextUrl.pathname,
      );
      return res;
    },
  },
  {
    // match /app_admin and /app_admin/ and all subpaths
    matcher: appAdminPathsWithLocale,
    middleware: async (req) => {
      middlewareLogger.log(
        "middleware app admin paths with locale",
        req.nextUrl.pathname,
      );
      const res = NextResponse.next();
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (!(maybeUser && isSupabaseUserAppAdmin(maybeUser))) {
        middlewareLogger.log(
          "User is not an app admin. Redirecting to dashboard.",
          req.nextUrl.pathname,
        );
        return NextResponse.redirect(
          toSiteURL(withMaybeLocale(req, "/dashboard")),
        );
      }
      middlewareLogger.log(
        "User is an app admin. Continuing.",
        req.nextUrl.pathname,
      );
      return res;
    },
  },
];

function shouldOnboardUser(user: User) {
  const userMetadata = authUserMetadataSchema.parse(user.user_metadata);
  const {
    onboardingHasAcceptedTerms,
    onboardingHasCompletedProfile,
    onboardingHasCreatedWorkspace,
  } = userMetadata;
  if (
    !onboardingHasAcceptedTerms ||
    !onboardingHasCompletedProfile ||
    !onboardingHasCreatedWorkspace
  ) {
    return true;
  }

  return false;
}

function matchesPath(matcher: string | string[], pathname: string): boolean {
  const matchers = Array.isArray(matcher) ? matcher : [matcher];
  return matchers.some((m) => {
    const matchFn = match(m, { decode: decodeURIComponent });
    return matchFn(pathname) !== false;
  });
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const applicableMiddlewares = middlewares.filter((m) =>
    matchesPath(m.matcher, pathname),
  );

  let response: NextResponse | undefined;

  for (const { middleware } of applicableMiddlewares) {
    const result = await middleware(request);

    if (result.status >= 300) {
      return result;
    }
  }

  return response || NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - api (API routes)
     * Feel free to modify this pattern to include more paths.
     */
    "/((?!_next/static|_next/image|favicon.ico|api|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
