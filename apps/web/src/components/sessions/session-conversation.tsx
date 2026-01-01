"use client";

import { Loader2, Send } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { MessageList } from "./message-list";
import { SessionHeader } from "./session-header";
import type { SessionMessage } from "./types";

export interface SessionConversationProps {
  sessionId: string;
  status: "active" | "paused" | "ended";
  repositoryName: string;
  branchName: string;
  deviceName: string;
  onSendMessage?: (message: string) => void;
  onPause?: () => void;
  onResume?: () => void;
  onTerminate?: () => void;
  messages: SessionMessage[];
  isConnected: boolean;
  isTyping?: boolean;
}

export function SessionConversation({
  sessionId,
  status,
  repositoryName,
  branchName,
  deviceName,
  onSendMessage,
  onPause,
  onResume,
  onTerminate,
  messages,
  isConnected,
  isTyping = false,
}: SessionConversationProps) {
  const [input, setInput] = useState("");
  const [isSending, setIsSending] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // Auto-resize textarea
  useEffect(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.style.height = "auto";
      textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`;
    }
  }, [input]);

  const handleSend = useCallback(async () => {
    if (!input.trim() || isSending || status !== "active") return;

    setIsSending(true);
    try {
      onSendMessage?.(input.trim());
      setInput("");
    } finally {
      setIsSending(false);
    }
  }, [input, isSending, status, onSendMessage]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const canSend = status === "active" && isConnected && input.trim().length > 0;

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <SessionHeader
        branchName={branchName}
        deviceName={deviceName}
        isConnected={isConnected}
        onPause={onPause}
        onResume={onResume}
        onTerminate={onTerminate}
        repositoryName={repositoryName}
        status={status}
      />

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4">
        <MessageList messages={messages} />
        {isTyping && (
          <div className="flex items-center gap-2 py-2 text-muted-foreground text-sm">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Claude is thinking...</span>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="border-t p-4">
        <div className="flex gap-2">
          <Textarea
            className={cn(
              "min-h-[44px] resize-none",
              status !== "active" && "cursor-not-allowed opacity-50"
            )}
            disabled={status !== "active" || !isConnected}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={
              status === "active"
                ? "Type a message..."
                : status === "paused"
                  ? "Session is paused"
                  : "Session has ended"
            }
            ref={textareaRef}
            rows={1}
            value={input}
          />
          <Button
            className="shrink-0"
            disabled={!canSend || isSending}
            onClick={handleSend}
          >
            {isSending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </Button>
        </div>
        {!isConnected && status === "active" && (
          <p className="mt-2 text-destructive text-sm">
            Disconnected from relay. Reconnecting...
          </p>
        )}
      </div>
    </div>
  );
}
