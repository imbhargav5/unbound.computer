import { Plus } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";

export function CreateTagButton() {
  return (
    <Button asChild>
      <Link href="/app-admin/marketing/tags/create">
        <Plus className="mr-2 h-4 w-4" />
        Create Tag
      </Link>
    </Button>
  );
}
