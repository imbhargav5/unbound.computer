import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

type Props = {
  quantity: number;
};

const ProjectsLoadingFallback = ({ quantity }: Props) => (
  <div className="mt-6 flex w-full gap-4 overflow-x-auto p-4">
    {[...Array(quantity)].map((_, i) => (
      <Card
        className="flex min-h-32 w-72 flex-col items-start rounded-lg bg-card p-4 shadow-sm"
        key={`${i}skeleton`}
      >
        <Skeleton className="mb-2 h-6 w-24" />
        <Skeleton className="mb-1 h-6 w-36" />
        <Skeleton className="h-4 w-16" />
      </Card>
    ))}
  </div>
);

export { ProjectsLoadingFallback };
