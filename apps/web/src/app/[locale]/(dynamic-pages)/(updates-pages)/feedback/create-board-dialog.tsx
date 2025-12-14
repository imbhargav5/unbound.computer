"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { LayoutDashboard } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useEffect, useRef, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import { z } from "zod";
import { SelectFeedbackBoardColor } from "@/components/form-components/select-feedback-board-color";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Form } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createFeedbackBoardAction } from "@/data/admin/marketing-feedback";
import { useRouter } from "@/i18n/navigation";
import { cn } from "@/utils/cn";

const boardSchema = z.object({
  title: z.string().min(1, "Title is required"),
  description: z.string().min(1, "Description is required"),
  slug: z
    .string()
    .min(1, "Slug is required")
    .regex(
      /^[a-z0-9-]+$/,
      "Slug must contain only lowercase letters, numbers, and hyphens"
    ),
  color: z.string().optional(),
});

type BoardFormType = z.infer<typeof boardSchema>;

interface CreateBoardDialogProps {
  children: React.ReactNode;
  className?: string;
}

export const CreateBoardDialog: React.FC<CreateBoardDialogProps> = ({
  children,
  className,
}) => {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const form = useForm<BoardFormType>({
    resolver: zodResolver(boardSchema),
    defaultValues: {
      title: "New Board",
      description: "New Board Description",
      slug: "new-board",
      color: "blue",
    },
  });

  const { control, handleSubmit, formState, reset } = form;

  const { execute: createBoard, status } = useAction(
    createFeedbackBoardAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Creating board...");
      },
      onSuccess: ({ data }) => {
        toast.success("Board created successfully", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        reset();
        setIsOpen(false);
        if (data?.slug) {
          router.push(`/feedback/boards/${data.slug}`);
        }
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to create board";
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    }
  );

  const currentTitle = form.watch("title");

  useEffect(() => {
    if (currentTitle) {
      form.setValue(
        "slug",
        slugify(currentTitle, {
          lower: true,
          strict: true,
          replacement: "-",
        })
      );
    }
  }, [currentTitle]);

  const { isValid } = formState;

  const onSubmit = (data: BoardFormType) => {
    createBoard(data);
  };

  return (
    <Dialog
      onOpenChange={(newIsOpen) => {
        setIsOpen(newIsOpen);
      }}
      open={isOpen}
    >
      <DialogTrigger className={cn("w-full", className)}>
        {children}
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <LayoutDashboard className="h-6 w-6" />
          </div>
          <div className="mb-4 p-1">
            <DialogTitle className="text-lg">Create Feedback Board</DialogTitle>
            <DialogDescription className="text-base">
              Create a new board to organize and collect feedback
            </DialogDescription>
          </div>
        </DialogHeader>
        <Form {...form}>
          <form
            className="space-y-4"
            data-testid="create-board-form"
            onSubmit={handleSubmit(onSubmit)}
          >
            <div className="space-y-1">
              <Label>Title</Label>
              <Controller
                control={control}
                name="title"
                render={({ field, fieldState }) => (
                  <>
                    <Input
                      data-testid="board-title-input"
                      {...field}
                      placeholder="e.g., Feature Requests"
                    />
                    {fieldState.error && (
                      <p className="text-red-500 text-sm">
                        {fieldState.error.message}
                      </p>
                    )}
                  </>
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Description</Label>
              <Controller
                control={control}
                name="description"
                render={({ field, fieldState }) => (
                  <>
                    <Textarea
                      data-testid="board-description-input"
                      {...field}
                      placeholder="Describe the purpose of this board"
                    />
                    {fieldState.error && (
                      <p className="text-red-500 text-sm">
                        {fieldState.error.message}
                      </p>
                    )}
                  </>
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Slug</Label>
              <Controller
                control={control}
                name="slug"
                render={({ field, fieldState }) => (
                  <>
                    <Input
                      data-testid="board-slug-input"
                      {...field}
                      placeholder="e.g., feature-requests"
                    />
                    {fieldState.error && (
                      <p className="text-red-500 text-sm">
                        {fieldState.error.message}
                      </p>
                    )}
                  </>
                )}
              />
              <p className="text-gray-500 text-sm">
                This will be used in the URL: /feedback/boards/your-slug
              </p>
            </div>
            <div className="space-y-1">
              <Label>Color</Label>
              <SelectFeedbackBoardColor
                control={control}
                description="Choose a color for your board"
                name="color"
              />
            </div>
            <Button
              className="mt-4 w-full"
              data-testid="submit-board-button"
              disabled={!isValid || status === "executing"}
              type="submit"
            >
              {status === "executing" ? "Creating..." : "Create Board"}
            </Button>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
};
