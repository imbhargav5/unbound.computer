import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import type { DBTable } from "@/types";

export function TagsNav({ tags }: { tags: DBTable<"marketing_tags">[] }) {
  return (
    <div className="flex flex-wrap justify-center space-x-2 px-4 sm:px-0">
      <Link href="/blog">
        <Button className="mr-2 mb-2" variant="outline">
          All
        </Button>
      </Link>

      {tags.map((tag) => (
        <Link href={`/blog/tag/${tag.slug}`} key={tag.id}>
          <Button className="mr-2 mb-2" variant="outline">
            {tag.name}
          </Button>
        </Link>
      ))}
    </div>
  );
}
