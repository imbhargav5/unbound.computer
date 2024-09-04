"use client";
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
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { generateProjectSlug } from "@/lib/utils";
import { zodResolver } from "@hookform/resolvers/zod";
import { Layers } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useForm, type SubmitHandler } from "react-hook-form";
import { z } from "zod";

const createProjectFormSchema = z.object({
  name: z.string().min(1),
  slug: z.string().min(1),
});

type CreateProjectDialogProps = {
  workspaceId: string;
};

export function CreateProjectDialog({
  workspaceId,
}: CreateProjectDialogProps) {
  const { register, handleSubmit, setValue } = useForm({
    resolver: zodResolver(createProjectFormSchema),
    defaultValues: {
      name: "",
      slug: "",
    },
  });

  const [open, setOpen] = useState(false);
  const router = useRouter();
  const createProjectMutation = useSAToastMutation(
    async ({
      name,
      slug,
    }: { workspaceId: string; name: string; slug: string }) =>
      await createProjectAction({ workspaceId, name, slug }),
    {
      loadingMessage: "Creating project...",
      successMessage: "Project created!",
      errorMessage: "Failed to create project",
      onSuccess: (response) => {
        setOpen(false);
        if (response.status === "success" && response.data) {
          router.push(`/project/${response.data.slug}`);
        }
      },
    },
  );

  const onSubmit: SubmitHandler<{ name: string; slug: string }> = (data) => {
    createProjectMutation.mutate({
      name: data.name,
      slug: data.slug,
    });
  };

  return (
    <>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogTrigger asChild>
          <Button variant="default" size="default">
            <Layers className="mr-2 w-5 h-5" />
            Create Project
          </Button>
        </DialogTrigger>
        <DialogContent>
          <DialogHeader>
            <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 mb-2 rounded-lg">
              <Layers className=" w-6 h-6" />
            </div>
            <div className="p-1">
              <DialogTitle className="text-lg">Create Project</DialogTitle>
              <DialogDescription className="text-base mt-0">
                Create a new project and get started.
              </DialogDescription>
            </div>
          </DialogHeader>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div>
              <Label>Project Name</Label>
              <Input
                {...register("name")}
                className="mt-1.5 shadow appearance-none border rounded-lg w-full"
                onChange={(e) => {
                  setValue("name", e.target.value);
                  setValue("slug", generateProjectSlug(e.target.value), {
                    shouldValidate: true,
                  });
                }}
                id="name"
                type="text"
                placeholder="Project Name"
                disabled={createProjectMutation.isLoading}
              />
            </div>
            <div>
              <Label>Project Slug</Label>
              <Input
                {...register("slug")}
                className="mt-1.5 shadow appearance-none border rounded-lg w-full"
                id="slug"
                type="text"
                placeholder="project-slug"
                disabled={createProjectMutation.isLoading}
              />
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                disabled={createProjectMutation.isLoading}
                className="w-full"
                onClick={() => {
                  setOpen(false);
                }}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                variant="default"
                className="w-full"
                disabled={createProjectMutation.isLoading}
              >
                {createProjectMutation.isLoading
                  ? "Creating project..."
                  : "Create Project"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
