// next-intl currently has a compatibility issue with next.js cache components
// nextjs cache components have a few issues that make it hard to work with next-intl
//https://github.com/amannn/next-intl/issues/1493
//TLDR: getting locale in server actions is not possible at this time.
// hence this util

import { headers } from "next/headers";
import { DEFAULT_LOCALE, isValidLocale } from "@/constants";

/**
 * Gets the locale from the referer header, if the locale is valid, otherwise returns the default locale
 * @returns The locale from the referer header, or the default locale if no locale is found
 */
export async function serverGetRefererLocale() {
  const headersList = await headers();
  const referer = headersList.get("referer");
  if (referer) {
    const url = new URL(referer);
    const pathname = url.pathname;
    const locale = pathname.split("/")[1];
    if (isValidLocale(locale)) {
      return locale;
    }
  }
  return DEFAULT_LOCALE;
}
