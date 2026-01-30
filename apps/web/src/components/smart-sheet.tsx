"use client";

import { VisuallyHidden } from "@radix-ui/react-visually-hidden";
import type { ReactNode } from "react";
import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import useMatchMedia from "@/hooks/use-match-media";
import { cn } from "@/lib/utils";

type SheetProps = React.ComponentPropsWithoutRef<typeof Sheet>;

interface SmartSheetProps extends SheetProps {
  children: ReactNode;
  className?: string;
}

export function SmartSheet({ children, className, ...props }: SmartSheetProps) {
  const isMobile = useMatchMedia("(max-width: 768px)");
  const sheetDirection = isMobile ? "bottom" : "right";

  return (
    <Sheet {...props}>
      <SheetContent
        className={cn(
          isMobile ? "max-h-100svh" : "",
          isMobile
            ? ""
            : "w-[400px] max-w-none! sm:w-[540px] md:w-[640px] lg:w-[800px] xl:w-[1000px]",
          "bg-muted",
          className
        )}
        side={sheetDirection}
      >
        <VisuallyHidden>
          <SheetTitle />
        </VisuallyHidden>
        <div
          className={cn(
            isMobile ? "overflow-y-auto pb-20" : "",
            isMobile ? "" : "max-h-full overflow-y-auto pb-20"
          )}
          style={{
            maxHeight: isMobile ? "calc(100svh - 100px)" : undefined,
          }}
        >
          {children}
        </div>
      </SheetContent>
    </Sheet>
  );
}
