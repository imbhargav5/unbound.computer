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
import { DeleteTagButton } from "./delete-tag-button";

type TagsListProps = {
  tags: DBTable<"marketing_tags">[];
};

export const TagsList: React.FC<TagsListProps> = ({ tags }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>Name</TableHead>
        <TableHead>Slug</TableHead>
        <TableHead>Description</TableHead>
        <TableHead>Actions</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {tags.map((tag) => (
        <TableRow key={tag.id}>
          <TableCell>{tag.name}</TableCell>
          <TableCell>{tag.slug}</TableCell>
          <TableCell>{tag.description}</TableCell>
          <TableCell>
            <div className="flex space-x-2">
              <Link href={`/app-admin/marketing/tags/${tag.id}`}>
                <Button size="sm" variant="outline">
                  <Edit className="h-4 w-4" />
                </Button>
              </Link>
              <DeleteTagButton tagId={tag.id} tagName={tag.name} />
            </div>
          </TableCell>
        </TableRow>
      ))}
    </TableBody>
  </Table>
);
