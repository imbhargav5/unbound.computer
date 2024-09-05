import { ChatHistory } from "@/components/chat-history";
import { getSlimProjectBySlug } from "@/data/user/projects";


export default async function ChatsPage({ params }: { params: { projectSlug: string } }) {
  const { projectSlug } = params;
  const project = await getSlimProjectBySlug(projectSlug);


  return <ChatHistory projectId={project.id} />;
}

