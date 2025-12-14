import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { redirect } from "@/i18n/navigation";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { LogoutClient } from "./logout-client";

async function LogoutContent(props: { locale: string }) {
  const { locale } = props;
  const userClaims = await serverGetLoggedInUserClaims();
  if (userClaims) {
    return <LogoutClient />;
  }
  redirect({ href: "/", locale });
}

export default async function Logout(props: {
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;
  const { locale } = params;
  setRequestLocale(locale);
  return (
    <Suspense>
      <LogoutContent locale={locale} />
    </Suspense>
  );
}
