import { Suspense } from "react";
import { LoginCTAButton } from "@/components/navigation-menu/external-navbar/login-cta-button";
import { MobileMenu } from "@/components/navigation-menu/external-navbar/mobile-menu";

export async function MobileMenuWrapper() {
  return (
    <Suspense>
      <MobileMenu loginCtaButton={<LoginCTAButton />} />
    </Suspense>
  );
}
