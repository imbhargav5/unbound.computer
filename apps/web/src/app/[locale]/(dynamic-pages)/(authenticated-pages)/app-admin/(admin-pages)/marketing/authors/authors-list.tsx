// src/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/AuthorsList.tsx
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
import { Typography } from "@/components/ui/typography-ui";
import type { DBTable } from "@/types";
import { CreateMarketingAuthorProfileButton } from "./create-marketing-author-profile-button";
import { DeleteAuthorButton } from "./delete-author-button";

type AuthorsListProps = {
  authors: DBTable<"marketing_author_profiles">[];
};

export const AuthorsList: React.FC<AuthorsListProps> = ({ authors }) => (
  <div>
    <div className="mb-4 flex items-center justify-between">
      <Typography.H4 className="text-2xl">
        Manage your marketing authors
      </Typography.H4>
      <CreateMarketingAuthorProfileButton />
    </div>
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Avatar</TableHead>
          <TableHead>Name</TableHead>
          <TableHead>Slug</TableHead>
          <TableHead>Created At</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {authors.map((profile) => (
          <TableRow key={profile.id}>
            <TableCell>
              <img
                alt={profile.display_name}
                className="h-10 w-10 rounded-full"
                src={profile.avatar_url}
              />
            </TableCell>
            <TableCell>{profile.display_name}</TableCell>
            <TableCell>{profile.slug}</TableCell>
            <TableCell>
              {format(new Date(profile.created_at), "MMM dd, yyyy")}
            </TableCell>
            <TableCell>
              <div className="flex space-x-2">
                <Link href={`/app-admin/marketing/authors/${profile.id}`}>
                  <Button size="sm" variant="outline">
                    <Edit className="h-4 w-4" />
                  </Button>
                </Link>
                <DeleteAuthorButton
                  authorId={profile.id}
                  authorName={profile.display_name}
                />
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </div>
);
