import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet";
import { T } from "@/components/ui/Typography";
import { cn } from "@/lib/utils";
import { MessageCircleIcon } from "lucide-react";
import { Suspense } from "react";
import { CommentInput } from "./CommentInput";
import { ProjectComments } from "./ProjectComments";

interface CommentsSheetProps {
  projectId: string;
}

export function CommentsSheet({ projectId }: CommentsSheetProps) {
  return (
    <div>
      <Sheet>
        <SheetTrigger asChild>
          <Button variant="outline">
            <span className="hidden sm:inline">Comments</span>
            <span className="sm:hidden">
              <MessageCircleIcon className="h-4 w-4" />
            </span>
          </Button>
        </SheetTrigger>
        <SheetContent side="right" className="w-[90vw] sm:w-[385px]">
          <T.H4>Comments</T.H4>
          <div className={cn("space-y-2 mt-4")}>
            <CommentInput projectId={projectId} />
            <Suspense fallback={<div>Loading comments...</div>}>
              <ProjectComments projectId={projectId} />
            </Suspense>
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}
