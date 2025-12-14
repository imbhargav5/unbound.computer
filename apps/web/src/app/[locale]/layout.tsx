import { routing } from "@/i18n/routing";
import "@/styles/globals.css";
import { GeistSans } from "geist/font/sans";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { setRequestLocale } from "next-intl/server";
import { ThemeProvider } from "next-themes";
import { Suspense } from "react";
import { AffonsoWrapper } from "./affonso-wrapper";
import { AppProviders } from "./app-providers";

export const generateMetadata = async ({
  params,
}: {
  params: Promise<{ locale: string }>;
}) => ({
  title: "Nextbase Ultimate",
  description: "Nextbase Ultimate",
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://ultimate-demo.usenextbase.com"
  ),
});

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function DynamicContent({
  params,
  children,
}: {
  params: Promise<{ locale: string }>;
  children: React.ReactNode;
}) {
  const { locale } = await params;
  setRequestLocale(locale);

  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }

  return (
    <html
      className={`${GeistSans.className}`}
      lang={locale}
      suppressHydrationWarning
    >
      {children}
    </html>
  );
}

export default async function RootLayout(props: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { children } = props;
  return (
    <Suspense>
      <DynamicContent params={props.params}>
        <head>
          <Suspense>
            <AffonsoWrapper />
          </Suspense>
        </head>
        <body className="flex min-h-screen flex-col">
          <ThemeProvider attribute="class">
            <NextIntlClientProvider>
              {children}
              <Suspense>
                <AppProviders />
              </Suspense>
            </NextIntlClientProvider>
          </ThemeProvider>
        </body>
      </DynamicContent>
    </Suspense>
  );
}
