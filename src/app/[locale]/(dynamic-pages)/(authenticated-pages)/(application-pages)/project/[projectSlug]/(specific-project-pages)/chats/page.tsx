import { ChatHistory } from "@/components/chat-history";

export default async function ChatsPage(props: {
  params: Promise<{ projectSlug: string }>;
}) {
  const params = await props.params;
  const { projectSlug } = params;
  return <ChatHistory projectSlug={projectSlug} />;
}
