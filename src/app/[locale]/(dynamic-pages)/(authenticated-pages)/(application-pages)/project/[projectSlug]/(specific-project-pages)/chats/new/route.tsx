import { insertChat } from "@/data/user/chats";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";
import { nanoid } from "nanoid";
import { redirect } from "next/navigation";

export async function GET(
  request: Request,
  { params }: { params: { projectSlug: string } },
) {
  const { projectSlug } = params;
  const project = await getSlimProjectBySlug(projectSlug);
  const user = await serverGetLoggedInUser();
  const newChatId = nanoid();
  await insertChat({
    id: newChatId,
    projectId: project.id,
    userId: user.id,
  });
  redirect(`/project/${projectSlug}/chats/${newChatId}`);
}
