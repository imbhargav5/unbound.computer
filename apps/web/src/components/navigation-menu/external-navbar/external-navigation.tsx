import { Suspense } from "react";
import { MobileMenuWrapper } from "@/components/mobile-menu-wrapper";
import { LeftNav } from "./left-nav";
import { LoginCTAButton } from "./login-cta-button";
import { MobileMenuOpen } from "./mobile-menu-open";

export async function ExternalNavigation() {
  return (
    <header className="sticky inset-x-0 top-0 z-50 w-full border-white/10 border-b bg-black/80 backdrop-blur-xl">
      <nav
        aria-label="Global"
        className="flex h-[54px] w-full items-center justify-between px-6 md:container md:mx-auto md:px-8"
      >
        <Suspense>
          <LeftNav />
        </Suspense>
        <div className="flex items-center gap-4">
          <div className="hidden lg:block">
            <Suspense>
              <LoginCTAButton />
            </Suspense>
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
