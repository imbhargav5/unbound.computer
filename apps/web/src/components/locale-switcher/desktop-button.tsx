"use client";

import { Check, Languages } from "lucide-react";
import { useTransition } from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { usePathname, useRouter } from "@/i18n/navigation";
import type { Locale } from "@/i18n/routing";

interface LocaleSwitcherDesktopButtonProps {
  defaultLocale: Locale;
  options: { value: Locale; label: string }[];
  className?: string;
}

export function LocaleSwitcherDesktopButton({
  defaultLocale,
  options,
  className,
}: LocaleSwitcherDesktopButtonProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const pathname = usePathname();

  function onLocaleSelect(nextLocale: Locale) {
    startTransition(() => {
      router.push(pathname, { locale: nextLocale });
    });
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          aria-label="Change language"
          className={`h-8 w-8 p-0 ${className || ""}`}
          size="sm"
          variant="outline"
        >
          <Languages className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[180px]">
        {options.map((locale) => (
          <DropdownMenuItem
            className="justify-between"
            key={locale.value}
            onClick={() => onLocaleSelect(locale.value)}
          >
            {locale.label}
            {locale.value === defaultLocale && <Check className="h-4 w-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
