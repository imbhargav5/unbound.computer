"use client";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { MOBILE_MEDIA_QUERY_MATCHER } from "@/constants";
import { SidebarVisibilityContext } from "@/contexts/SidebarVisibilityContext";
import useMatchMedia from "@/hooks/useMatchMedia";
import { useContext } from "react";
import "./mobilesidebar.css";

export function MobileSidebarShell({
  children,
}: {
  children: React.ReactNode;
}) {
  const { isVisible, setVisibility } = useContext(SidebarVisibilityContext);
  const isMobile = useMatchMedia(MOBILE_MEDIA_QUERY_MATCHER);
  if (!isMobile) {
    return null;
  }
  return (
    <Sheet open={isVisible} onOpenChange={setVisibility}>
      <SheetContent side="left" className="mobile-sidebar w-[264px]">
        {children}
      </SheetContent>
    </Sheet>
  );
}
