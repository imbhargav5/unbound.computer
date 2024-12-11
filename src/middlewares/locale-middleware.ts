import createMiddleware from "next-intl/middleware";
import { NextResponse } from "next/server";
import { DEFAULT_LOCALE, LOCALES } from "../constants";
import { allPaths } from "./paths";
import { MiddlewareConfig } from "./types";
import { isStringALocale } from "./utils";

export const localeMiddleware: MiddlewareConfig = {
  matcher: ["/((?!api|_next|.*\\..*).*)", ...allPaths],
  middleware: async (request) => {
    // Create the i18n middleware handler
    const handler = createMiddleware({
      locales: LOCALES,
      defaultLocale: DEFAULT_LOCALE,
      localePrefix: "always",
    });

    // Get the locale from the URL path
    const pathname = request.nextUrl.pathname;
    const localeFromPath = pathname.split("/")[1];
    const searchParams = request.nextUrl.searchParams.toString();
    const search = searchParams ? `?${searchParams}` : "";

    // If the URL doesn't start with a locale, redirect to the default or stored locale
    if (!isStringALocale(localeFromPath)) {
      const storedLocale = request.cookies.get("NEXT_LOCALE")?.value;
      let targetLocale = DEFAULT_LOCALE;
      if (storedLocale && isStringALocale(storedLocale)) {
        targetLocale = storedLocale;
      }

      const response = NextResponse.redirect(
        new URL(`/${targetLocale}${pathname}${search}`, request.url),
      );
      response.cookies.set("NEXT_LOCALE", targetLocale);
      return [response, null];
    }

    // Handle the request with next-intl middleware
    const response = handler(request);

    // Update the locale cookie if needed
    response.cookies.set("NEXT_LOCALE", localeFromPath);
    return [response, null];
  },
};
