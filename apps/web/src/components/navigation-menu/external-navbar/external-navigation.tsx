import { Suspense } from "react";
import { MobileMenuWrapper } from "@/components/mobile-menu-wrapper";
import { ThemeSwitch, ThemeSwitchFallback } from "@/components/theme-switch";
import { LeftNav } from "./left-nav";
import { LoginCTAButton } from "./login-cta-button";
import { MobileMenuOpen } from "./mobile-menu-open";

export async function ExternalNavigation() {
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
      <MobileMenuWrapper />
    </header>
  );
}
