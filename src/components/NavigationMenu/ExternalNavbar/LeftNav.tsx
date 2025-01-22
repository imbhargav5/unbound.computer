"use client";

import { Link } from "@/components/intl-link";
import { cn } from "@/utils/cn";
import acmeLightLogo from "@public/logos/acme-logo-dark.png";
import acmeDarkLogo from "@public/logos/acme-logo-light.png";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { DocsMobileNavigation } from "./DocsMobileNavigation";
import { navbarLinks } from "./constants";

export function LeftNav() {
  const pathname = usePathname();

  const isBlogPage = pathname?.startsWith("/blog");
  const isDocsPage = pathname?.startsWith("/docs");

  return (
    <div className="flex items-center gap-8">
      <DocsMobileNavigation />
      <div className="flex space-x-8">
        <Link href="/" className={cn("font-bold text-xl ")}>
          <div className="relative flex space-x-2 h-10 md:w-fit items-center justify-center text-black dark:text-white dark:-ml-4 -ml-2">
            <Image
              src={acmeLightLogo}
              width={40}
              height={40}
              alt="logo"
              className="dark:hidden block h-8 w-8"
            />
            <Image
              src={acmeDarkLogo}
              width={40}
              height={40}
              alt="logo"
              className="hidden dark:block h-8 w-8"
            />
            {isBlogPage && <span className="font-bold">Nextbase Blog</span>}
            {isDocsPage && <span className="font-bold">Nextbase Docs</span>}
            {!isBlogPage && !isDocsPage && (
              <span className="font-bold">Nextbase</span>
            )}
          </div>
        </Link>
      </div>
      <ul className="hidden lg:flex gap-8 font-medium items-center">
        {navbarLinks.map(({ name, href }) => (
          <li
            key={name}
            className="text-gray-500 dark:text-gray-300 font-regular text-sm hover:text-gray-800 dark:hover:text-gray-500"
          >
            <Link href={href}>{name}</Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
