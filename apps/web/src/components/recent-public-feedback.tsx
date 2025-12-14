import { Clock } from "lucide-react";
import { Link } from "@/components/intl-link";
import { cachedGetRecentPublicFeedback } from "@/data/anon/marketing-feedback";

export async function RecentPublicFeedback() {
  const recentFeedback = await cachedGetRecentPublicFeedback();
  if (recentFeedback.length === 0) {
    return <p className="text-muted-foreground text-sm">Nothing here yet.</p>;
  }

  return (
    <div className="space-y-1">
      {recentFeedback.map((item) => (
        <Link
          className="group block"
          href={`/feedback/${item.id}`}
          key={item.id}
        >
          <div className="-mx-2 rounded-md px-2 py-2.5 transition-colors hover:bg-accent/50">
            <p className="line-clamp-1 font-medium text-foreground text-sm transition-colors group-hover:text-primary">
              {item.title}
            </p>
            <p className="mt-1 flex items-center gap-1.5 text-muted-foreground text-xs">
              <Clock className="h-3 w-3" />
              {new Date(item.created_at).toLocaleDateString()}
            </p>
          </div>
        </Link>
      ))}
    </div>
  );
}
