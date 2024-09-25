import { Link } from '@/components/intl-link';
import { getRecentPublicFeedback } from '@/data/anon/marketing-feedback';

export async function RecentPublicFeedback() {
  const recentFeedback = await getRecentPublicFeedback();

  return (
    <ul className="space-y-2">
      {recentFeedback.map((item) => (
        <li key={item.id} className="text-sm">
          <Link href={`/feedback/${item.id}`} className="text-primary hover:underline">
            {item.title}
          </Link>
          <p className="text-xs text-muted-foreground">
            {new Date(item.created_at).toLocaleDateString()}
          </p>
        </li>
      ))}
    </ul>
  );
}
