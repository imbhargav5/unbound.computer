import { GeistSans } from "geist/font/sans";
import type { Metadata } from "next";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Typography } from "@/components/ui/typography-ui";

export const metadata: Metadata = {
  title: "404 - Not Found",
  description: "The page you are looking for does not exist.",
};

export default function NotFound() {
  return (
    <html className={GeistSans.className}>
      <body className="bg-background">
        <div className="flex min-h-screen items-center justify-center bg-linear-to-b from-background to-secondary/20">
          <div className="flex flex-col items-center space-y-4 text-center">
            <Typography.H1>404.</Typography.H1>
            <Typography.P>
              The page you&apos;re looking for doesn&apos;t exist or has been
              moved.
            </Typography.P>
            <Button asChild className="font-semibold" size="lg">
              <Link href="/">Return to Home</Link>
            </Button>
          </div>
        </div>
      </body>
    </html>
  );
}
