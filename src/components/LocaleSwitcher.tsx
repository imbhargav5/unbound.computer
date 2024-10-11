import { DEFAULT_LOCALE, isValidLocale } from "@/constants";
import { routing } from "@/i18n/routing";
import { useLocale, useTranslations } from "next-intl";
import { LocaleSwitcherSelect } from "./LocaleSwitcherSelect";

export default function LocaleSwitcher() {
  const locale = useLocale();
  const localeLabels = useTranslations("LocaleSwitcher.localeLabels");
  const labelOptions = routing.locales.map((cur) => ({
    value: cur,
    label: localeLabels(cur),
  }));
  const defaultLocale = isValidLocale(locale) ? locale : DEFAULT_LOCALE;

  return (
    <LocaleSwitcherSelect
      options={labelOptions}
      defaultLocale={defaultLocale}
    />
  );
}
