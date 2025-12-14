import { format } from "date-fns";
import { Edit } from "lucide-react";
import type React from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { DBTable } from "@/types";
import { DeleteChangelogButton } from "./delete-changelog-button";

type ChangelogListProps = {
  changelogs: (DBTable<"marketing_changelog"> & {
    marketing_changelog_author_relationship: { author_id: string }[];
  })[];
};

export const ChangelogList: React.FC<ChangelogListProps> = ({ changelogs }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>Title</TableHead>
        <TableHead>Status</TableHead>
        <TableHead>Authors</TableHead>
        <TableHead>Created At</TableHead>
        <TableHead>Actions</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {changelogs.map((changelog) => (
        <TableRow
          data-testid={`changelog-row-${changelog.id}`}
          key={changelog.id}
        >
          <TableCell data-testid={`changelog-title-${changelog.id}`}>
            {changelog.title}
          </TableCell>
          <TableCell>{changelog.status}</TableCell>
          <TableCell>
            {changelog.marketing_changelog_author_relationship.length}
          </TableCell>
          <TableCell>
            {changelog.created_at
              ? format(new Date(changelog.created_at), "MMM dd, yyyy")
              : "N/A"}
          </TableCell>
          <TableCell>
            <div className="flex space-x-2">
              <Link href={`/app-admin/marketing/changelog/${changelog.id}`}>
                <Button size="sm" variant="outline">
                  <Edit className="h-4 w-4" />
                </Button>
              </Link>
              <DeleteChangelogButton
                changelogId={changelog.id}
                changelogTitle={changelog.title}
              />
            </div>
          </TableCell>
        </TableRow>
      ))}
    </TableBody>
  </Table>
);
