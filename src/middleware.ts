import {
  type User
} from '@supabase/auth-helpers-nextjs';
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
// const matchAppAdmin = match('/app_admin_preview/(.*)?');
import createMiddleware from 'next-intl/middleware';
import { match } from 'path-to-regexp';
import urlJoin from 'url-join';
import { DEFAULT_LOCALE, LOCALES, LOCALE_GLOB_PATTERN, isValidLocale } from './constants';
import { updateSession } from './supabase-clients/middleware';
import { createSupabaseMiddlewareClient } from './supabase-clients/user/createSupabaseMiddlewareClient';
import { toSiteURL } from './utils/helpers';
import { authUserMetadataSchema } from './utils/zod-schemas/authUserMetadata';


const onboardingPaths = [`/onboarding/(.*)?`];
const appAdminPaths = [`/app_admin/(.*)?`];
// Using a middleware to protect pages from unauthorized access
// may seem repetitive however it massively increases the security
// and performance of your application. This is because the middleware
// runs first on the server and can bail out early before the
// server component is even rendered. This means no database queries
// or other expensive operations are run if the user is not authorized.

const unprotectedPagePrefixes = [
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
  `/roadmap/`,
  `/version2`,
  `/blog(/.*)?`,
  `/docs(/.*)?`,
  `/terms`,
  `/waitlist(/.*)?`,
];

const protectedPagePrefixes = [
  `/app_admin/(.*)?`,
  `/dashboard/(.*)?`,
  `/settings/(.*)?`,
  `/profile/(.*)?`,
  `/workspace/(.*)?`,
  `/project/(.*)?`,
  `/onboarding/(.*)?`,
  `/home/(.*)?`,
  `/settings/(.*)?`,
  `/user/(.*)?`,
];

const rootPaths = ['/']

const allSubPathsWithoutLocale = [...unprotectedPagePrefixes, ...protectedPagePrefixes, ...onboardingPaths, ...appAdminPaths];


const unprotectedPagesWithLocale = unprotectedPagePrefixes.map(path => urlJoin('/', `(${LOCALE_GLOB_PATTERN})`, path));
const protectedPagesWithLocale = protectedPagePrefixes.map(path => urlJoin('/', `(${LOCALE_GLOB_PATTERN})`, path));
const onboardingPathsWithLocale = onboardingPaths.map(path => urlJoin('/', `(${LOCALE_GLOB_PATTERN})`, path));
const appAdminPathsWithLocale = appAdminPaths.map(path => urlJoin('/', `(${LOCALE_GLOB_PATTERN})`, path));
const rootPathsWithLocale = rootPaths.map(path => urlJoin('/', `(${LOCALE_GLOB_PATTERN})`, path));
const allSubPathsWithLocale = [...rootPathsWithLocale, ...unprotectedPagesWithLocale, ...protectedPagesWithLocale, ...onboardingPathsWithLocale, ...appAdminPathsWithLocale];





function isUnprotectedPage(pathname: string) {
  return unprotectedPagePrefixes.some((prefix) => {
    const matchPath = match(prefix);
    return matchPath(pathname);
  });
}

type MiddlewareFunction = (request: NextRequest) => Promise<NextResponse>

interface MiddlewareConfig {
  matcher: string | string[]
  middleware: MiddlewareFunction
}

const middlewares: MiddlewareConfig[] = [
  {
    matcher: ['/', ...allSubPathsWithoutLocale],
    middleware: async (request) => {
      // redirect to /en if the locale is not /en or /
      const currentLocale = request.cookies.get('NEXT_LOCALE')?.value;
      if (currentLocale) {
        const parsedLocale = isValidLocale(currentLocale);
        if (parsedLocale) {
          return NextResponse.redirect(
            urlJoin(request.nextUrl.origin, currentLocale, request.nextUrl.pathname)
          );
        }
      }
      const response = NextResponse.redirect(
        urlJoin(request.nextUrl.origin, DEFAULT_LOCALE, request.nextUrl.pathname)
      );
      response.cookies.set('NEXT_LOCALE', DEFAULT_LOCALE);
      return response;
    }
  },

  {
    matcher: allSubPathsWithLocale,
    middleware: async (request) => {
      console.log('all i18n paths')
      const localeFromPath = request.nextUrl.pathname.split('/')[1];

      // Step 2: Create and call the next-intl middleware (example)
      const handleI18nRouting = createMiddleware({
        locales: LOCALES,
        defaultLocale: DEFAULT_LOCALE,
      });
      const response = handleI18nRouting(request);
      console.log(localeFromPath);
      if (isValidLocale(localeFromPath)) {
        // save cookie
        response.cookies.set('NEXT_LOCALE', localeFromPath);
      } else {
        response.cookies.delete('NEXT_LOCALE');
      }
      return response;
    }
  },
  {
    // protected routes
    matcher: protectedPagesWithLocale,
    middleware: async (req) => {
      const res = NextResponse.next();
      await updateSession(req);
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (!maybeUser) {
        return NextResponse.redirect(toSiteURL('/login'));
      }
      return res;
    }
  },
  {
    matcher: onboardingPathsWithLocale,
    middleware: async (req) => {
      const res = NextResponse.next();
      await updateSession(req);
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (shouldOnboardUser(req.nextUrl.pathname, maybeUser)) {
        return NextResponse.redirect(toSiteURL('/onboarding'));
      }
      return res;
    }
  },

  {
    // match /app_admin and /app_admin/ and all subpaths
    matcher: appAdminPathsWithLocale,
    middleware: async (req) => {
      const res = NextResponse.next();
      await updateSession(req);
      const supabase = createSupabaseMiddlewareClient(req);
      const sessionResponse = await supabase.auth.getSession();
      const maybeUser = sessionResponse?.data.session?.user;
      if (
        !(
          maybeUser &&
          'user_role' in maybeUser &&
          maybeUser.user_role === 'admin'
        )
      ) {
        return NextResponse.redirect(toSiteURL('/dashboard'));
      }
      return res;
    }
  },

]

function shouldOnboardUser(pathname: string, user: User | undefined) {
  const matchOnboarding = match(onboardingPaths);
  const isOnboardingRoute = matchOnboarding(pathname);
  if (!isUnprotectedPage(pathname) && user && !isOnboardingRoute) {
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
  }
  return false;
}




function matchesPath(matcher: string | string[], pathname: string): boolean {
  const matchers = Array.isArray(matcher) ? matcher : [matcher]
  return matchers.some(m => {
    const matchFn = match(m, { decode: decodeURIComponent })
    return matchFn(pathname) !== false
  })
}


export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  const applicableMiddlewares = middlewares.filter(m => matchesPath(m.matcher, pathname))

  let response = NextResponse.next()

  for (const { middleware } of applicableMiddlewares) {
    response = await middleware(request)
  }

  return response
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
    '/((?!_next/static|_next/image|favicon.ico|api|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
