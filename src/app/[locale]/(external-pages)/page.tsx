import { LandingPage } from "@/components/LandingPage";
import { unstable_setRequestLocale } from "next-intl/server";
import "server-only";

export default function Page({
  params: { locale },
}: {
  params: { locale: string };
}) {
  unstable_setRequestLocale(locale);

  return (
    <main>
      <LandingPage />
    </main>
  );
}
