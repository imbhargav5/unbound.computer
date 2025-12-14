import Image from "next/image";
import { Link } from "@/components/intl-link";
import { footerItems, footerSocialItems } from "./footer-items";

export function Footer() {
  return (
    <footer className="min-h-[200px] border-border/30 border-t bg-background text-foreground">
      <div className="mx-auto max-w-6xl px-6 pt-12 md:pt-20 lg:px-6 xl:px-0">
        <div className="flex flex-col">
          <div className="flex flex-col items-start gap-y-10 pb-16 md:pb-20 lg:flex-row">
            <div className="flex w-full flex-col gap-6">
              <Link href="/">
                <div className="relative flex items-center gap-2">
                  <Image
                    alt="logo"
                    height={64}
                    src={"/logos/nextbase.png"}
                    width={64}
                  />
                  <span className="font-medium text-2xl text-foreground sm:inline-block">
                    Nextbase
                  </span>
                </div>
              </Link>
              <p className="max-w-[350px] text-muted-foreground dark:font-light">
                Acme Inc. 123 Acme Street, London, UK, SW1A 1AA
              </p>
            </div>
            <div className="flex w-full flex-wrap justify-start gap-8 lg:justify-end lg:gap-16">
              {footerItems.map((item) => (
                <div className="space-y-4" key={item.title}>
                  <h3 className="font-semibold text-sm uppercase tracking-wide">
                    {item.title}
                  </h3>
                  <ul className="mt-2 space-y-3">
                    {item.items.map((link) => (
                      <li
                        className="text-muted-foreground transition-colors hover:text-foreground dark:font-light"
                        key={link.name}
                      >
                        <Link href={link.url}>{link.name}</Link>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          </div>
          <div className="h-[1px] w-full bg-border/50 dark:bg-slate-800" />
          <div className="flex w-full flex-col items-center justify-between gap-6 py-8 md:flex-row md:gap-0">
            <p className="order-2 text-center text-muted-foreground text-sm md:order-1 md:text-left dark:text-slate-400">
              © 2023
              <a
                className="mx-2 hover:underline"
                href="https://usenextbase.com/"
                rel="noopener noreferrer"
                target="_blank"
              >
                Arni Creative Private Limited.
              </a>
              All Rights Reserved
            </p>
            <div className="order-1 flex w-full justify-center gap-6 md:order-2 md:w-auto md:justify-end">
              {footerSocialItems.map((item) => (
                <Link
                  className="text-muted-foreground transition-colors hover:text-foreground"
                  href={item.url}
                  key={item.name}
                >
                  <item.icon />
                  <span className="sr-only">{item.name}</span>
                </Link>
              ))}
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
