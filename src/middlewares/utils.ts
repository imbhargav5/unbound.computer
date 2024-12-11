import { LOCALES } from "@/constants";
import { Locale } from "@/i18n/routing";
import { User } from "@supabase/supabase-js";
import { NextRequest } from "next/server";
import { match } from "path-to-regexp";
import urlJoin from "url-join";
import { authUserMetadataSchema } from "../utils/zod-schemas/authUserMetadata";

/**
 * Prepends the current locale to a given subPath if a locale cookie exists
 * @param request - The Next.js request object containing cookies
 * @param subPath - The path to potentially prefix with the locale
 * @returns The subPath with the locale prepended if it exists, otherwise just the subPath
 * @example
 * // If NEXT_LOCALE cookie is 'en'
 * withMaybeLocale(request, '/dashboard') // Returns 'en/dashboard'
 * // If no NEXT_LOCALE cookie
 * withMaybeLocale(request, '/dashboard') // Returns '/dashboard'
 */
export function withMaybeLocale(request: NextRequest, subPath: string) {
  const currentLocale = request.cookies.get("NEXT_LOCALE")?.value;
  if (currentLocale) {
    return urlJoin(currentLocale, subPath);
  }
  return subPath;
}

/**
 * Checks if a pathname matches one or more path patterns
 * @param matcher - A single path pattern or array of path patterns to match against
 * @param pathname - The pathname to check
 * @returns True if the pathname matches any of the patterns, false otherwise
 * @example
 * matchesPath('/users/:id', '/users/123') // Returns true
 * matchesPath(['/users/:id', '/admin/:id'], '/users/123') // Returns true
 */
export function matchesPath(
  matcher: string | string[],
  pathname: string,
): boolean {
  const matchers = Array.isArray(matcher) ? matcher : [matcher];
  return matchers.some((m) => {
    const matchFn = match(m, { decode: decodeURIComponent });
    return matchFn(pathname) !== false;
  });
}

/**
 * Determines if a user needs to complete the onboarding process
 * @param user - The Supabase user object
 * @returns True if any onboarding steps are incomplete, false if all steps are complete
 * @example
 * shouldOnboardUser(user) // Returns true if any onboarding steps are incomplete
 */
export function shouldOnboardUser(user: User) {
  const userMetadata = authUserMetadataSchema.parse(user.user_metadata);
  const {
    onboardingHasAcceptedTerms,
    onboardingHasCompletedProfile,
    onboardingHasCreatedWorkspace,
  } = userMetadata;

  return (
    !onboardingHasAcceptedTerms ||
    !onboardingHasCompletedProfile ||
    !onboardingHasCreatedWorkspace
  );
}

export function isStringALocale(maybeLocale: string): maybeLocale is Locale {
  return LOCALES.some((locale) => locale === maybeLocale);
}
