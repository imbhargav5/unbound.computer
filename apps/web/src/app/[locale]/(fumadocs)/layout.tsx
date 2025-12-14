import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { baseOptions } from "@/app/layout.config";
import { isValidLocale } from "@/constants";
import { source } from "../source";
import "@/styles/docs-layout-styles.css";
import { RootProvider } from "fumadocs-ui/provider/next";

export default async function Layout({
  params,
  children,
}: {
  params: Promise<{ locale: string }>;
  children: React.ReactNode;
}) {
  const { locale } = await params;
  if (!isValidLocale(locale)) {
    notFound();
  }

  setRequestLocale(locale);

  return (
    <RootProvider>
      <DocsLayout tree={source.pageTree[locale]} {...baseOptions(locale)}>
        {children}
      </DocsLayout>
    </RootProvider>
  );
}
