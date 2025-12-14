import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/typography-ui";
import { RoadmapList } from "./_components/roadmap-list";
import type { RoadmapData } from "./types";

export function AppAdminRoadmap({ roadmapData }: { roadmapData: RoadmapData }) {
  const concatRoadmap = [
    ...roadmapData.plannedCards,
    ...roadmapData.inProgress,
  ];
  return (
    <div className="space-y-6">
      <div className="w-full gap-4 md:flex">
        <div className="flex-1">
          <div className="flex flex-col rounded-lg border bg-card">
            <div className="flex-1 overflow-auto">
              {roadmapData.plannedCards.length > 0 ||
              roadmapData.inProgress.length > 0 ? (
                <>
                  <RoadmapList cards={concatRoadmap} />
                </>
              ) : (
                <div className="py-4 text-center text-muted-foreground text-sm">
                  No items available
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="hidden w-[300px] space-y-4 md:block">
          <div className="space-y-3 rounded-lg border bg-card p-4">
            <T.H4 className="mt-0 font-semibold">Admin Actions</T.H4>
            <p className="text-muted-foreground text-sm">
              Add new items to the roadmap through the feedback system.
            </p>
            <Link
              className="font-medium text-primary text-sm underline hover:text-primary/80"
              href="/feedback"
            >
              Manage feedback →
            </Link>
          </div>

          <div className="space-y-3 rounded-lg border bg-card p-4">
            <T.H4 className="mt-0 font-semibold">Statistics</T.H4>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Planned</span>
                <span className="font-medium">
                  {roadmapData.plannedCards.length}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">In Progress</span>
                <span className="font-medium">
                  {roadmapData.inProgress.length}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Completed</span>
                <span className="font-medium">
                  {roadmapData.completedCards.length}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
