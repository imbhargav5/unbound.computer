"use client";
import { DndContext, type DragEndEvent } from "@dnd-kit/core";
import { useAction } from "next-cool-action/hooks";
import { useRef } from "react";
import { toast } from "sonner";
import { T } from "@/components/ui/typography-ui";
import { adminUpdateFeedbackStatusAction } from "@/data/feedback";
import type { RoadmapData } from "../types";
import { RoadmapList } from "./roadmap-list";

const statusesKey = {
  plannedCards: "planned",
  inProgress: "in_progress",
} as const;

export function DraggableRoadmapContent({
  roadmapData,
}: {
  roadmapData: RoadmapData;
}) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const { execute } = useAction(adminUpdateFeedbackStatusAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating feedback status");
    },
    onSuccess: () => {
      toast.success("Feedback status updated", {
        id: toastRef.current,
      });
    },
    onError: () => {
      toast.error("Error updating feedback status", {
        id: toastRef.current,
      });
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  function handleDragEnd(event: DragEndEvent) {
    const { over } = event;
    if (over) {
      execute({
        feedbackId: event.active.id as string,
        status: statusesKey[over.id as keyof typeof statusesKey],
      });
    }
  }

  return (
    <DndContext onDragEnd={handleDragEnd}>
      <div className="flex-1 overflow-auto">
        {roadmapData.plannedCards.length > 0 ||
        roadmapData.inProgress.length > 0 ? (
          <>
            <div className="border-b px-4 py-3">
              <T.H4 className="mt-0 font-semibold">In Progress</T.H4>
              <RoadmapList cards={roadmapData.inProgress} isAdmin />
            </div>
            <div className="px-4 py-3">
              <T.H4 className="mt-0 font-semibold">Planned</T.H4>
              <RoadmapList cards={roadmapData.plannedCards} isAdmin />
            </div>
          </>
        ) : (
          <div className="py-4 text-center text-muted-foreground text-sm">
            No items available
          </div>
        )}
      </div>
    </DndContext>
  );
}
