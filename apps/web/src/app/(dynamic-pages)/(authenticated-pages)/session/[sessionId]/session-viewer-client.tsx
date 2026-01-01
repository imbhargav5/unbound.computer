"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { SessionConversation } from "@/components/sessions";
import type { SessionMessage, ToolUse } from "@/components/sessions/types";
import { useToast } from "@/components/ui/use-toast";
import { useRelayConnection } from "@/hooks/use-relay-connection";

interface SessionViewerClientProps {
  sessionId: string;
  viewerId: string;
  viewerToken: string;
  relayUrl: string;
  repositoryName: string;
  branchName: string;
  deviceName: string;
  status: "active" | "paused" | "ended";
}

export function SessionViewerClient({
  sessionId,
  viewerId,
  viewerToken,
  relayUrl,
  repositoryName,
  branchName,
  deviceName,
  status: initialStatus,
}: SessionViewerClientProps) {
  const { toast } = useToast();
  const [status, setStatus] = useState<"active" | "paused" | "ended">(
    initialStatus
  );
  const [messages, setMessages] = useState<SessionMessage[]>([]);
  const [pendingToolUses, setPendingToolUses] = useState<Map<string, ToolUse>>(
    new Map()
  );

  const {
    connectionState,
    isConnected,
    error,
    streamChunks,
    currentContent,
    isTyping,
    sendInput,
    pause,
    resume,
    stop,
  } = useRelayConnection({
    relayUrl,
    sessionId,
    viewerId,
    authToken: viewerToken,
    permission: "interact", // Default to interact - allow input
    enabled: status !== "ended",
  });

  // Handle connection errors
  useEffect(() => {
    if (error) {
      toast({
        title: "Connection Error",
        description: error.message,
        variant: "destructive",
      });
    }
  }, [error, toast]);

  // Process stream chunks into messages
  useEffect(() => {
    let currentAssistantMessage: SessionMessage | null = null;
    const newMessages: SessionMessage[] = [];

    for (const chunk of streamChunks) {
      switch (chunk.contentType) {
        case "text": {
          // Accumulate text chunks into assistant message
          if (
            !currentAssistantMessage ||
            currentAssistantMessage.role !== "assistant"
          ) {
            currentAssistantMessage = {
              id: `msg-${chunk.sessionId}-${chunk.sequenceNumber}`,
              role: "assistant",
              content: chunk.content,
              timestamp: new Date(chunk.timestamp).toISOString(),
            };
            newMessages.push(currentAssistantMessage);
          } else {
            currentAssistantMessage.content =
              (currentAssistantMessage.content ?? "") + chunk.content;
          }
          break;
        }

        case "tool_use": {
          // Parse tool use from chunk content
          try {
            const toolData = JSON.parse(chunk.content);
            const toolUse: ToolUse = {
              id: toolData.id ?? `tool-${chunk.sequenceNumber}`,
              name: toolData.name ?? "unknown",
              input: toolData.input,
              status: chunk.isComplete ? "completed" : "running",
              duration: toolData.duration,
            };

            // Add to pending tool uses
            setPendingToolUses((prev) => {
              const next = new Map(prev);
              next.set(toolUse.id, toolUse);
              return next;
            });

            // Add tool use to current message
            if (
              currentAssistantMessage &&
              currentAssistantMessage.role === "assistant"
            ) {
              currentAssistantMessage.toolUses = [
                ...(currentAssistantMessage.toolUses ?? []),
                toolUse,
              ];
            }
          } catch {
            // Invalid JSON
          }
          break;
        }

        case "tool_result": {
          // Update pending tool use with result
          try {
            const resultData = JSON.parse(chunk.content);
            const toolId = resultData.toolId ?? resultData.id;

            setPendingToolUses((prev) => {
              const next = new Map(prev);
              const existing = next.get(toolId);
              if (existing) {
                next.set(toolId, {
                  ...existing,
                  output: resultData.output ?? resultData.result,
                  status: "completed",
                });
              }
              return next;
            });
          } catch {
            // Invalid JSON
          }
          break;
        }

        case "system": {
          // System messages might indicate session state changes
          if (chunk.content.includes("paused")) {
            setStatus("paused");
          } else if (chunk.content.includes("resumed")) {
            setStatus("active");
          } else if (chunk.content.includes("ended")) {
            setStatus("ended");
          }
          break;
        }

        case "error": {
          toast({
            title: "Session Error",
            description: chunk.content,
            variant: "destructive",
          });
          break;
        }
      }
    }

    if (newMessages.length > 0) {
      setMessages((prev) => [...prev, ...newMessages]);
    }
  }, [streamChunks, toast]);

  // Update messages with completed tool uses
  const messagesWithTools = useMemo(
    () =>
      messages.map((msg) => {
        if (msg.toolUses) {
          return {
            ...msg,
            toolUses: msg.toolUses.map(
              (tu) => pendingToolUses.get(tu.id) ?? tu
            ),
          };
        }
        return msg;
      }),
    [messages, pendingToolUses]
  );

  // Handle sending a message
  const handleSendMessage = useCallback(
    (content: string) => {
      if (!sendInput(content)) {
        toast({
          title: "Failed to send",
          description: "Could not send message. Check your connection.",
          variant: "destructive",
        });
        return;
      }

      // Add user message to local state
      const userMessage: SessionMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content,
        timestamp: new Date().toISOString(),
      };
      setMessages((prev) => [...prev, userMessage]);
    },
    [sendInput, toast]
  );

  // Handle pause
  const handlePause = useCallback(() => {
    if (pause()) {
      setStatus("paused");
    } else {
      toast({
        title: "Failed to pause",
        description: "Could not pause session.",
        variant: "destructive",
      });
    }
  }, [pause, toast]);

  // Handle resume
  const handleResume = useCallback(() => {
    if (resume()) {
      setStatus("active");
    } else {
      toast({
        title: "Failed to resume",
        description: "Could not resume session.",
        variant: "destructive",
      });
    }
  }, [resume, toast]);

  // Handle terminate
  const handleTerminate = useCallback(() => {
    if (stop()) {
      setStatus("ended");
    } else {
      toast({
        title: "Failed to terminate",
        description: "Could not terminate session.",
        variant: "destructive",
      });
    }
  }, [stop, toast]);

  return (
    <SessionConversation
      branchName={branchName}
      deviceName={deviceName}
      isConnected={isConnected}
      isTyping={isTyping}
      messages={messagesWithTools}
      onPause={handlePause}
      onResume={handleResume}
      onSendMessage={handleSendMessage}
      onTerminate={handleTerminate}
      repositoryName={repositoryName}
      sessionId={sessionId}
      status={status}
    />
  );
}
