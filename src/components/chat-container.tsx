"use client";

import { useChat, type Message } from "ai/react";
import { nanoid } from "nanoid";
import { usePathname } from "next/navigation";
import React, { Fragment } from "react";
import { toast } from "sonner";

import { Card, CardContent, CardFooter } from "@/components/ui/card";
import { insertChatAction } from "@/data/user/chats";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { cn } from "@/lib/utils";
import { ChatList } from "./chat-list";
import { ChatPanel } from "./chat-panel";
import { EmptyScreen } from "./empty-screen";

export interface ChatProps extends React.ComponentProps<"div"> {
  initialMessages?: Message[];
  id?: string;
  project: { id: string; slug: string; name: string };
}

export function ChatContainer({
  id,
  initialMessages,
  className,
  project,
}: ChatProps) {
  const { mutate } = useSAToastMutation(
    async ({
      chatId,
      projectId,
      content,
    }: {
      chatId: string;
      projectId: string;
      content: Message[];
    }) => {
      return await insertChatAction(projectId, content, chatId);
    },
    {
      errorMessage(error) {
        return `Failed to save chat: ${String(error)}`;
      },
    },
  );

  const pathname = usePathname();

  const { messages, append, reload, stop, isLoading, input, setInput } =
    useChat({
      initialMessages,
      id,
      body: { id },
      onFinish({ content }) {
        messages.push(
          {
            role: "user",
            content: input,
            id: nanoid(),
          },
          {
            role: "assistant",
            content,
            id: nanoid(),
          },
        );

        if (pathname === `/project/${project.slug}`) {
          const chatPath = `/project/${project.slug}/chats/${id}`;
          window.history.replaceState(null, "", chatPath);
        }
        mutate({
          chatId: id ?? nanoid(),
          projectId: project.id,
          content: messages,
        });
      },
      onResponse(response) {
        if (response.status === 401) {
          toast.error(response.statusText);
        }
      },
    });

  return (
    <Card
      className={cn(
        "flex flex-col h-[calc(100svh-240px)] md:h-[calc(100svh-200px)]",
        className,
      )}
    >
      <CardContent className="flex-grow p-4 overflow-hidden relative h-[calc(100%-250px)]">
        {messages.length ? (
          <Fragment>
            <ChatList isLoading={isLoading} messages={messages} />
          </Fragment>
        ) : (
          <EmptyScreen setInput={setInput} />
        )}
      </CardContent>
      <CardFooter className="w-full">
        <ChatPanel
          id={id}
          isLoading={isLoading}
          stop={stop}
          append={append}
          projectSlug={project.slug}
          reload={reload}
          messages={messages}
          input={input}
          setInput={setInput}
        />
      </CardFooter>
    </Card>
  );
}
