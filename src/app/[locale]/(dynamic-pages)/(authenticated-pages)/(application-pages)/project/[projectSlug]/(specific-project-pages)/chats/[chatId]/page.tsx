import { ChatContainer } from "@/components/chat-container";
import { getChatById } from "@/data/user/chats";
import { getSlimProjectBySlug } from "@/data/user/projects";

import { nanoid, type Message } from "ai";



export default async function ChatPage({ params }: { params: { chatId: string; projectSlug: string } }) {
  const { chatId, projectSlug } = params;
  const project = await getSlimProjectBySlug(projectSlug);

  if (!chatId) {
    const newChatId = nanoid();
    return <ChatContainer id={newChatId} project={project} />;
  }

  const chat = await getChatById(chatId);

  if (chat.payload !== null && typeof chat.payload === "string") {
    const { messages } = JSON.parse(chat.payload);
    const assertedMessages = messages as unknown as Message[];
    return (
      <div className="relative h-[calc(100vh-150px)]">
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
