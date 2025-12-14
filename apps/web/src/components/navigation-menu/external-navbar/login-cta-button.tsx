import { ExternalNavigationCTAButton } from "@/components/navigation-menu/external-navbar/external-navigation-cta-button";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

export async function LoginCTAButton() {
  let isLoggedIn = false;
  try {
    const claims = await serverGetLoggedInUserClaims();
    isLoggedIn = Boolean(claims?.sub);
  } catch (error) {
    isLoggedIn = false;
  }
  return <ExternalNavigationCTAButton isLoggedIn={isLoggedIn} />;
}
