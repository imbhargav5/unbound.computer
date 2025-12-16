import { useDroppable } from "@dnd-kit/core";
import type React from "react";
import { T } from "@/components/ui/typography-ui";

interface Props {
  id: string;
  children: React.ReactNode;
  status: string;
  itemCount: number;
}

export function Droppable({ id, children, status, itemCount }: Props) {
  const { isOver, setNodeRef } = useDroppable({
    id,
  });

  return (
    <div
      className={`px-4 py-3 transition-colors duration-200 ${
        isOver ? "bg-muted/50" : ""
      }`}
      ref={setNodeRef}
    >
      <T.H4 className="mb-4 flex items-center justify-between font-semibold">
        <span>{status}</span>
        <span className="text-muted-foreground text-sm">{itemCount} items</span>
      </T.H4>
      {children}
    </div>
  );
}
