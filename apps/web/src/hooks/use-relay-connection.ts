"use client";

import type { RemoteControlAck, StreamChunk } from "@unbound/protocol";
import { useCallback, useEffect, useRef, useState } from "react";
import type {
  ConnectionState,
  MemberJoinedData,
  MemberLeftData,
  RelayError,
  SessionParticipant,
} from "@/lib/relay";
import { createWebRelayClient, type WebRelayClient } from "@/lib/relay";

/**
 * Options for useRelayConnection hook
 */
export interface UseRelayConnectionOptions {
  relayUrl: string;
  sessionId: string;
  viewerId: string;
  authToken: string;
  permission?: "view_only" | "interact" | "full_control";
  enabled?: boolean;
}

/**
 * State returned by useRelayConnection
 */
export interface UseRelayConnectionState {
  connectionState: ConnectionState;
  isConnected: boolean;
  error: RelayError | null;
  participants: SessionParticipant[];
  streamChunks: StreamChunk[];
  currentContent: string;
  isTyping: boolean;
}

/**
 * Actions returned by useRelayConnection
 */
export interface UseRelayConnectionActions {
  connect: () => void;
  disconnect: () => void;
  sendInput: (content: string) => boolean;
  pause: () => boolean;
  resume: () => boolean;
  stop: () => boolean;
  clearContent: () => void;
}

/**
 * Combined return type
 */
export type UseRelayConnectionReturn = UseRelayConnectionState &
  UseRelayConnectionActions;

/**
 * React hook for managing a WebSocket relay connection for session viewing
 */
export function useRelayConnection(
  options: UseRelayConnectionOptions
): UseRelayConnectionReturn {
  const {
    relayUrl,
    sessionId,
    viewerId,
    authToken,
    permission,
    enabled = true,
  } = options;

  const clientRef = useRef<WebRelayClient | null>(null);

  // Connection state
  const [connectionState, setConnectionState] =
    useState<ConnectionState>("disconnected");
  const [error, setError] = useState<RelayError | null>(null);
  const [participants, setParticipants] = useState<SessionParticipant[]>([]);

  // Stream state
  const [streamChunks, setStreamChunks] = useState<StreamChunk[]>([]);
  const [currentContent, setCurrentContent] = useState("");
  const [isTyping, setIsTyping] = useState(false);

  // Track last complete sequence for content assembly
  const lastCompleteSeq = useRef(-1);

  // Handle connection state changes
  const handleConnectionStateChange = useCallback((state: ConnectionState) => {
    setConnectionState(state);
    if (state === "error") {
      setIsTyping(false);
    }
  }, []);

  // Handle stream chunks
  const handleStreamChunk = useCallback((chunk: StreamChunk) => {
    setStreamChunks((prev) => [...prev, chunk]);

    // Update typing indicator
    if (chunk.isComplete) {
      setIsTyping(false);
    } else {
      setIsTyping(true);
    }

    // Assemble content from text chunks
    if (
      chunk.contentType === "text" &&
      chunk.sequenceNumber > lastCompleteSeq.current
    ) {
      setCurrentContent((prev) => prev + chunk.content);

      if (chunk.isComplete) {
        lastCompleteSeq.current = chunk.sequenceNumber;
      }
    }
  }, []);

  // Handle remote control acknowledgments
  const handleRemoteControlAck = useCallback((ack: RemoteControlAck) => {
    if (!ack.success && ack.error) {
      setError({
        code: "REMOTE_CONTROL_FAILED",
        message: ack.error,
        recoverable: true,
      });
    }
  }, []);

  // Handle member joined
  const handleMemberJoined = useCallback((data: MemberJoinedData) => {
    setParticipants((prev) => {
      const exists = prev.some((p) => p.deviceId === data.deviceId);
      if (exists) return prev;
      return [
        ...prev,
        {
          deviceId: data.deviceId,
          deviceName: data.deviceName,
          role: data.role,
          permission: data.permission,
        },
      ];
    });
  }, []);

  // Handle member left
  const handleMemberLeft = useCallback((data: MemberLeftData) => {
    setParticipants((prev) => prev.filter((p) => p.deviceId !== data.deviceId));
  }, []);

  // Handle session ended
  const handleSessionEnded = useCallback(() => {
    setIsTyping(false);
  }, []);

  // Handle errors
  const handleError = useCallback((err: RelayError) => {
    setError(err);
  }, []);

  // Create and connect client
  const connect = useCallback(() => {
    if (clientRef.current) {
      clientRef.current.disconnect();
    }

    const client = createWebRelayClient({
      relayUrl,
      sessionId,
      viewerId,
      authToken,
      permission,
      onConnectionStateChange: handleConnectionStateChange,
      onStreamChunk: handleStreamChunk,
      onRemoteControlAck: handleRemoteControlAck,
      onMemberJoined: handleMemberJoined,
      onMemberLeft: handleMemberLeft,
      onSessionEnded: handleSessionEnded,
      onError: handleError,
    });

    clientRef.current = client;
    client.connect();
  }, [
    relayUrl,
    sessionId,
    viewerId,
    authToken,
    permission,
    handleConnectionStateChange,
    handleStreamChunk,
    handleRemoteControlAck,
    handleMemberJoined,
    handleMemberLeft,
    handleSessionEnded,
    handleError,
  ]);

  // Disconnect client
  const disconnect = useCallback(() => {
    if (clientRef.current) {
      clientRef.current.disconnect();
      clientRef.current = null;
    }
  }, []);

  // Send input
  const sendInput = useCallback((content: string): boolean => {
    if (!clientRef.current) return false;
    return clientRef.current.sendInput(content);
  }, []);

  // Pause session
  const pause = useCallback((): boolean => {
    if (!clientRef.current) return false;
    return clientRef.current.sendRemoteControl("PAUSE");
  }, []);

  // Resume session
  const resume = useCallback((): boolean => {
    if (!clientRef.current) return false;
    return clientRef.current.sendRemoteControl("RESUME");
  }, []);

  // Stop session
  const stop = useCallback((): boolean => {
    if (!clientRef.current) return false;
    return clientRef.current.sendRemoteControl("STOP");
  }, []);

  // Clear accumulated content
  const clearContent = useCallback(() => {
    setStreamChunks([]);
    setCurrentContent("");
    lastCompleteSeq.current = -1;
  }, []);

  // Connect on mount if enabled
  useEffect(() => {
    if (enabled && sessionId && authToken) {
      connect();
    }

    return () => {
      disconnect();
    };
  }, [enabled, sessionId, authToken, connect, disconnect]);

  return {
    // State
    connectionState,
    isConnected: connectionState === "authenticated",
    error,
    participants,
    streamChunks,
    currentContent,
    isTyping,
    // Actions
    connect,
    disconnect,
    sendInput,
    pause,
    resume,
    stop,
    clearContent,
  };
}
