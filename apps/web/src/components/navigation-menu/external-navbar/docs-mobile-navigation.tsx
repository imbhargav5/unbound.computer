"use client";
import lightLogo from "@public/logos/acme-logo-dark.png";
import darkLogo from "@public/logos/acme-logo-light.png";
import { PanelLeft } from "lucide-react";
import Image from "next/image";
import { type ComponentProps, useState } from "react";
import { Link } from "@/components/intl-link";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet";
import { usePathname, useRouter } from "@/i18n/navigation";
import { DocsNavigation } from "./docs-navigation";

function MenuIcon(props: ComponentProps<"svg">) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      strokeLinecap="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      {...props}
    >
      <path d="M4 7h16M4 12h16M4 17h16" />
    </svg>
  );
}

function CloseIcon(props: ComponentProps<"svg">) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      strokeLinecap="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      {...props}
    >
      <path d="M5 5l14 14M19 5l-14 14" />
    </svg>
  );
}

export function DocsMobileNavigation() {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);
  const pathname = usePathname();
  const isDocs = pathname ? pathname.startsWith("/docs") : false;

  if (!isDocs) {
    return null;
  }

  return (
    <Sheet onOpenChange={setIsOpen} open={isOpen}>
      <SheetTrigger asChild>
        <button
          aria-label="Open navigation"
          className="relative md:hidden"
          onClick={() => setIsOpen(true)}
          type="button"
        >
          <PanelLeft className="h-6 w-6 stroke-muted-foreground" />
        </button>
      </SheetTrigger>
      <SheetContent
        className="min-h-full w-full max-w-xs bg-white px-6 pt-5 pb-12 sm:px-6 dark:bg-gray-900"
        side="left"
      >
        <div className="flex items-center">
          <Link className="font-bold text-xl" href={"/"}>
            <div className="dark:-ml-4 relative flex items-center space-x-2 text-black dark:text-white">
              <Image
                alt="logo"
                className="block h-10 w-10 dark:hidden"
                src={lightLogo}
              />
              <Image
                alt="logo"
                className="hidden h-10 w-10 dark:block"
                src={darkLogo}
              />
              <span className="hidden font-bold sm:inline-block">nextbase</span>
            </div>
          </Link>
        </div>
        <ScrollArea className="h-screen overflow-y-auto">
          <DocsNavigation className="mt-5 px-1 pb-40" setIsOpen={setIsOpen} />
        </ScrollArea>
      </SheetContent>
    </Sheet>
  );
}
