"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useEffect, useRef } from "react";
import { useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { updateMarketingTagAction } from "@/data/admin/marketing-tags";
import type { DBTable } from "@/types";

const editTagSchema = z.object({
  id: z.uuid(),
  name: z.string().min(1, "Name is required"),
  slug: z.string().min(1, "Slug is required"),
  description: z.string().optional(),
});

type EditTagFormProps = {
  tag: DBTable<"marketing_tags">;
};

export const EditTagForm: React.FC<EditTagFormProps> = ({ tag }) => {
  const toastRef = useRef<string | number | undefined>(undefined);
  const router = useRouter();

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
    setValue,
  } = useForm<z.infer<typeof editTagSchema>>({
    resolver: zodResolver(editTagSchema),
    defaultValues: {
      id: tag.id,
      name: tag.name,
      slug: tag.slug,
      description: tag.description ?? "",
    },
  });

  const watchName = watch("name");

  useEffect(() => {
    if (watchName) {
      setValue("slug", slugify(watchName, { lower: true, strict: true }));
    }
  }, [watchName, setValue]);

  const updateTagMutation = useAction(updateMarketingTagAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating tag...", {
        description: "Please wait while we update the tag.",
      });
    },
    onSuccess: () => {
      toast.success("Tag updated successfully", { id: toastRef.current });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to update tag: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
  });

  const onSubmit = (data: z.infer<typeof editTagSchema>) => {
    updateTagMutation.execute(data);
  };

  return (
    <form className="space-y-6" onSubmit={handleSubmit(onSubmit)}>
      <div>
        <Label htmlFor="name">Name</Label>
        <Input id="name" {...register("name")} />
        {errors.name ? (
          <p className="mt-1 text-red-500 text-sm">{errors.name.message}</p>
        ) : null}
      </div>
      <div>
        <Label htmlFor="slug">Slug</Label>
        <Input id="slug" {...register("slug")} />
        {errors.slug ? (
          <p className="mt-1 text-red-500 text-sm">{errors.slug.message}</p>
        ) : null}
      </div>
      <div>
        <Label htmlFor="description">Description</Label>
        <Textarea id="description" {...register("description")} />
        {errors.description ? (
          <p className="mt-1 text-red-500 text-sm">
            {errors.description.message}
          </p>
        ) : null}
      </div>
      <Button disabled={updateTagMutation.status === "executing"} type="submit">
        {updateTagMutation.status === "executing"
          ? "Updating..."
          : "Update Tag"}
      </Button>
    </form>
  );
};
