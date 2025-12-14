"use client";

import { Check, ChevronDown } from "lucide-react";
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

interface LocaleSwitcherSelectProps {
  defaultLocale: Locale;
  options: { value: Locale; label: string }[];
}

export function LocaleSwitcherSelect({
  defaultLocale,
  options,
}: LocaleSwitcherSelectProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const pathname = usePathname();

  function onLocaleSelect(nextLocale: Locale) {
    startTransition(() => {
      router.push(pathname, { locale: nextLocale });
    });
  }

  const currentLocaleLabel = options.find(
    (locale) => locale.value === defaultLocale
  )?.label;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          className="w-[180px] justify-between"
          size="sm"
          variant="outline"
        >
          {currentLocaleLabel}
          <ChevronDown className="h-4 w-4 opacity-50" />
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
