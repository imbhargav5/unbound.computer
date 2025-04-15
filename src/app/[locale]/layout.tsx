import "@/styles/globals.css";
import { GeistSans } from "geist/font/sans";
import { Metadata } from "next";
import { getMessages } from "next-intl/server";
import "server-only";
import { AffonsoWrapper } from "./AffonsoWrapper";
import { AppProviders } from "./AppProviders";

export const metadata: Metadata = {
  icons: {
    icon: "/images/logo-black-main.ico",
  },
  title: "Nextbase Ultimate",
  description: "Nextbase Ultimate",
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? `https://usenextbase.com`,
  ),
};

export default async function RootLayout(props: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;

  const { locale } = params;

  const { children } = props;

  // Providing all messages to the client
  // side is the easiest way to get started
  const messages = await getMessages({
    locale: locale,
  });
  return (
    <html
      lang={locale}
      className={GeistSans.className}
      suppressHydrationWarning
    >
      <head>
        <AffonsoWrapper />
      </head>
      <body className="flex flex-col min-h-screen">
        <AppProviders locale={locale} messages={messages}>
          {children}
        </AppProviders>
      </body>
    </html>
  );
}
