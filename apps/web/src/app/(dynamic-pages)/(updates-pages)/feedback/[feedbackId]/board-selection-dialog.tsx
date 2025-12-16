"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { FormSelect } from "@/components/form-components/form-select";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Form } from "@/components/ui/form";
import { updateFeedbackThreadBoardAction } from "@/data/admin/marketing-feedback";

const boardSelectionSchema = z.object({
  boardId: z.string().nullable(),
});

type BoardSelectionForm = z.infer<typeof boardSelectionSchema>;

interface BoardSelectionDialogProps {
  feedbackId: string;
  currentBoardId: string | null;
  boards: Array<{
    id: string;
    title: string;
  }>;
}

export function BoardSelectionDialog({
  feedbackId,
  currentBoardId,
  boards,
}: BoardSelectionDialogProps) {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();

  const form = useForm<BoardSelectionForm>({
    resolver: zodResolver(boardSelectionSchema),
    defaultValues: {
      boardId: currentBoardId,
    },
  });

  const { execute: updateBoard, status } = useAction(
    updateFeedbackThreadBoardAction,
    {
      onSuccess: () => {
        toast.success("Board updated successfully");
        setIsOpen(false);
      },
      onError: ({ error }) => {
        toast.error(error.serverError || "Failed to update board");
      },
    }
  );

  const onSubmit = (data: BoardSelectionForm) => {
    updateBoard({
      threadId: feedbackId,
      boardId: data.boardId === "none" ? null : data.boardId,
    });
  };

  const boardOptions = [
    { label: "None", value: "none" },
    ...boards.map((board) => ({
      label: board.title,
      value: board.id,
    })),
  ];

  const currentBoard = boards.find((board) => board.id === currentBoardId);

  return (
    <Dialog onOpenChange={setIsOpen} open={isOpen}>
      <DialogTrigger asChild>
        <Badge
          className="cursor-pointer transition-colors hover:bg-accent"
          variant="outline"
        >
          {currentBoard?.title || "None"}
        </Badge>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Update Board</DialogTitle>
        </DialogHeader>
        <Form {...form}>
          <form className="space-y-4" onSubmit={form.handleSubmit(onSubmit)}>
            <FormSelect
              control={form.control}
              id="board-selection"
              label="Select Board"
              name="boardId"
              options={boardOptions}
              placeholder="Select a board"
            />
            <Button
              className="w-full"
              disabled={status === "executing"}
              type="submit"
            >
              {status === "executing" ? "Updating..." : "Update Board"}
            </Button>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
