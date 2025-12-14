import { Suspense } from "react";
import { LocaleSwitcherDesktopButton } from "@/components/locale-switcher/desktop-button";
import { DEFAULT_LOCALE, isValidLocale } from "@/constants";
import type { Locale } from "@/i18n/routing";
import { getLabelOptions } from "@/utils/server/get-label-options";

export async function DesktopLocaleSwitcherWrapper({
  locale,
}: {
  locale: Locale;
}) {
  const labelOptions = await getLabelOptions(locale);
  const defaultLocale = isValidLocale(locale) ? locale : DEFAULT_LOCALE;

  return (
    <Suspense>
      <LocaleSwitcherDesktopButton
        className="hidden md:block"
        defaultLocale={defaultLocale}
        options={labelOptions}
      />
    </Suspense>
  );
}
