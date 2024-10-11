"use client";
import { SidebarVisibilityContext } from "@/contexts/SidebarVisibilityContext";
import dynamic from "next/dynamic";
import { useContext } from "react";
const MobileSidebarShell = dynamic(
  () => import("./MobileSidebarShell").then((m) => m.MobileSidebarShell),
  { ssr: false },
);
function DesktopShell({ children }: { children: React.ReactNode }) {
  const { isVisible } = useContext(SidebarVisibilityContext);
  if (!isVisible) {
    return null;
  }
  return (
    <>
      <div className="hidden lg:block h-full w-[264px] border-r dark:border-gray-700/50 select-none">
        {isVisible ? children : null}
      </div>
    </>
  );
}

export function SidebarShell({ children }: { children: React.ReactNode }) {
  return (
    <>
      <DesktopShell>{children}</DesktopShell>
      <MobileSidebarShell>{children}</MobileSidebarShell>
    </>
  );
}
