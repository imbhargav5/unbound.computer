'use client';

import { useChat, type Message } from 'ai/react';

import { insertChatAction } from '@/data/user/chats';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { cn } from '@/lib/utils';
import { nanoid } from 'nanoid';
import { usePathname } from 'next/navigation';
import { toast } from 'sonner';
import { ChatList } from './chat-list';
import { ChatPanel } from './chat-panel';
import { ChatScrollAnchor } from './chat-scroll-anchor';
import { EmptyScreen } from './empty-screen';

export interface ChatProps extends React.ComponentProps<'div'> {
  initialMessages?: Message[];
  id?: string;
  project: { id: string, slug: string, name: string };
}


export function ChatContainer({ id, initialMessages, className, project }: ChatProps) {
  const { mutate } = useSAToastMutation(async ({ chatId, projectId, content }: { chatId: string, projectId: string, content: Message[] }) => {
    return await insertChatAction(projectId, content, chatId);
  }, {
    errorMessage(error) {
      try {
        if (error instanceof Error) {
          return String(error.message);
        }
        return `Failed to delete organization ${String(error)}`;
      } catch (_err) {
        console.warn(_err);
        return 'Failed to delete organization';
      }
    },
  })

  const pathname = usePathname();

  const { messages, append, reload, stop, isLoading, input, setInput } =
    useChat({
      initialMessages,
      id,
      body: {
        id,
      },
      onFinish({ content }) {
        messages.push({
          role: 'user',
          content: input,
          id: nanoid(),
        }, {
          role: 'assistant',
          content,
          id: nanoid(),
        });

        if (pathname === `/project/${project.slug}`) {
          const chatPath = `/project/${project.slug}/chats/${id}`;
          window.history.replaceState(null, '', chatPath);
        }
        mutate({ chatId: id ?? nanoid(), projectId: project.id, content: messages });
      },
      onResponse(response) {
        if (response.status === 401) {
          toast.error(response.statusText);
        }
      },
    });

  return (
    <>
      <div className={cn('pb-[200px] pt-4 md:pt-10', className)}>
        {messages.length ? (
          <>
            <ChatList messages={messages} />
            <ChatScrollAnchor trackVisibility={isLoading} />
          </>
        ) : (
          <EmptyScreen setInput={setInput} />
        )}
      </div>
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
    </>
  );
}
