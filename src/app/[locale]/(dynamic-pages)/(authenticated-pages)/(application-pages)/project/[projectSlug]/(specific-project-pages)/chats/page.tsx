import { ChatHistory } from "@/components/chat-history";

export default async function ChatsPage({
  params,
}: {
  params: { projectSlug: string };
}) {
  const { projectSlug } = params;
  return <ChatHistory projectSlug={projectSlug} />;
}
