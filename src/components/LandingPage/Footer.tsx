import { Link } from "@/components/intl-link";
import Image from "next/image";
import { footerItems, footerSocialItems } from "./footer-items";

export function Footer() {
  return (
    <footer className="bg-background min-h-[200px] text-foreground border-t border-border/30">
      <div className="max-w-6xl mx-auto pt-12 md:pt-20 px-6 lg:px-6 xl:px-0">
        <div className="flex flex-col">
          <div className="flex flex-col lg:flex-row items-start gap-y-10 pb-16 md:pb-20">
            <div className="flex flex-col w-full gap-6">
              <Link href="/">
                <div className="relative flex gap-2 items-center">
                  <Image
                    src={"/logos/nextbase.png"}
                    alt="logo"
                    width={64}
                    height={64}
                  />
                  <span className="font-medium text-2xl text-foreground sm:inline-block">
                    Nextbase
                  </span>
                </div>
              </Link>
              <p className="text-muted-foreground max-w-[350px] dark:font-light">
                Acme Inc. 123 Acme Street, London, UK, SW1A 1AA
              </p>
            </div>
            <div className="flex flex-wrap w-full justify-start lg:justify-end gap-8 lg:gap-16">
              {footerItems.map((item) => (
                <div className="space-y-4" key={item.title}>
                  <h3 className="font-semibold uppercase text-sm tracking-wide">
                    {item.title}
                  </h3>
                  <ul className="space-y-3 mt-2">
                    {item.items.map((link) => (
                      <li
                        className="text-muted-foreground hover:text-foreground transition-colors dark:font-light"
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
          <div className="w-full h-[1px] bg-border/50 dark:bg-slate-800"></div>
          <div className="flex flex-col gap-6 md:flex-row md:gap-0 justify-between items-center py-8 w-full">
            <p className="text-muted-foreground dark:text-slate-400 text-sm text-center md:text-left order-2 md:order-1">
              © 2023
              <a
                href="https://usenextbase.com/"
                className="mx-2 hover:underline"
                target="_blank"
                rel="noopener noreferrer"
              >
                Arni Creative Private Limited.
              </a>
              All Rights Reserved
            </p>
            <div className="flex justify-center md:justify-end gap-6 w-full md:w-auto order-1 md:order-2">
              {footerSocialItems.map((item) => (
                <Link
                  key={item.name}
                  href={item.url}
                  className="text-muted-foreground hover:text-foreground transition-colors"
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
