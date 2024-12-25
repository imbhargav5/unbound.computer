"use client";

import { cn } from "@/lib/utils";
import { zodResolver } from "@hookform/resolvers/zod";
import { useOptimisticAction } from "next-safe-action/hooks";
import { Fragment, ReactElement, useRef } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";

import { T } from "@/components/ui/Typography";
import { Button } from "@/components/ui/button";
import { SelectSeparator } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { createProjectCommentAction } from "@/data/user/projects";
import { CommentList } from "./CommentList";

const addCommentSchema = z.object({
  text: z.string().min(1),
});

type AddCommentSchema = z.infer<typeof addCommentSchema>;

interface OptimisticState {
  comments: Array<{
    id: string | number;
    children: ReactElement;
    isPending?: boolean;
  }>;
}

export const CommentInput = ({
  projectId,
  projectSlug,
}: {
  projectId: string;
  projectSlug: string;
}) => {
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, optimisticState, isPending } = useOptimisticAction(
    createProjectCommentAction,
    {
      currentState: { comments: [] },
      updateFn: (state: OptimisticState, input) => ({
        comments: [
          ...state.comments,
          {
            id: crypto.randomUUID(),
            isPending: true,
            children: (
              <div className="opacity-50">
                <T.Subtle className="text-xs italic">
                  Sending comment...
                </T.Subtle>
                <div>{input.text}</div>
              </div>
            ),
          },
        ],
      }),
      onExecute: () => {
        toastRef.current = toast.loading("Adding comment...");
      },
      onSuccess: (result) => {
        toast.success("Comment added!", { id: toastRef.current });
        toastRef.current = undefined;
        if (!result.data) {
          throw new Error("No data returned from action");
        }
        return {
          comments: [
            {
              id: result.data.comment.id,
              isPending: false,
              children: <CommentList comments={[result.data.comment]} />,
            },
          ],
        };
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to add comment";
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    },
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
          execute({ projectId, projectSlug, text: data.text });
          setValue("text", "");
        })}
      >
        <div className="space-y-3">
          <Textarea
            id="text"
            placeholder="Share your thoughts"
            className="p-3 h-24 rounded-lg"
            {...register("text")}
          />
          <div className="flex justify-end space-x-2">
            <Button disabled={isPending} variant="outline" type="reset">
              Reset
            </Button>
            <Button disabled={isPending} type="submit">
              {isPending ? "Adding comment..." : "Add comment"}
            </Button>
          </div>
        </div>
      </form>
      <div className="mt-8 mb-4">
        <SelectSeparator />
      </div>
      {optimisticState.comments.map((comment) => (
        <div
          className={cn("space-y-2", {
            "opacity-50": comment.isPending,
          })}
          key={comment.id}
        >
          <Fragment key={comment.id}>{comment.children}</Fragment>
        </div>
      ))}
    </>
  );
};
