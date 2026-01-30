/**
 * Notification Manager
 *
 * Handles sending push notifications to offline iOS devices when session events occur.
 * Queries the database for APNs tokens and coordinates with the APNs service.
 */

import { supabaseAdmin } from "../auth/supabase.js";
import { connectionManager } from "../managers/index.js";
import { createLogger } from "../utils/index.js";
import { apnsService } from "./apns.js";

const log = createLogger({ module: "notification-manager" });

/**
 * Device with APNs token information from the database
 */
interface DeviceWithApns {
  id: string;
  user_id: string;
  name: string | null;
  apns_token: string | null;
  apns_environment: "sandbox" | "production" | null;
  push_enabled: boolean;
}

/**
 * Live Activity token from the database
 */
interface LiveActivityToken {
  id: string;
  device_id: string;
  activity_id: string;
  push_token: string;
  apns_environment: "sandbox" | "production";
  is_active: boolean;
}

/**
 * Notification types for different events
 */
type NotificationType =
  | "session_started"
  | "session_ended"
  | "member_joined"
  | "member_left"
  | "approval_request"
  | "run_update";

/**
 * Notification Manager for coordinating push notifications
 */
class NotificationManager {
  private initialized = false;

  /**
   * Initialize the notification manager
   */
  initialize(): boolean {
    if (!apnsService.isConfigured) {
      log.info("APNs not configured - notification manager disabled");
      return false;
    }

    const apnsInitialized = apnsService.initialize();
    this.initialized = apnsInitialized;

    if (apnsInitialized) {
      log.info("Notification manager initialized");
    }

    return this.initialized;
  }

  /**
   * Check if notifications are available
   */
  get isAvailable(): boolean {
    return this.initialized && apnsService.isConfigured;
  }

  /**
   * Notify offline iOS devices in a session about an event
   */
  async notifySessionMembers(
    sessionId: string,
    notificationType: NotificationType,
    payload: Record<string, unknown>,
    excludeDeviceId?: string
  ): Promise<void> {
    if (!this.isAvailable) {
      return;
    }

    try {
      // Get all session members
      const sessionMembers = connectionManager.getSessionMembers(sessionId);
      if (sessionMembers.length === 0) {
        return;
      }

      // Filter to offline devices
      const offlineDevices = sessionMembers.filter(
        (deviceId) =>
          deviceId !== excludeDeviceId &&
          !connectionManager.isDeviceOnline(deviceId)
      );

      if (offlineDevices.length === 0) {
        log.debug({ sessionId }, "No offline devices in session to notify");
        return;
      }

      // Get APNs tokens for offline devices
      const { data: devices, error } = await supabaseAdmin
        .from("devices")
        .select("id, user_id, name, apns_token, apns_environment, push_enabled")
        .in("id", offlineDevices)
        .eq("push_enabled", true)
        .not("apns_token", "is", null);

      if (error) {
        log.error({ error, sessionId }, "Failed to query device APNs tokens");
        return;
      }

      if (!devices || devices.length === 0) {
        log.debug({ sessionId }, "No devices with APNs tokens to notify");
        return;
      }

      // Send push notifications in parallel
      const results = await Promise.allSettled(
        devices.map((device) =>
          this.sendNotification(
            device as DeviceWithApns,
            notificationType,
            sessionId,
            payload
          )
        )
      );

      const successful = results.filter((r) => r.status === "fulfilled").length;
      const failed = results.filter((r) => r.status === "rejected").length;

      log.info(
        { sessionId, notificationType, successful, failed },
        "Sent session notifications"
      );
    } catch (error) {
      log.error(
        { error, sessionId, notificationType },
        "Failed to notify session members"
      );
    }
  }

  /**
   * Notify a specific device (if offline and has APNs token)
   */
  async notifyDevice(
    deviceId: string,
    notificationType: NotificationType,
    payload: Record<string, unknown>
  ): Promise<boolean> {
    if (!this.isAvailable) {
      return false;
    }

    // Skip if device is online (they'll get the message via WebSocket)
    if (connectionManager.isDeviceOnline(deviceId)) {
      log.debug({ deviceId }, "Device is online, skipping push notification");
      return false;
    }

    try {
      // Get APNs token for device
      const { data: device, error } = await supabaseAdmin
        .from("devices")
        .select("id, user_id, name, apns_token, apns_environment, push_enabled")
        .eq("id", deviceId)
        .eq("push_enabled", true)
        .not("apns_token", "is", null)
        .single();

      if (error || !device) {
        log.debug({ deviceId }, "Device not found or push not enabled");
        return false;
      }

      return this.sendNotification(
        device as DeviceWithApns,
        notificationType,
        undefined,
        payload
      );
    } catch (error) {
      log.error(
        { error, deviceId, notificationType },
        "Failed to notify device"
      );
      return false;
    }
  }

  /**
   * Notify all controller devices for an account (iOS devices watching sessions)
   */
  async notifyAccountControllers(
    accountId: string,
    notificationType: NotificationType,
    payload: Record<string, unknown>,
    excludeDeviceId?: string
  ): Promise<void> {
    if (!this.isAvailable) {
      return;
    }

    try {
      // Get all iOS devices for this account with push enabled
      const { data: devices, error } = await supabaseAdmin
        .from("devices")
        .select("id, user_id, name, apns_token, apns_environment, push_enabled")
        .eq("user_id", accountId)
        .eq("device_type", "ios")
        .eq("push_enabled", true)
        .not("apns_token", "is", null);

      if (error) {
        log.error({ error, accountId }, "Failed to query account iOS devices");
        return;
      }

      if (!devices || devices.length === 0) {
        return;
      }

      // Filter out excluded device and online devices
      const offlineDevices = devices.filter(
        (d) =>
          d.id !== excludeDeviceId && !connectionManager.isDeviceOnline(d.id)
      );

      if (offlineDevices.length === 0) {
        return;
      }

      // Send push notifications in parallel
      await Promise.allSettled(
        offlineDevices.map((device) =>
          this.sendNotification(
            device as DeviceWithApns,
            notificationType,
            undefined,
            payload
          )
        )
      );

      log.info(
        { accountId, notificationType, count: offlineDevices.length },
        "Sent account controller notifications"
      );
    } catch (error) {
      log.error({ error, accountId }, "Failed to notify account controllers");
    }
  }

  /**
   * Update all active Live Activities for a session
   */
  async updateLiveActivities(
    sessionId: string,
    contentState: Record<string, unknown>,
    event: "update" | "end" = "update"
  ): Promise<void> {
    if (!this.isAvailable) {
      return;
    }

    try {
      // Get all active Live Activity tokens for devices in this session
      const sessionMembers = connectionManager.getSessionMembers(sessionId);
      if (sessionMembers.length === 0) {
        return;
      }

      const { data: tokens, error } = await supabaseAdmin
        .from("live_activity_tokens")
        .select(
          "id, device_id, activity_id, push_token, apns_environment, is_active"
        )
        .in("device_id", sessionMembers)
        .eq("is_active", true);

      if (error) {
        log.error({ error, sessionId }, "Failed to query Live Activity tokens");
        return;
      }

      if (!tokens || tokens.length === 0) {
        return;
      }

      // Send Live Activity updates in parallel
      const results = await Promise.allSettled(
        tokens.map((token) =>
          apnsService.updateLiveActivity(
            token.push_token,
            contentState,
            event,
            token.apns_environment as "sandbox" | "production"
          )
        )
      );

      const successful = results.filter((r) => r.status === "fulfilled").length;
      log.info(
        { sessionId, event, successful, total: tokens.length },
        "Sent Live Activity updates"
      );

      // If ending, mark tokens as inactive
      if (event === "end") {
        await supabaseAdmin
          .from("live_activity_tokens")
          .update({ is_active: false, updated_at: new Date().toISOString() })
          .in("device_id", sessionMembers);
      }
    } catch (error) {
      log.error({ error, sessionId }, "Failed to update Live Activities");
    }
  }

  /**
   * Send a push notification to a specific device
   */
  private async sendNotification(
    device: DeviceWithApns,
    notificationType: NotificationType,
    sessionId: string | undefined,
    payload: Record<string, unknown>
  ): Promise<boolean> {
    if (!(device.apns_token && device.apns_environment)) {
      return false;
    }

    const notification = this.buildNotification(
      notificationType,
      payload,
      device.name
    );

    const result = await apnsService.sendAlert(
      device.apns_token,
      notification.alert,
      {
        type: notificationType,
        sessionId,
        ...payload,
      },
      device.apns_environment
    );

    return result.success;
  }

  /**
   * Build notification content based on type
   */
  private buildNotification(
    type: NotificationType,
    payload: Record<string, unknown>,
    _deviceName: string | null
  ): { alert: { title?: string; subtitle?: string; body?: string } } {
    switch (type) {
      case "session_started":
        return {
          alert: {
            title: "Session Started",
            body: `${payload.executorName ?? "A device"} started a Claude Code session`,
          },
        };

      case "session_ended":
        return {
          alert: {
            title: "Session Ended",
            body: `${payload.executorName ?? "The"} session has ended`,
          },
        };

      case "member_joined":
        return {
          alert: {
            title: "Device Connected",
            body: `${payload.memberName ?? "A device"} joined the session`,
          },
        };

      case "member_left":
        return {
          alert: {
            title: "Device Disconnected",
            body: `${payload.memberName ?? "A device"} left the session`,
          },
        };

      case "approval_request":
        return {
          alert: {
            title: "Approval Required",
            subtitle: payload.projectName as string | undefined,
            body:
              (payload.description as string) ??
              "Claude is waiting for your approval",
          },
        };

      case "run_update":
        return {
          alert: {
            title: "Run Update",
            body: (payload.message as string) ?? "Session activity update",
          },
        };

      default:
        return {
          alert: {
            title: "Unbound",
            body: "New activity in your session",
          },
        };
    }
  }

  /**
   * Shutdown and cleanup
   */
  shutdown(): void {
    apnsService.shutdown();
    log.info("Notification manager shut down");
  }
}

// Singleton instance
export const notificationManager = new NotificationManager();
