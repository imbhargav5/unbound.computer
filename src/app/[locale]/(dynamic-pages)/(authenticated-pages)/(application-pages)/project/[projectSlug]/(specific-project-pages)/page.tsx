import { Typography } from "@/components/ui/Typography";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { cn } from "@/lib/utils";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { nanoid } from "nanoid";
import type { Metadata } from "next";

type ProjectPageProps = {
  params: {
    projectSlug: string;
  };
};

export async function generateMetadata({
  params,
}: ProjectPageProps): Promise<Metadata> {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);

  return {
    title: `Project | ${project.name}`,
    description: `View and manage your project ${project.name}`,
  };
}

export default async function ProjectPage({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);

  const newChatId = nanoid();
  return (
    <div className={cn("space-y-6")}>
      <div className={cn("mb-10", "flex flex-col lg:flex-row lg:space-x-6")}>
        <div
          className={cn(
            "border dotted-bg dark:dotted-bg-dark border-gray-400/50 dark:border-gray-600/50 rounded bg-gray-200/20 dark:bg-slate-950/40",
            "flex flex-col justify-center items-center",
            "w-full lg:w-2/3 mb-6 lg:mb-0",
            "px-6 py-12 min-h-[240px]", // Increased padding and minimum height
            "text-center", // Ensure text is centered
          )}
        >
          <Typography.H3 className="mb-4 mt-0">
            Build Your Business Logic here
          </Typography.H3>
          <Typography.Subtle className="max-w-md">
            For eg: if you are building a marketplace, you can create entities
            like Product, Category, Order etc. If you are building a blog, you
            can create entities like Post, Comment, Tag etc.
          </Typography.Subtle>

          {/* <ChatContainer id={newChatId} project={project} /> */}
        </div>
      </div>
    </div>
  );
}
