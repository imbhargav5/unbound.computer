import { Suspense } from "react";
import { DesktopLocaleSwitcherWrapper } from "@/components/desktop-locale-switcher-wrapper";
import { MobileMenuWrapper } from "@/components/mobile-menu-wrapper";
import { ThemeSwitch, ThemeSwitchFallback } from "@/components/theme-switch";
import type { Locale } from "@/i18n/routing";
import { LeftNav } from "./left-nav";
import { LoginCTAButton } from "./login-cta-button";
import { MobileMenuOpen } from "./mobile-menu-open";

export async function ExternalNavigation({ locale }: { locale: Locale }) {
  return (
    <header className="sticky inset-x-0 top-0 z-50 w-full border-b backdrop-blur-3xl">
      <nav
        aria-label="Global"
        className="flex h-[54px] w-full items-center justify-between px-6 md:container md:mx-auto md:px-8"
      >
        <Suspense>
          <LeftNav />
        </Suspense>
        <div className="flex gap-5">
          <div className="lg:-mr-2 flex items-center space-x-3">
            <Suspense fallback={<div>Loading...</div>}>
              <DesktopLocaleSwitcherWrapper locale={locale} />
            </Suspense>
            <Suspense fallback={<ThemeSwitchFallback />}>
              <ThemeSwitch />
            </Suspense>
            <div className="ml-6 hidden lg:block" suppressHydrationWarning>
              <Suspense>
                <LoginCTAButton />
              </Suspense>
            </div>
          </div>
          <Suspense>
            <MobileMenuOpen />
          </Suspense>
        </div>
      </nav>
      <MobileMenuWrapper locale={locale} />
    </header>
  );
}
