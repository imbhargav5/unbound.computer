import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { useDroppable } from '@dnd-kit/core';

import type React from 'react';

type Props = {
  id: string;
  children: React.ReactNode;
  status: string;
  className?: string;
};

export function Droppable({ id, children, status }: Props) {
  const { isOver, setNodeRef } = useDroppable({
    id,
  });

  return (
    <div ref={setNodeRef}>
      <Card
        data-isOver={isOver}
        key={status ?? 'default-key'}
        className="data-[isOver=true]:border-foreground transition-all duration-300 ease-in-out"
      >
        <CardHeader>
          <CardTitle>{status}</CardTitle>
          <CardDescription>These are {status}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">{children}</div>
        </CardContent>
      </Card>
    </div>
  );
}
