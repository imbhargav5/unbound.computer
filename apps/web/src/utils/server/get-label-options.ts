import { getTranslations } from "next-intl/server";
import { type Locale, routing } from "@/i18n/routing";

export async function getLabelOptions(locale: Locale) {
  const t = await getTranslations({
    locale,
    namespace: "LocaleSwitcher.localeLabels",
  });
  return routing.locales.map((cur) => ({
    value: cur,
    label: t(cur),
  }));
}
