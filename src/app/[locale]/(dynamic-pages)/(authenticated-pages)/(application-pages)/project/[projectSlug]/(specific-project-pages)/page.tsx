import { ChatContainer } from "@/components/chat-container";
import { T } from "@/components/ui/Typography";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { nanoid } from "ai";
import type { Metadata } from "next";
import { Suspense } from "react";
import { CommentInput } from "./CommentInput";
import { ProjectComments } from "./ProjectComments";

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
    <div className="space-y-6">
      <div className="mb-10">
        <div
          className="border dotted-bg dark:dotted-bg-dark border-gray-400/50 dark:border-gray-600/50 rounded-xl bg-gray-200/20 dark:bg-slate-950/40 flex justify-center items-center h-full"
        >
          <div className="h-[800px] w-full relative">
            <ChatContainer id={newChatId} project={project} />
          </div>

        </div>
        <div className="space-y-4 max-w-md">
          <T.H4>Comments</T.H4>
          <div className="space-y-2 mb-10">
            <div className="space-y-4 mt-4 mb-10">
              <CommentInput projectId={project.id} />
              <Suspense>
                <ProjectComments projectId={project.id} />
              </Suspense>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
