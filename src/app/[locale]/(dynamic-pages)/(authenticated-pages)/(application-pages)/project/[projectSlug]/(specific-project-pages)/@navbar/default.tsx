// https://github.com/vercel/next.js/issues/58272
import { Link } from '@/components/intl-link';
import { T } from '@/components/ui/Typography';
import { getCachedProjectBySlug } from '@/rsc-data/user/projects';
import { projectSlugParamSchema } from '@/utils/zod-schemas/params';
import { Layers } from 'lucide-react';

async function Title({ title }: { title: string }) {
  return (
    <div className="flex items-center gap-2">
      <Layers className="w-4 h-4" />
      <T.P>{title}</T.P>
      <div className="flex items-center gap-2 border-neutral-300 px-2 p-0.5 border rounded-full font-normal text-neutral-600 text-xs uppercase">
        Project
      </div>
    </div>
  );
}

export default async function ProjectNavbar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getCachedProjectBySlug(projectSlug);
  return (
    <div className="flex items-center">
      <Link href={`/project/${project.id}`}>
        <span className="flex items-center space-x-2">
          <Title title={project.name} />
        </span>
      </Link>
    </div>
  );
}
