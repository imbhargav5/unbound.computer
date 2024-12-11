// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/(application-pages)/project/[projectSlug]/(specific-project-pages)/chats/[chatId]/page.tsx
import { ChatContainer } from "@/components/chat-container";
import { getChatById } from "@/data/user/chats";
import { getSlimProjectBySlug } from "@/data/user/projects";

import { type Message } from "ai";

export default async function ChatPage(props: {
  params: Promise<{ chatId: string; projectSlug: string }>;
}) {
  const params = await props.params;
  const { chatId, projectSlug } = params;
  const project = await getSlimProjectBySlug(projectSlug);

  const chat = await getChatById(chatId);

  if (chat.payload !== null && typeof chat.payload === "string") {
    const { messages } = JSON.parse(chat.payload);
    const assertedMessages = messages as unknown as Message[];
    return (
      <div className="relative">
        <ChatContainer
          id={chatId}
          initialMessages={assertedMessages}
          project={project}
        />
      </div>
    );
  }

  return <ChatContainer id={chatId} project={project} />;
}
