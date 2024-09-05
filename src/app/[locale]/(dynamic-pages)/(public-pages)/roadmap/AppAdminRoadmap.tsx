'use client';
import type { roadmapDataType } from '@/data/admin/internal-roadmap';
import { adminUpdateFeedbackStatusAction } from '@/data/feedback';
import { DndContext, type DragEndEvent } from '@dnd-kit/core';
import Link from 'next/link';
import { Droppable } from './_components/Droppable';
import { RoadmapList } from './_components/RoadmapList';

export enum Statuses {
  plannedCards = 'Planned',
  inProgress = 'In Progress',
  completedCards = 'Completed',
}

enum statusesKey {
  plannedCards = 'planned',
  inProgress = 'in_progress',
  completedCards = 'completed',
}

export function AppAdminRoadmap({
  roadmapData,
}: {
  roadmapData: {
    plannedCards: roadmapDataType[];
    inProgress: roadmapDataType[];
    completedCards: roadmapDataType[];
  };
}) {
  async function handleDragEnd(event: DragEndEvent) {
    const { over } = event;

    if (over) {
      await adminUpdateFeedbackStatusAction({
        feedbackId: event.active.id as string,
        status: statusesKey[over.id],
      });
    }
  }

  return (
    <div className="space-y-10">
      <div>
        If you want to add items to the roadmap, add them{' '}
        <Link href="/feedback" className='text-primary underline font-bold'>here.</Link>
      </div>
      <div className="grid grid-cols-3 gap-10">
        <DndContext onDragEnd={handleDragEnd}>

          {Object.keys(roadmapData).map((cardListName) => (
            <Droppable
              key={cardListName}
              id={cardListName}
              status={Statuses[cardListName]}
            >
              {roadmapData[cardListName].length > 0 ? (
                <RoadmapList isAdmin cards={roadmapData[cardListName]} />
              ) : (
                <div>Nothing in {Statuses[cardListName]}</div>
              )}
            </Droppable>
          ))}
        </DndContext>
      </div>



    </div>
  );
}
