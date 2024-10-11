import { ExternalNavigation } from "@/components/NavigationMenu/ExternalNavbar/ExternalNavigation";
import { routing } from "@/i18n/routing";
import { unstable_setRequestLocale } from "next-intl/server";
import "./layout.css";
export const dynamic = "force-static";
export const revalidate = 60;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}
export default function Layout({
  children,
  params: { locale },
}: {
  children: React.ReactNode;
  params: { locale: string };
}) {
  unstable_setRequestLocale(locale);
  return (
    <div>
      <ExternalNavigation />
      {children}
    </div>
  );
}
