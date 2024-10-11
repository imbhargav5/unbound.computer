"use client";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Locale, usePathname, useRouter } from "@/i18n/routing";
import { Check, ChevronDown } from "lucide-react";
import { useParams } from "next/navigation";
import { useTransition } from "react";

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
  const params = useParams();

  function onLocaleSelect(nextLocale: Locale) {
    startTransition(() => {
      router.push(pathname, { locale: nextLocale });
    });
  }

  const currentLocaleLabel = options.find(
    (locale) => locale.value === defaultLocale,
  )?.label;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className="w-[180px] justify-between"
        >
          {currentLocaleLabel}
          <ChevronDown className="h-4 w-4 opacity-50" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[180px]">
        {options.map((locale) => (
          <DropdownMenuItem
            key={locale.value}
            onClick={() => onLocaleSelect(locale.value)}
            className="justify-between"
          >
            {locale.label}
            {locale.value === defaultLocale && <Check className="h-4 w-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
