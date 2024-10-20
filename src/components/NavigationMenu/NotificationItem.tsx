import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/Typography";
import { useNotificationsContext } from "@/contexts/NotificationsContext";
import { cn } from "@/utils/cn";
import { motion } from "framer-motion";

type NotificationItemProps = {
  title: string;
  description: string;
  href?: string;
  onClick?: () => void;
  image: string;
  isRead: boolean;
  createdAt: string;
  isNew: boolean;
  notificationId: string;
  onHover: () => void;
};

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
}: NotificationItemProps) {
  const { mutateReadNotification } = useNotificationsContext();

  const content = (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.3 }}
      onMouseOver={onHover}
      className={cn(
        "flex items-center w-full px-4 py-3 border-b",
        isRead ? "bg-accent/50" : "bg-background",
        "hover:bg-accent/25 transition-colors duration-200",
      )}
    >
      <motion.img
        initial={{ scale: 0.8 }}
        animate={{ scale: 1 }}
        transition={{ duration: 0.2 }}
        src={image}
        alt={title}
        className="h-12 w-12 rounded-full object-cover mr-4"
      />
      <div className="flex-grow">
        <T.P className="font-semibold text-foreground !leading-5">{title}</T.P>
        <T.Small className="text-muted-foreground">{description}</T.Small>
        <T.Subtle className="text-xs text-muted-foreground/75">
          {createdAt}
        </T.Subtle>
      </div>
      {isNew && (
        <motion.div
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          className="h-2 w-2 rounded-full bg-primary"
        />
      )}
    </motion.div>
  );

  if (href) {
    return (
      <Link
        href={href}
        onClick={() => mutateReadNotification(notificationId)}
        className="block w-full"
      >
        {content}
      </Link>
    );
  }

  return (
    <div className="w-full" onClick={onClick}>
      {content}
    </div>
  );
}
