'use client';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import type { roadmapDataType } from '@/data/admin/internal-roadmap';
import { RoadmapList } from './_components/RoadmapList';

export enum Statuses {
  plannedCards = 'Planned',
  inProgress = 'In Progress',
  completedCards = 'Completed',
}

export function Roadmap({
  roadmapData,
}: {
  roadmapData: {
    plannedCards: roadmapDataType[];
    inProgress: roadmapDataType[];
    completedCards: roadmapDataType[];
  };
}) {
  return (
    <div className="space-y-10">
      <div className="grid grid-cols-3 gap-10">
        {Object.keys(roadmapData).map((cardListName) => (
          <Card>
            <div key={cardListName} className="drop-area">
              <CardHeader>
                <CardTitle>{Statuses[cardListName]}</CardTitle>
                <CardDescription>
                  These are {Statuses[cardListName]}
                </CardDescription>
              </CardHeader>
              <CardContent>
                <RoadmapList cards={roadmapData[cardListName]} />
              </CardContent>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}
