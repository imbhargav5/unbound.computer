"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { Loader, Plus } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useEffect, useRef } from "react";
import { useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import { z } from "zod";
import { FormInput } from "@/components/form-components/form-input";
import { FormSelect } from "@/components/form-components/form-select";
import { FormTextarea } from "@/components/form-components/form-textarea";
import { Button } from "@/components/ui/button";
import { Form } from "@/components/ui/form";
import { createBlogPostAction } from "@/data/admin/marketing-blog";

const createBlogPostFormSchema = z.object({
  title: z.string().min(1, "Title is required"),
  slug: z.string().min(1, "Slug is required"),
  summary: z.string().min(1, "Summary is required"),
  status: z.enum(["draft", "published"]),
});

type FormData = z.infer<typeof createBlogPostFormSchema>;

export function CreateBlogPostForm() {
  const toastRef = useRef<string | number | undefined>(undefined);

  const createMutation = useAction(createBlogPostAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating blog post...", {
        description: "Please wait while we create the post.",
      });
    },
    onNavigation: () => {
      toast.success("Blog post created!", {
        description: "Redirecting to edit page...",
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to create blog post: ${error.serverError || "Unknown error"}`,
        {
          description: "Please try again.",
          id: toastRef.current,
        }
      );
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof createBlogPostFormSchema
  >(createMutation.result.validationErrors, { joinBy: "\n" });

  const form = useForm<FormData>({
    resolver: zodResolver(createBlogPostFormSchema),
    defaultValues: {
      title: "",
      slug: "",
      summary: "",
      status: "draft",
    },
    errors: hookFormValidationErrors,
  });

  const { handleSubmit, control, setValue, watch } = form;

  const currentTitle = watch("title");

  useEffect(() => {
    if (currentTitle) {
      setValue(
        "slug",
        slugify(currentTitle, {
          lower: true,
          strict: true,
          replacement: "-",
        })
      );
    }
  }, [currentTitle, setValue]);

  const onSubmit = async (data: FormData) => {
    createMutation.execute({
      title: data.title,
      slug: data.slug,
      summary: data.summary,
      content: "",
      stringified_json_content: JSON.stringify({}),
      stringified_seo_data: JSON.stringify({}),
      status: data.status,
    });
  };

  return (
    <>
      <div className="mb-6">
        <p className="text-muted-foreground text-sm">Create New</p>
        <h1 className="font-bold text-3xl">Blog Post</h1>
      </div>
      <Form {...form}>
        <form
          className="flex flex-col gap-6 md:flex-row"
          onSubmit={handleSubmit(onSubmit)}
        >
          {/* Main content column */}
          <div className="grow space-y-6">
            {/* Title */}
            <FormInput
              control={control}
              description="The title of your blog post."
              id="title"
              inputProps={{ placeholder: "Enter blog post title" }}
              label="Title"
              name="title"
            />

            {/* Slug */}
            <FormInput
              control={control}
              description="URL-friendly version of the title (auto-generated)."
              id="slug"
              inputProps={{ placeholder: "blog-post-slug" }}
              label="Slug"
              name="slug"
            />

            {/* Summary */}
            <FormTextarea
              control={control}
              description="A brief summary of the blog post."
              id="summary"
              label="Summary"
              name="summary"
            />

            <Button
              disabled={createMutation.status === "executing"}
              type="submit"
            >
              {createMutation.status === "executing" ? (
                <>
                  <Loader className="h-4 w-4 animate-spin" />
                  Creating...
                </>
              ) : (
                <>
                  <Plus className="h-4 w-4" />
                  Create Blog Post
                </>
              )}
            </Button>
          </div>

          {/* Sidebar */}
          <div className="order-first space-y-4 md:order-none md:w-72 md:shrink-0">
            {/* Status */}
            <FormSelect
              control={control}
              description="Set the initial status of the blog post."
              id="status"
              label="Status"
              name="status"
              options={[
                { label: "Draft", value: "draft" },
                { label: "Published", value: "published" },
              ]}
              placeholder="Select status"
            />
          </div>
        </form>
      </Form>
    </>
  );
}
