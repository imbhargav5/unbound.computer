import { PRODUCT_NAME } from "@/constants";
import {
  type UserNotificationPayloadType,
  userNotificationPayloadSchema,
} from "./zod-schemas/notifications";

type NormalizedNotification = {
  title: string;
  description: string;
  image: string;
  icon?: React.ReactNode;
  type: UserNotificationPayloadType["type"] | "unknown";
} & (
  | {
      actionType: "link";
      href: string;
    }
  | {
      actionType: "button";
    }
);

export const parseNotification = (
  notificationPayload: unknown
): NormalizedNotification => {
  try {
    const notification =
      userNotificationPayloadSchema.parse(notificationPayload);
    switch (notification.type) {
      case "welcome":
        return {
          title: "Welcome to Unbound",
          description: "Welcome to Unbound. We are glad to see you here!",
          actionType: "button",
          image: "/logos/logo-black.png",
          type: notification.type,
        };
      case "receivedFeedback":
        return {
          title: `${PRODUCT_NAME} received new feedback`,
          description: `${notification.feedbackCreatorFullName} said: ${notification.feedbackTitle}`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackReceivedComment":
        return {
          title: `New comment on ${notification.feedbackTitle}`,
          description: `${notification.commenterName} says: ${
            notification.comment.slice(0, 50) + "..."
          }`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackStatusChanged":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback status was updated from ${notification.oldStatus} to ${notification.newStatus}`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackPriorityChanged":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback priority was updated from ${notification.oldPriority} to ${notification.newPriority}`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackTypeUpdated":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback priority was updated from ${notification.oldType} to ${notification.newType}`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackIsInRoadmapUpdated":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback is now ${
            notification.isInRoadmap ? "added to" : "removed from"
          } roadmap.`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackVisibilityUpdated":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback is now ${
            notification.isPubliclyVisible ? "visible to" : "hidden from"
          } public.`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      case "feedbackFeedbackOpenForCommentUpdated":
        return {
          title: "Your feedback was updated.",
          description: `Your feedback is now ${
            notification.isOpenForComments ? "open" : "closed to"
          } comments.`,
          image: "/logos/logo-black.png",
          actionType: "link",
          href: `/feedback/${notification.feedbackId}`,
          type: notification.type,
        };
      default: {
        return {
          title: "Unknown notification type",
          description: "Unknown notification type",
          href: "#",
          image: "/logos/logo-black.png",
          actionType: "link",
          type: "unknown",
        };
      }
    }
  } catch (error) {
    return {
      title: "Unknown notification type",
      description: "Unknown notification type",
      image: "/logos/logo-black.png",
      actionType: "button",
      type: "unknown",
    };
  }
};
