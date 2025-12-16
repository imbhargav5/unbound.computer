"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Loader, Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useEffect, useRef } from "react";
import { useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createMarketingTagAction } from "@/data/admin/marketing-tags";

const createTagSchema = z.object({
  name: z.string().min(1, "Name is required"),
  slug: z.string().min(1, "Slug is required"),
  description: z.string().optional(),
});

type FormData = z.infer<typeof createTagSchema>;

export function CreateTagForm() {
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
    setValue,
  } = useForm<FormData>({
    resolver: zodResolver(createTagSchema),
    defaultValues: {
      name: "",
      slug: "",
      description: "",
    },
  });

  const watchName = watch("name");

  useEffect(() => {
    if (watchName) {
      setValue("slug", slugify(watchName, { lower: true, strict: true }));
    }
  }, [watchName, setValue]);

  const createMutation = useAction(createMarketingTagAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating tag...", {
        description: "Please wait while we create the tag.",
      });
    },
    onSuccess: ({ data }) => {
      toast.success("Tag created!", {
        description: "Redirecting to edit page...",
        id: toastRef.current,
      });
      toastRef.current = undefined;
      if (data) {
        router.push(`/app-admin/marketing/tags/${data.id}`);
      }
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to create tag: ${error.serverError || "Unknown error"}`,
        {
          description: "Please try again.",
          id: toastRef.current,
        }
      );
      toastRef.current = undefined;
    },
  });

  const onSubmit = (data: FormData) => {
    createMutation.execute(data);
  };

  return (
    <>
      <div className="mb-6">
        <p className="text-muted-foreground text-sm">Create New</p>
        <h1 className="font-bold text-3xl">Tag</h1>
      </div>
      <form className="max-w-lg space-y-6" onSubmit={handleSubmit(onSubmit)}>
        <div>
          <Label htmlFor="name">
            Name <span className="text-destructive">*</span>
          </Label>
          <Input id="name" placeholder="Enter tag name" {...register("name")} />
          {errors.name ? (
            <p className="mt-1 text-destructive text-sm">
              {errors.name.message}
            </p>
          ) : null}
        </div>
        <div>
          <Label htmlFor="slug">
            Slug <span className="text-destructive">*</span>
          </Label>
          <Input id="slug" placeholder="tag-slug" {...register("slug")} />
          {errors.slug ? (
            <p className="mt-1 text-destructive text-sm">
              {errors.slug.message}
            </p>
          ) : null}
        </div>
        <div>
          <Label htmlFor="description">
            Description{" "}
            <span className="text-muted-foreground text-sm">(optional)</span>
          </Label>
          <Textarea
            id="description"
            placeholder="Enter tag description..."
            {...register("description")}
          />
          {errors.description ? (
            <p className="mt-1 text-destructive text-sm">
              {errors.description.message}
            </p>
          ) : null}
        </div>
        <Button disabled={createMutation.status === "executing"} type="submit">
          {createMutation.status === "executing" ? (
            <>
              <Loader className="h-4 w-4 animate-spin" />
              Creating...
            </>
          ) : (
            <>
              <Plus className="h-4 w-4" />
              Create Tag
            </>
          )}
        </Button>
      </form>
    </>
  );
}
