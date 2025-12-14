"use client";

import { ChevronDown } from "lucide-react";
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/utils/cn";

interface CollapsibleCardProps {
  title: string;
  icon: React.ReactNode;
  children: React.ReactNode;
  defaultOpen?: boolean;
}

export function CollapsibleCard({
  title,
  icon,
  children,
  defaultOpen = false,
}: CollapsibleCardProps) {
  const [isOpen, setIsOpen] = useState(defaultOpen);

  return (
    <Card>
      <CardHeader
        className="cursor-pointer select-none"
        onClick={() => setIsOpen(!isOpen)}
      >
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center gap-1 text-sm">
            {icon}
            {title}
          </CardTitle>
          <ChevronDown
            className={cn("h-4 w-4 transition-transform", {
              "rotate-180 transform": isOpen,
            })}
          />
        </div>
      </CardHeader>
      {isOpen && <CardContent className="space-y-2">{children}</CardContent>}
    </Card>
  );
}
