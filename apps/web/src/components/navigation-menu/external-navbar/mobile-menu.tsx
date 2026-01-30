"use client";
import { Link } from "@/components/intl-link";
import { useMobileMenu } from "@/hooks/use-mobile-menu";
import { navbarLinks } from "./constants";

export function MobileMenu({
  loginCtaButton,
}: {
  loginCtaButton: React.ReactNode;
}) {
  const { isOpen, close } = useMobileMenu();
  return (
    <>
      {isOpen && (
        <ul className="flex w-full flex-col items-start py-2 pb-2 font-medium shadow-2xl md:hidden">
          {navbarLinks.map(({ name, href }) => (
            <li
              className="rounded-lg px-4 py-2 text-gray-900 dark:text-gray-300"
              key={name}
            >
              <Link href={href} onClick={close}>
                {name}
              </Link>
            </li>
          ))}

          <hr className="h-2 w-full" />
          <div className="flex w-full px-4">{loginCtaButton}</div>
        </ul>
      )}
    </>
  );
}
