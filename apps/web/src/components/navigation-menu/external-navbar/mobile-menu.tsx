"use client";
import { Link } from "@/components/intl-link";
import { LocaleSwitcherMobileTabletDialog } from "@/components/locale-switcher/mobile-tablet-dialog";
import { LocaleSwitcherMobileTabletLink } from "@/components/locale-switcher/mobile-tablet-link";
import { useLocaleSwitcherDialog } from "@/hooks/use-locale-switcher-dialog";
import { useMobileMenu } from "@/hooks/use-mobile-menu";
import type { Locale } from "@/i18n/routing";
import { navbarLinks } from "./constants";

function MobileLanguageSwitcher({
  locale,
  labelText,
  labelOptions,
}: {
  locale: Locale;
  labelText: string;
  labelOptions: { value: Locale; label: string }[];
}) {
  const { isOpen: dialogOpen, setIsOpen: setDialogOpen } =
    useLocaleSwitcherDialog();

  return (
    <>
      <LocaleSwitcherMobileTabletLink
        label={labelText}
        onClick={() => setDialogOpen(true)}
      />
      <LocaleSwitcherMobileTabletDialog
        defaultLocale={locale}
        labelText={labelText}
        onOpenChange={setDialogOpen}
        open={dialogOpen}
        options={labelOptions}
      />
    </>
  );
}

export function MobileMenu({
  loginCtaButton,
  locale,
  labelText,
  labelOptions,
}: {
  loginCtaButton: React.ReactNode;
  locale: Locale;
  labelText: string;
  labelOptions: { value: Locale; label: string }[];
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

          <li className="w-full">
            <MobileLanguageSwitcher
              labelOptions={labelOptions}
              labelText={labelText}
              locale={locale}
            />
          </li>

          <hr className="h-2 w-full" />
          <div className="flex w-full px-4">{loginCtaButton}</div>
        </ul>
      )}
    </>
  );
}
