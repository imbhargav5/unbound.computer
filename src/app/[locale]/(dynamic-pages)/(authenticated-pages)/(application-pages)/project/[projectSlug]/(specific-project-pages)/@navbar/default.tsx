// https://github.com/vercel/next.js/issues/58272
import { T } from '@/components/ui/Typography';
import { Skeleton } from '@/components/ui/skeleton';
import { getProjectById, getSlimProjectBySlug } from '@/data/user/projects';
import { projectSlugParamSchema } from '@/utils/zod-schemas/params';
import { Layers } from 'lucide-react';
import Link from 'next/link';


import { Suspense } from 'react';

async function Title({ projectId }: { projectId: string }) {
  const project = await getProjectById(projectId);
  return (
    <div className="flex items-center gap-2">
      <Layers className="w-4 h-4" />
      <T.P>{project.name}</T.P>
      <div className="flex items-center gap-2 border-neutral-300 px-2 p-0.5 border rounded-full font-normal text-neutral-600 text-xs uppercase">
        Project
      </div>
    </div>
  );
}

export default async function ProjectNavbar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  return (
    <div className="flex items-center">
      <Link href={`/project/${project.id}`}>
        <span className="flex items-center space-x-2">
          <Suspense fallback={<Skeleton className="w-16 h-6" />}>
            <Title projectId={project.id} />
          </Suspense>
        </span>
      </Link>
    </div>
  );
}
