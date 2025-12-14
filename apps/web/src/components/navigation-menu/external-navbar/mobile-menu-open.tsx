"use client";

import { Menu } from "lucide-react";
import { useMobileMenu } from "@/hooks/use-mobile-menu";

export function MobileMenuOpen() {
  const { toggle } = useMobileMenu();
  return (
    <Menu className="-mr-2 hover:cursor-pointer lg:hidden" onClick={toggle} />
  );
}
