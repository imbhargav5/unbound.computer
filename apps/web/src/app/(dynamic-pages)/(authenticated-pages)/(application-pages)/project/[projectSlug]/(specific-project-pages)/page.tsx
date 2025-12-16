import type { Metadata } from "next";
import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { cn } from "@/lib/utils";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";

type ProjectPageProps = {
  params: Promise<{
    projectSlug: string;
  }>;
};

export async function generateMetadata(
  props: ProjectPageProps
): Promise<Metadata> {
  const params = await props.params;
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);

  return {
    title: `Project | ${project.name}`,
    description: `View and manage your project ${project.name}`,
  };
}

async function ProjectPageContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  return (
    <div className="space-y-6">
      <div className={cn("mb-10", "flex flex-col lg:flex-row lg:space-x-6")}>
        <div
          className={cn(
            "dotted-bg dark:dotted-bg-dark rounded border border-gray-400/50 bg-gray-200/20 dark:border-gray-600/50 dark:bg-slate-950/40",
            "flex flex-col items-center justify-center",
            "mb-6 w-full lg:mb-0 lg:w-2/3",
            "min-h-[240px] px-6 py-12", // Increased padding and minimum height
            "text-center" // Ensure text is centered
          )}
        >
          <Typography.H3 className="mt-0 mb-4">
            Build Your Business Logic here
          </Typography.H3>
          <Typography.Subtle className="max-w-md">
            For eg: if you are building a marketplace, you can create entities
            like Product, Category, Order etc. If you are building a blog, you
            can create entities like Post, Comment, Tag etc.
          </Typography.Subtle>
        </div>
      </div>
    </div>
  );
}

export default async function ProjectPage(props: { params: Promise<unknown> }) {
  return (
    <Suspense>
      <ProjectPageContent params={props.params} />
    </Suspense>
  );
}
