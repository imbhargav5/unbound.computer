"use client";

import { formatDistanceToNow } from "date-fns";
import { Bot, User } from "lucide-react";
import { cn } from "@/lib/utils";
import { CodeBlock } from "./code-block";
import { ToolUseBlock } from "./tool-use-block";
import type { SessionMessage } from "./types";

interface MessageListProps {
  messages: SessionMessage[];
}

export function MessageList({ messages }: MessageListProps) {
  if (messages.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-muted-foreground">
        <p>No messages yet. Send a message to start the conversation.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {messages.map((message) => (
        <MessageItem key={message.id} message={message} />
      ))}
    </div>
  );
}

function MessageItem({ message }: { message: SessionMessage }) {
  const isUser = message.role === "user";

  return (
    <div className={cn("flex gap-3", isUser ? "flex-row-reverse" : "flex-row")}>
      <div
        className={cn(
          "flex h-8 w-8 shrink-0 items-center justify-center rounded-full",
          isUser ? "bg-primary text-primary-foreground" : "bg-muted"
        )}
      >
        {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
      </div>

      <div
        className={cn(
          "max-w-[80%] space-y-2",
          isUser ? "items-end" : "items-start"
        )}
      >
        {/* Text content */}
        {message.content && (
          <div
            className={cn(
              "rounded-lg px-4 py-2",
              isUser ? "bg-primary text-primary-foreground" : "bg-muted"
            )}
          >
            <MessageContent content={message.content} />
          </div>
        )}

        {/* Tool uses */}
        {message.toolUses?.map((toolUse) => (
          <ToolUseBlock key={toolUse.id} toolUse={toolUse} />
        ))}

        {/* Timestamp */}
        <div className="text-muted-foreground text-xs">
          {formatDistanceToNow(new Date(message.timestamp), {
            addSuffix: true,
          })}
        </div>
      </div>
    </div>
  );
}

function MessageContent({ content }: { content: string }) {
  // Simple markdown-like rendering for code blocks
  const parts = content.split(/(```[\s\S]*?```)/g);

  return (
    <div className="space-y-2">
      {parts.map((part, index) => {
        if (part.startsWith("```")) {
          const match = part.match(/```(\w+)?\n?([\s\S]*?)```/);
          if (match) {
            const [, language, code] = match;
            return (
              <CodeBlock
                code={code.trim()}
                key={index}
                language={language ?? "text"}
              />
            );
          }
        }
        return part.trim() ? (
          <p className="whitespace-pre-wrap" key={index}>
            {part}
          </p>
        ) : null;
      })}
    </div>
  );
}
