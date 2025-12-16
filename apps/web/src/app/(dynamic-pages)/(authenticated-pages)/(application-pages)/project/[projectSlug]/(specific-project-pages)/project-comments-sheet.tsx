"use client";
import { MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { CommentInput } from "./comment-input";
import { ProjectComments } from "./project-comments";

export function ProjectCommentsSheet({
  projectId,
  projectSlug,
}: {
  projectId: string;
  projectSlug: string;
}) {
  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button variant="outline">
          <MessageCircle className="h-5 w-5" />
          Comments
        </Button>
      </SheetTrigger>
      <SheetContent className="p-0">
        <div className="grid h-full grid-rows-[auto_1fr_auto] divide-y-2">
          <div className="px-6 py-4">
            <SheetTitle>Comments</SheetTitle>
            <SheetDescription>
              List of comments in recent first order
            </SheetDescription>
          </div>

          <div className="space-y-2 overflow-y-auto">
            <ProjectComments projectId={projectId} />
          </div>
          <div className="space-y-2 p-6">
            <SheetTitle>Add Comment</SheetTitle>
            <CommentInput projectId={projectId} projectSlug={projectSlug} />
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
