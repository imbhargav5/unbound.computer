"use client";

import { Check } from "lucide-react";
import { useTransition } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { usePathname, useRouter } from "@/i18n/navigation";
import type { Locale } from "@/i18n/routing";

interface LocaleSwitcherMobileTabletDialogProps {
  defaultLocale: Locale;
  labelText: string;
  options: { value: Locale; label: string }[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function LocaleSwitcherMobileTabletDialog({
  defaultLocale,
  options,
  labelText,
  open,
  onOpenChange,
}: LocaleSwitcherMobileTabletDialogProps) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const pathname = usePathname();

  function onLocaleSelect(nextLocale: Locale) {
    startTransition(() => {
      router.push(pathname, { locale: nextLocale });
      onOpenChange(false);
    });
  }

  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{labelText}</DialogTitle>
        </DialogHeader>
        <div className="space-y-2">
          {options.map((locale) => (
            <button
              className={`flex w-full items-center justify-between rounded-lg p-3 text-left transition-colors hover:bg-accent ${
                locale.value === defaultLocale ? "bg-accent" : ""
              }`}
              key={locale.value}
              onClick={() => onLocaleSelect(locale.value)}
            >
              <span className="font-medium">{locale.label}</span>
              {locale.value === defaultLocale && (
                <Check className="h-4 w-4 text-primary" />
              )}
            </button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
