import "@/styles/globals.css";
import { GeistSans } from "geist/font/sans";
import { ThemeProvider } from "next-themes";
import { Suspense } from "react";
import { AffonsoWrapper } from "./affonso-wrapper";
import { AppProviders } from "./app-providers";

export const generateMetadata = async () => ({
  title: "Nextbase Ultimate",
  description: "Nextbase Ultimate",
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://ultimate-demo.usenextbase.com"
  ),
});

async function StaticContent({ children }: { children: React.ReactNode }) {
  "use cache";
  return (
    <>
      <head>
        <Suspense>
          <AffonsoWrapper />
        </Suspense>
      </head>
      <body className="flex min-h-screen flex-col">
        <ThemeProvider attribute="class">{children}</ThemeProvider>
      </body>
    </>
  );
}

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html className={GeistSans.className} lang="en" suppressHydrationWarning>
      <StaticContent>
        {children}
        <Suspense>
          <AppProviders />
        </Suspense>
      </StaticContent>
    </html>
  );
}
