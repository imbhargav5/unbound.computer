import { LandingPage } from "@/components/LandingPage";
import { unstable_setRequestLocale } from "next-intl/server";
import "server-only";

export default async function Page(props: {
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;

  const { locale } = params;

  unstable_setRequestLocale(locale);

  return (
    <div>
      <LandingPage />
    </div>
  );
}
