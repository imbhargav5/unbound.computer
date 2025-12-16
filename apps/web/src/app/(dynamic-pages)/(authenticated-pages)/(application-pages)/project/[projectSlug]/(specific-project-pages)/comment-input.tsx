"use client";
import { zodResolver } from "@hookform/resolvers/zod";
import { useAction } from "next-cool-action/hooks";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { createProjectCommentAction } from "@/data/user/projects";

const addCommentSchema = z.object({
  text: z.string().min(1),
});

type AddCommentSchema = z.infer<typeof addCommentSchema>;

type InFlightComment = {
  children: React.ReactNode;
  id: string | number;
};

export const CommentInput = ({
  projectId,
  projectSlug,
}: {
  projectId: string;
  projectSlug: string;
}) => {
  const { execute: addComment, isPending } = useAction(
    createProjectCommentAction
  );

  const { handleSubmit, setValue, register } = useForm<AddCommentSchema>({
    resolver: zodResolver(addCommentSchema),
    defaultValues: {
      text: "",
    },
  });
  return (
    <>
      <form
        onSubmit={handleSubmit((data) => {
          addComment({
            text: data.text,
            projectId,
            projectSlug,
          });
          setValue("text", "");
        })}
      >
        <div className="space-y-3">
          <Textarea
            className="h-24 rounded-lg border-none bg-gray-200/50 p-3 text-gray-700 dark:bg-gray-700/50 dark:text-muted-foreground"
            id="text"
            placeholder="Share your thoughts"
            {...register("text")}
          />
          <div className="flex justify-end space-x-2">
            <Button disabled={isPending} type="reset" variant="outline">
              Reset
            </Button>
            <Button disabled={isPending} type="submit">
              {isPending ? "Adding comment..." : "Add comment"}
            </Button>
          </div>
        </div>
      </form>
    </>
  );
};
