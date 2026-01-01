"use client";

import { Layers, Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { type SubmitHandler, useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createProjectAction } from "@/data/user/projects";
import { generateProjectSlug } from "@/lib/utils";
import { zodResolver } from "@/lib/zod-resolver";

const createProjectFormSchema = z.object({
  name: z.string().min(1),
  slug: z.string().min(1),
});

type CreateProjectFormData = z.infer<typeof createProjectFormSchema>;

interface CreateProjectDialogProps {
  workspaceId: string;
  onSuccess?: () => void;
}

export function CreateProjectDialog({
  workspaceId,
  onSuccess,
}: CreateProjectDialogProps) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  const { register, handleSubmit, setValue } = useForm<CreateProjectFormData>({
    resolver: zodResolver(createProjectFormSchema),
    defaultValues: {
      name: "",
      slug: "",
    },
  });

  const { execute: executeCreateProject, status } = useAction(
    createProjectAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Creating project...");
      },
      onNavigation: () => {
        toast.success("Project created!", { id: toastRef.current });
        toastRef.current = undefined;
        setOpen(false);
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to create project";
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    }
  );

  const onSubmit: SubmitHandler<CreateProjectFormData> = (data) => {
    executeCreateProject({ workspaceId, name: data.name, slug: data.slug });
  };

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button size="default" variant="ghost">
          <Plus className="h-5 w-5" />
          Create Project
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <div className="mb-2 w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Layers className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Create Project</DialogTitle>
            <DialogDescription className="mt-0 text-base">
              Create a new project and get started.
            </DialogDescription>
          </div>
        </DialogHeader>
        <form className="space-y-4" onSubmit={handleSubmit(onSubmit)}>
          <div>
            <Label>Project Name</Label>
            <Input
              {...register("name")}
              className="mt-1.5 w-full appearance-none rounded-lg border shadow-sm"
              disabled={status === "executing"}
              id="name"
              onChange={(e) => {
                setValue("name", e.target.value);
                setValue("slug", generateProjectSlug(e.target.value), {
                  shouldValidate: true,
                });
              }}
              placeholder="Project Name"
              type="text"
            />
          </div>
          <div>
            <Label>Project Slug</Label>
            <Input
              {...register("slug")}
              className="mt-1.5 w-full appearance-none rounded-lg border shadow-sm"
              disabled={status === "executing"}
              id="slug"
              placeholder="project-slug"
              type="text"
            />
          </div>

          <DialogFooter>
            <Button
              disabled={status === "executing"}
              onClick={() => {
                setOpen(false);
              }}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button
              disabled={status === "executing"}
              type="submit"
              variant="default"
            >
              {status === "executing"
                ? "Creating project..."
                : "Create Project"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
