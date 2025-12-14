import { getTranslations } from "next-intl/server";
import { Suspense } from "react";
import { LoginCTAButton } from "@/components/navigation-menu/external-navbar/login-cta-button";
import { MobileMenu } from "@/components/navigation-menu/external-navbar/mobile-menu";
import type { Locale } from "@/i18n/routing";
import { getLabelOptions } from "@/utils/server/get-label-options";

export async function MobileMenuWrapper({ locale }: { locale: Locale }) {
  const labelOptions = await getLabelOptions(locale);
  const localSwitcherTranslations = await getTranslations({
    locale,
    namespace: "LocaleSwitcher",
  });
  return (
    <Suspense>
      <MobileMenu
        labelOptions={labelOptions}
        labelText={localSwitcherTranslations("label")}
        locale={locale}
        loginCtaButton={<LoginCTAButton />}
      />
    </Suspense>
  );
}
