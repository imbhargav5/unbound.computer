import { getSlimProjectBySlug } from '@/data/user/projects';
import { cn } from '@/utils/cn';
import { projectSlugParamSchema } from '@/utils/zod-schemas/params';
import { ArrowLeftIcon } from '@radix-ui/react-icons';
import Link from 'next/link';



export default async function ProjectSettingsNavbar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  return (
    <div className={cn('hidden lg:block', 'relative ')}>
      <Link
        className="flex gap-1.5 py-1.5 px-3 cursor-pointer items-center group rounded-md transition hover:cursor-pointer hover:bg-neutral-100 dark:hover:bg-neutral-800"
        href={`/project/${project.slug}`}
      >
        <ArrowLeftIcon className="w-4 h-4 text-neutral-500 dark:text-neutral-400 group-hover:text-neutral-700 dark:group-hover:text-neutral-300" />
        <p className="text-neutral-500 dark:text-neutral-400 group-hover:text-neutral-700 dark:group-hover:text-neutral-300 text-sm font-normal">
          Back to Project
        </p>
      </Link>
    </div>
  );
}
