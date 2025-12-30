"use client";

import { Terminal } from "lucide-react";
import { usePathname } from "next/navigation";
import { Link } from "@/components/intl-link";
import { navbarLinks } from "./constants";
import { DocsMobileNavigation } from "./docs-mobile-navigation";

export function LeftNav() {
  const pathname = usePathname();

  const isBlogPage = pathname?.startsWith("/blog");
  const isDocsPage = pathname?.startsWith("/docs");

  return (
    <div className="flex items-center gap-8">
      <DocsMobileNavigation />
      <Link className="flex items-center gap-2" href="/">
        <div className="flex size-8 items-center justify-center rounded-lg border border-white/20">
          <Terminal className="size-4 text-white" />
        </div>
        <span className="font-medium text-white">
          {isBlogPage && "Unbound Blog"}
          {isDocsPage && "Unbound Docs"}
          {!(isBlogPage || isDocsPage) && "Unbound"}
        </span>
      </Link>
      <ul className="hidden items-center gap-6 lg:flex">
        {navbarLinks.map(({ name, href }) => (
          <li key={name}>
            <Link
              className="text-sm text-white/60 transition-colors hover:text-white"
              href={href}
            >
              {name}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
