
import { Link } from '@/components/intl-link';

import { buttonVariants } from "@/components/ui/button";

import { cn } from "@/lib/utils";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";
import { PlusIcon } from "@radix-ui/react-icons";

import { getChats, getChatsHistory } from "@/data/user/chats";
import { getSlimProjectById } from "@/data/user/projects";
import type { Message } from "ai";
import { formatRelative, subDays } from "date-fns";
import { HomeIcon } from "lucide-react";

async function ChatList({ userId }: { userId: string }) {
  const chats = await getChats(userId);
  return (
    <div className="flex flex-col flex-1 px-4 space-y-4 overflow-auto">
      {chats.map((chat) => {
        const { payload } = chat;
        const messages =
          typeof payload === "object" &&
            payload !== null &&
            "messages" in payload
            ? payload.messages
            : [];
        const assertedMessages = messages as unknown as Message[];
        const title =
          assertedMessages.length > 0
            ? assertedMessages[0].content
            : "No title";

        return (
          <Link
            key={chat.id}
            href={`/chats/${chat.id}`}
            className={cn(
              buttonVariants({ variant: "outline" }),
              "h-10 truncate text-ellipsis overflow-hidden block w-full justify-start bg-zinc-50 px-4 shadow-none transition-colors hover:bg-zinc-200/40 dark:bg-zinc-900 dark:hover:bg-zinc-300/10",
            )}
          >
            {title}
          </Link>
        );
      })}
    </div>
  );
}

export async function ChatHistory({ projectId }: { projectId: string }) {
  const user = await serverGetLoggedInUser();
  const project = await getSlimProjectById(projectId)
  const userId = user.id;
  const chatsHistory = await getChatsHistory(projectId, userId)
  return (
    <div className="flex flex-col h-full">
      <div className="px-2 my-4">
        <Link
          href="/dashboard"
          className={cn(
            buttonVariants({ variant: "outline" }),
            "h-10 w-full justify-start bg-zinc-50 px-4 shadow-none transition-colors hover:bg-zinc-200/40 dark:bg-zinc-900 dark:hover:bg-zinc-300/10",
          )}
        >
          <HomeIcon className="-translate-x-2 stroke-2" />
          Home
        </Link>
      </div>
      <div className="px-2 my-4">
        <Link
          href={`/project/${project.slug}`}
          className={cn(
            buttonVariants({ variant: "outline" }),
            "h-10 w-full justify-start bg-zinc-50 px-4 shadow-none transition-colors hover:bg-zinc-200/40 dark:bg-zinc-900 dark:hover:bg-zinc-300/10",
          )}
        >
          <PlusIcon className="-translate-x-2 stroke-2" />
          New Chat
        </Link>
      </div>

      <div className="flex flex-col gap-2">
        {chatsHistory.map((chat, i) => (
          <Link
            key={chat.id}
            href={`/project/${project.slug}/chats/${chat.id}`}
            className="p-2 w-1/3 bg-background rounded-lg hover:bg-backgrou/60"
          >
            Chat {chat.id} - {formatRelative(subDays(new Date(), 3), new Date(chat.created_at))}
          </Link>
        ))}
      </div>

    </div>
  );
}
