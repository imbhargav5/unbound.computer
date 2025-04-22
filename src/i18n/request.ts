import { getRequestConfig } from "next-intl/server";
import { notFound } from "next/navigation";
import { Locale, routing } from "./routing";

export default getRequestConfig(async ({ requestLocale }) => {
  // Validate that the incoming `locale` parameter is valid
  const locale = await requestLocale;
  if (!locale || !routing.locales.includes(locale as Locale)) notFound();

  return {
    messages: (await import(`../../messages/${locale}.json`)).default,
    locale,
  };
});
