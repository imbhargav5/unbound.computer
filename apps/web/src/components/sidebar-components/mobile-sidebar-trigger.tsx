"use client";

import { PanelLeftIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useSidebar } from "@/components/ui/sidebar";

export function MobileSidebarTrigger() {
  const { toggleSidebar } = useSidebar();

  return (
    <Button
      className="size-8 md:hidden"
      onClick={toggleSidebar}
      size="icon"
      variant="ghost"
    >
      <PanelLeftIcon className="size-4" />
      <span className="sr-only">Toggle Sidebar</span>
    </Button>
  );
}
