import { setRequestLocale } from "next-intl/server";
import { ExternalNavigation } from "@/components/navigation-menu/external-navbar/external-navigation";
import "./layout.css";
import { notFound } from "next/navigation";
import { isValidLocale } from "@/constants";

export default async function Layout(props: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;

  const { locale } = params;

  const { children } = props;

  setRequestLocale(locale);
  if (isValidLocale(locale)) {
    return (
      <div>
        <ExternalNavigation locale={locale} />
        {children}
      </div>
    );
  }
  notFound();
}
