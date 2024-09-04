import {
  type User
} from '@supabase/auth-helpers-nextjs';
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
// const matchAppAdmin = match('/app_admin_preview/(.*)?');
import { match } from 'path-to-regexp';
import { updateSession } from './supabase-clients/middleware';
import { createSupabaseMiddlewareClient } from './supabase-clients/user/createSupabaseMiddlewareClient';
import { toSiteURL } from './utils/helpers';
import { authUserMetadataSchema } from './utils/zod-schemas/authUserMetadata';

const onboardingPaths = `/onboarding/(.*)?`;
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
  `/testing(/.*)?`,
];

function isUnprotectedPage(pathname: string) {
  return unprotectedPagePrefixes.some((prefix) => {
    const matchPath = match(prefix);
    return matchPath(pathname);
  });
}

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

// this middleware refreshes the user's session and must be run
// for any Server Component route that uses `createServerComponentSupabaseClient`
export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  await updateSession(req);
  const supabase = createSupabaseMiddlewareClient(req);
  const sessionResponse = await supabase.auth.getSession();
  const maybeUser = sessionResponse?.data.session?.user;
  if (shouldOnboardUser(req.nextUrl.pathname, maybeUser)) {
    console.log('redirecting to onboarding');
    return NextResponse.redirect(toSiteURL('/onboarding'));
  }
  // only do optimistic updates in middleware.
  // don't try to contact the database.
  if (!isUnprotectedPage(req.nextUrl.pathname) && !maybeUser) {
    return NextResponse.redirect(toSiteURL('/login'));
  }
  if (
    !req.nextUrl.pathname.startsWith(`/app_admin_preview`) &&
    req.nextUrl.pathname.startsWith('/app_admin')
  ) {
    if (
      !(
        maybeUser &&
        'user_role' in maybeUser &&
        maybeUser.user_role === 'admin'
      )
    ) {
      return NextResponse.redirect(toSiteURL('/dashboard'));
    }
  }
  return res;
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
