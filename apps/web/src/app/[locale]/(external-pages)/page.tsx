import { setRequestLocale } from "next-intl/server";
import { LandingPage } from "@/components/landing-page";

export default async function Page(props: {
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;

  const { locale } = params;

  setRequestLocale(locale);

  return (
    <div>
      <LandingPage locale={locale} />
    </div>
  );
}
