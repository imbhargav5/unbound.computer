import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import type { MessageType, SessionMessage } from "./types.js";

/**
 * Message queue events interface
 */
export interface QueueEvents {
  enqueue: [message: SessionMessage];
  dequeue: [message: SessionMessage];
  acknowledge: [messageId: string];
  retry: [message: SessionMessage];
  drop: [message: SessionMessage, reason: string];
}

/**
 * Message queue configuration
 */
export interface QueueConfig {
  /** Maximum queue size */
  maxSize: number;
  /** Maximum retry attempts */
  maxRetries: number;
  /** Retry delay in milliseconds */
  retryDelayMs: number;
  /** Message TTL in milliseconds */
  messageTtlMs: number;
}

/**
 * Default queue configuration
 */
const DEFAULT_QUEUE_CONFIG: QueueConfig = {
  maxSize: 1000,
  maxRetries: 3,
  retryDelayMs: 1000,
  messageTtlMs: 5 * 60 * 1000, // 5 minutes
};

/**
 * Message queue for session communication
 * Provides ordering guarantees, acknowledgments, and retry logic
 */
export class MessageQueue extends EventEmitter {
  private sessionId: string;
  private config: QueueConfig;
  private messages: Map<string, SessionMessage> = new Map();
  private pendingAcks: Set<string> = new Set();
  private sequence = 0;
  private retryTimers: Map<string, NodeJS.Timeout> = new Map();

  constructor(sessionId: string, config: Partial<QueueConfig> = {}) {
    super();
    this.sessionId = sessionId;
    this.config = { ...DEFAULT_QUEUE_CONFIG, ...config };
  }

  /**
   * Enqueue a new message
   */
  enqueue(type: MessageType, content: string): SessionMessage {
    if (this.messages.size >= this.config.maxSize) {
      // Remove oldest acknowledged message
      const oldest = this.getOldestAcknowledged();
      if (oldest) {
        this.messages.delete(oldest.id);
      } else {
        throw new Error("Message queue is full");
      }
    }

    const message: SessionMessage = {
      id: randomUUID(),
      sessionId: this.sessionId,
      type,
      content,
      timestamp: new Date(),
      sequence: this.sequence++,
      acknowledged: false,
      retryCount: 0,
    };

    this.messages.set(message.id, message);
    this.pendingAcks.add(message.id);
    this.emit("enqueue", message);

    return message;
  }

  /**
   * Get message by ID
   */
  get(messageId: string): SessionMessage | undefined {
    return this.messages.get(messageId);
  }

  /**
   * Acknowledge a message
   */
  acknowledge(messageId: string): boolean {
    const message = this.messages.get(messageId);
    if (!message) {
      return false;
    }

    message.acknowledged = true;
    this.pendingAcks.delete(messageId);
    this.cancelRetry(messageId);
    this.emit("acknowledge", messageId);

    return true;
  }

  /**
   * Get all pending (unacknowledged) messages
   */
  getPending(): SessionMessage[] {
    return Array.from(this.messages.values())
      .filter((m) => !m.acknowledged)
      .sort((a, b) => a.sequence - b.sequence);
  }

  /**
   * Get messages in order
   */
  getOrdered(): SessionMessage[] {
    return Array.from(this.messages.values()).sort(
      (a, b) => a.sequence - b.sequence
    );
  }

  /**
   * Schedule retry for a message
   */
  scheduleRetry(messageId: string): void {
    const message = this.messages.get(messageId);
    if (!message || message.acknowledged) {
      return;
    }

    if (message.retryCount >= this.config.maxRetries) {
      this.drop(messageId, "Max retries exceeded");
      return;
    }

    // Cancel existing retry timer
    this.cancelRetry(messageId);

    // Schedule retry with exponential backoff
    const delay = this.config.retryDelayMs * 2 ** message.retryCount;
    const timer = setTimeout(() => {
      const msg = this.messages.get(messageId);
      if (msg && !msg.acknowledged) {
        msg.retryCount++;
        this.emit("retry", msg);
      }
    }, delay);

    this.retryTimers.set(messageId, timer);
  }

  /**
   * Cancel pending retry for a message
   */
  cancelRetry(messageId: string): void {
    const timer = this.retryTimers.get(messageId);
    if (timer) {
      clearTimeout(timer);
      this.retryTimers.delete(messageId);
    }
  }

  /**
   * Drop a message
   */
  drop(messageId: string, reason: string): void {
    const message = this.messages.get(messageId);
    if (!message) {
      return;
    }

    this.cancelRetry(messageId);
    this.messages.delete(messageId);
    this.pendingAcks.delete(messageId);
    this.emit("drop", message, reason);
  }

  /**
   * Clear expired messages
   */
  clearExpired(): number {
    const now = Date.now();
    let cleared = 0;

    for (const [id, message] of this.messages) {
      const age = now - message.timestamp.getTime();
      if (age > this.config.messageTtlMs && message.acknowledged) {
        this.messages.delete(id);
        cleared++;
      }
    }

    return cleared;
  }

  /**
   * Get queue statistics
   */
  getStats(): {
    total: number;
    pending: number;
    acknowledged: number;
    retrying: number;
  } {
    let pending = 0;
    let acknowledged = 0;

    for (const message of this.messages.values()) {
      if (message.acknowledged) {
        acknowledged++;
      } else {
        pending++;
      }
    }

    return {
      total: this.messages.size,
      pending,
      acknowledged,
      retrying: this.retryTimers.size,
    };
  }

  /**
   * Get current sequence number
   */
  getSequence(): number {
    return this.sequence;
  }

  /**
   * Clear all messages and timers
   */
  clear(): void {
    for (const timer of this.retryTimers.values()) {
      clearTimeout(timer);
    }
    this.retryTimers.clear();
    this.messages.clear();
    this.pendingAcks.clear();
  }

  /**
   * Get oldest acknowledged message
   */
  private getOldestAcknowledged(): SessionMessage | undefined {
    let oldest: SessionMessage | undefined;

    for (const message of this.messages.values()) {
      if (
        message.acknowledged &&
        (!oldest || message.sequence < oldest.sequence)
      ) {
        oldest = message;
      }
    }

    return oldest;
  }

  // Type-safe event methods
  override on(
    event: "enqueue",
    listener: (message: SessionMessage) => void
  ): this;
  override on(
    event: "dequeue",
    listener: (message: SessionMessage) => void
  ): this;
  override on(
    event: "acknowledge",
    listener: (messageId: string) => void
  ): this;
  override on(
    event: "retry",
    listener: (message: SessionMessage) => void
  ): this;
  override on(
    event: "drop",
    listener: (message: SessionMessage, reason: string) => void
  ): this;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }
}

/**
 * Create a message queue for a session
 */
export function createMessageQueue(
  sessionId: string,
  config?: Partial<QueueConfig>
): MessageQueue {
  return new MessageQueue(sessionId, config);
}
