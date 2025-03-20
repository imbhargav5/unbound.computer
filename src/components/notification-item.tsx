import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/Typography";
import { useNotificationsContext } from "@/contexts/NotificationsContext";
import { cn } from "@/utils/cn";
import { motion } from "motion/react";

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
  // Access the notification mutation context to mark notifications as read
  const { mutateReadNotification } = useNotificationsContext();

  // Shared content rendering for both linked and non-linked notifications
  const content = (
    <div
      onMouseOver={onHover}
      className={cn(
        "flex items-start w-full p-4 gap-4 relative",
        isRead ? "bg-muted/50" : "bg-card",
        "hover:bg-accent/10 transition-colors duration-200",
        href && "cursor-pointer",
      )}
    >
      {/* Render either a custom icon or a default avatar image */}
      {icon ? (
        <div className="w-12 h-12 flex items-center justify-center rounded-full bg-primary/10">
          {icon}
        </div>
      ) : (
        <motion.img
          // Animate image scaling for subtle entrance effect
          initial={{ scale: 0.8 }}
          animate={{ scale: 1 }}
          transition={{ duration: 0.2 }}
          src={image}
          alt={title}
          className="h-12 w-12 rounded-full object-cover border-2 border-border"
        />
      )}

      {/* Notification text content with typography variations */}
      <div className="grow space-y-1">
        <T.P className="font-medium text-foreground leading-snug">{title}</T.P>
        <T.Small className="text-muted-foreground block">{description}</T.Small>
        <T.Subtle className="text-xs text-muted-foreground/75 block">
          {createdAt}
        </T.Subtle>
      </div>

      {/* Render a small indicator for new notifications */}
      {isNew && (
        <motion.div
          // Animate new notification indicator with scale
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          className="absolute right-4 top-4 h-2.5 w-2.5 rounded-full bg-primary ring-4 ring-primary/10"
        />
      )}
    </div>
  );

  // Conditionally render as a link or a div based on href prop
  if (href) {
    return (
      <Link
        href={href}
        // Mark notification as read when clicked
        onClick={() => mutateReadNotification(notificationId)}
        className="block w-full"
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
