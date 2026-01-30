import { motion } from "motion/react";
import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/typography-ui";
import { useReadNotification } from "@/hooks/notifications";
import { cn } from "@/utils/cn";

/**
 * Props for the NotificationItem component
 * Defines the structure and optional properties for rendering a notification
 */
type NotificationItemProps = {
  /** Title of the notification */
  title: string;
  /** Detailed description of the notification */
  description: string;
  /** Optional link destination for the notification */
  href?: string;
  /** Optional click handler for the notification */
  onClick?: () => void;
  /** Image URL for the notification avatar */
  image: string;
  /** Indicates if the notification has been read */
  isRead: boolean;
  /** Timestamp when the notification was created */
  createdAt: string;
  /** Indicates if the notification is new */
  isNew: boolean;
  /** Unique identifier for the notification */
  notificationId: string;
  /** Callback triggered on mouse hover */
  onHover: () => void;
  /** Optional custom icon to replace the default image */
  icon?: React.ReactNode;
};

/**
 * Renders an individual notification item with dynamic styling and interactions
 *
 * @param props - Configuration properties for the notification
 * @returns A renderable notification component with optional linking and hover effects
 */
export function NotificationItem({
  title,
  description,
  href,
  image,
  isRead,
  isNew,
  onClick,
  createdAt,
  notificationId,
  onHover,
  icon,
}: NotificationItemProps) {
  // Access the notification mutation hook to mark notifications as read
  const { mutate: mutateReadNotification } = useReadNotification();

  // Shared content rendering for both linked and non-linked notifications
  const content = (
    <div
      className={cn(
        "relative flex w-full items-start gap-4 p-4",
        isRead ? "bg-muted/50" : "bg-card",
        "transition-colors duration-200 hover:bg-accent/10",
        href && "cursor-pointer"
      )}
      onMouseOver={onHover}
    >
      {/* Render either a custom icon or a default avatar image */}
      {icon ? (
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
          {icon}
        </div>
      ) : (
        <motion.img
          // Animate image scaling for subtle entrance effect
          alt={title}
          animate={{ scale: 1 }}
          className="h-12 w-12 rounded-full border-2 border-border object-cover"
          initial={{ scale: 0.8 }}
          src={image}
          transition={{ duration: 0.2 }}
        />
      )}

      {/* Notification text content with typography variations */}
      <div className="grow space-y-1">
        <T.P className="font-medium text-foreground leading-snug">{title}</T.P>
        <T.Small className="block text-muted-foreground">{description}</T.Small>
        <T.Subtle className="block text-muted-foreground/75 text-xs">
          {createdAt}
        </T.Subtle>
      </div>

      {/* Render a small indicator for new notifications */}
      {isNew && (
        <motion.div
          // Animate new notification indicator with scale
          animate={{ scale: 1 }}
          className="absolute top-4 right-4 h-2.5 w-2.5 rounded-full bg-primary ring-4 ring-primary/10"
          initial={{ scale: 0 }}
        />
      )}
    </div>
  );

  // Conditionally render as a link or a div based on href prop
  if (href) {
    return (
      <Link
        className="block w-full"
        // Mark notification as read when clicked
        href={href}
        onClick={() => mutateReadNotification(notificationId)}
      >
        {content}
      </Link>
    );
  }

  // Render as a standard div with optional click handler
  return (
    <div className="w-full" onClick={onClick}>
      {content}
    </div>
  );
}
