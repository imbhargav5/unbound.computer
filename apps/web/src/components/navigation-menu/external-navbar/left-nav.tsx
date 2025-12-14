"use client";

import Image from "next/image";
import { Link } from "@/components/intl-link";
import { usePathname } from "@/i18n/navigation";
import { cn } from "@/utils/cn";
import { navbarLinks } from "./constants";
import { DocsMobileNavigation } from "./docs-mobile-navigation";

export function LeftNav() {
  const pathname = usePathname();

  const isBlogPage = pathname?.startsWith("/blog");
  const isDocsPage = pathname?.startsWith("/docs");

  return (
    <div className="flex items-center gap-8">
      <DocsMobileNavigation />
      <div className="flex space-x-8">
        <Link className={cn("font-bold text-xl")} href="/">
          <div className="dark:-ml-4 -ml-2 relative flex h-10 items-center justify-center space-x-2 md:w-fit">
            <Image
              alt="light-logo"
              height={32}
              src={"/logos/nextbase.png"}
              width={32}
            />

            {isBlogPage && (
              <span className="font-bold text-foreground">Nextbase Blog</span>
            )}
            {isDocsPage && (
              <span className="font-bold font-bold text-foreground">
                Nextbase Docs
              </span>
            )}
            {!(isBlogPage || isDocsPage) && (
              <span className="font-bold">Nextbase</span>
            )}
          </div>
        </Link>
      </div>
      <ul className="hidden items-center gap-8 font-medium lg:flex">
        {navbarLinks.map(({ name, href }) => (
          <li
            className="font-regular text-muted-foreground text-sm hover:text-foreground"
            key={name}
          >
            <Link href={href}>{name}</Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
