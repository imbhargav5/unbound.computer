import { ExternalNavigation } from "@/components/NavigationMenu/ExternalNavbar/ExternalNavigation";
import { routing } from "@/i18n/routing";
import { unstable_setRequestLocale } from "next-intl/server";
import "./layout.css";
export const dynamic = "force-static";
export const revalidate = 60;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}
export default async function Layout(props: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;

  const { locale } = params;

  const { children } = props;

  unstable_setRequestLocale(locale);
  return (
    <div>
      <ExternalNavigation />
      {children}
    </div>
  );
}
