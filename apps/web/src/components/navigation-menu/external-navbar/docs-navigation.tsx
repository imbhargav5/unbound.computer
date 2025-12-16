"use client";

import clsx from "clsx";
import { usePathname } from "next/navigation";
import { Link } from "@/components/intl-link";
import { navigation } from "./docslinks";

type NavigationProps = {
  className?: string;
  setIsOpen?: (isOpen: boolean) => void;
};

export function DocsNavigation({ className, setIsOpen }: NavigationProps) {
  const pathname = usePathname();
  const handleClick = () => {
    setTimeout(() => {
      setIsOpen?.(false);
    }, 500);
  };

  return (
    <nav className={clsx("text-base lg:text-sm", className)}>
      <ul className="space-y-9" role="list">
        {navigation.map((section) => (
          <li key={section.title} onClick={handleClick}>
            <h2 className="font-bold font-display text-neutral-800 text-xs uppercase tracking-wider dark:text-neutral-500">
              {section.title}
            </h2>
            <ul className="mt-2 space-y-2 lg:mt-2 lg:space-y-2.5" role="list">
              {section.links.map((link) => (
                <li className="relative" key={link.href}>
                  <Link
                    className={clsx(
                      "block w-full",
                      link.href === pathname
                        ? "font-semibold text-primary before:bg-neutral-500 dark:text-white dark:underline dark:before:bg-neutral-400"
                        : "text-neutral-600 before:hidden before:bg-neutral-300 hover:text-neutral-600 hover:before:block dark:text-neutral-300 dark:hover:text-neutral-300 dark:before:bg-neutral-700"
                    )}
                    href={link.href}
                  >
                    {link.title}
                  </Link>
                </li>
              ))}
            </ul>
          </li>
        ))}
      </ul>
    </nav>
  );
}
