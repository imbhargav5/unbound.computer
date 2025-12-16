"use server";
import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/typography-ui";
import { RoadmapList } from "./_components/roadmap-list";
import type { RoadmapData } from "./types";

export async function Roadmap({ roadmapData }: { roadmapData: RoadmapData }) {
  const allItems = [...roadmapData.inProgress, ...roadmapData.plannedCards];

  return (
    <div className="w-full gap-4 md:flex">
      <div className="flex-1">
        <div className="flex flex-col rounded-lg border bg-card">
          {allItems.length > 0 ? (
            <RoadmapList cards={allItems} />
          ) : (
            <div className="py-4 text-center text-muted-foreground text-sm">
              No items available
            </div>
          )}
        </div>
      </div>

      <div className="hidden w-[300px] space-y-4 md:block">
        <div className="space-y-3 rounded-lg border bg-card p-4">
          <T.H4 className="mt-0 font-semibold">Have a suggestion?</T.H4>
          <p className="text-muted-foreground text-sm">
            We&apos;d love to hear your ideas for improving the platform.
          </p>
          <Link
            className="font-medium text-primary text-sm underline hover:text-primary/80"
            href="/feedback"
          >
            Submit feedback →
          </Link>
        </div>

        <div className="space-y-3 rounded-lg border bg-card p-4">
          <T.H4 className="mt-0 font-semibold">Statistics</T.H4>
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">In Progress</span>
              <span className="font-medium">
                {roadmapData.inProgress.length}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Planned</span>
              <span className="font-medium">
                {roadmapData.plannedCards.length}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
