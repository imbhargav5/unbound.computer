'use client';

import InternalRoadmapCard from '@/components/InternalRoadmapCard';
import type { roadmapDataType } from '@/data/admin/internal-roadmap';
import { Draggable } from './Draggable';

export const RoadmapList = async ({
  cards,
  isAdmin,
}: {
  cards: roadmapDataType[];
  isAdmin?: boolean;
}) => {
  return (
    <div className="space-y-4">
      {cards?.map((feedback) => (
        <Draggable key={feedback.id} id={feedback.id}>
          <InternalRoadmapCard
            isAdmin={isAdmin}
            key={feedback.id}
            date={feedback.date}
            title={feedback.title}
            description={feedback.description}
            tag={feedback.tag}
            priority={feedback.priority}
            feedbackItemId={feedback.id}
          />
        </Draggable>
      ))}
    </div>
  );
};
