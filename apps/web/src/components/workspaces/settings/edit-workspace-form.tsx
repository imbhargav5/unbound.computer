"use client";

import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { type SubmitHandler, useForm } from "react-hook-form";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { T } from "@/components/ui/typography-ui";
import { updateWorkspaceInfoAction } from "@/data/user/workspaces"; // Assuming this action exists
import { generateWorkspaceSlug } from "@/lib/utils";
import { zodResolver } from "@/lib/zod-resolver";
import type { WorkspaceWithMembershipType } from "@/types";
import {
  type CreateWorkspaceFormSchema,
  createWorkspaceFormSchema,
} from "@/utils/zod-schemas/workspaces";

type EditFormProps = {
  workspace: WorkspaceWithMembershipType;
};

export function EditWorkspaceForm({ workspace }: EditFormProps) {
  const router = useRouter();

  const { register, handleSubmit, formState, setValue } =
    useForm<CreateWorkspaceFormSchema>({
      resolver: zodResolver(createWorkspaceFormSchema),
      defaultValues: {
        name: workspace.name,
        slug: workspace.slug,
      },
    });

  const { execute, status } = useAction(updateWorkspaceInfoAction, {
    onError: ({ error }) => {
      const errorMessage =
        error.serverError ?? "Failed to update workspace information";
      toast.error(errorMessage);
    },
  });

  const onSubmit: SubmitHandler<CreateWorkspaceFormSchema> = (data) => {
    execute({
      workspaceId: workspace.id,
      name: data.name,
      slug: data.slug ?? generateWorkspaceSlug(data.name),
      workspaceMembershipType: workspace.membershipType,
    });
  };

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <T.H4>Edit Workspace Title</T.H4>
        <T.P className="text-muted-foreground">
          This is the title that will be displayed on the workspace page.
        </T.P>
      </div>
      <form
        className="max-w-md space-y-4"
        data-testid="edit-workspace-title-form"
        onSubmit={handleSubmit(onSubmit)}
      >
        <Input
          data-testid="edit-workspace-title-input"
          id="organization-title"
          type="text"
          {...register("name")}
          onChange={(e) => {
            setValue("name", e.target.value, { shouldValidate: true });
            setValue("slug", generateWorkspaceSlug(e.target.value), {
              shouldValidate: true,
            });
          }}
        />
        <div className="space-y-2">
          <T.H4>Edit Workspace Slug</T.H4>
          <T.P className="text-muted-foreground">
            This is the slug that will be displayed in the URL.
          </T.P>
        </div>
        <Input
          data-testid="edit-workspace-slug-input"
          id="organization-slug"
          type="text"
          {...register("slug")}
        />
        <div className="inline-block">
          <Button
            disabled={status === "executing" || !formState.isValid}
            id="update-workspace-title-button"
            type="submit"
          >
            {status === "executing" ? "Updating..." : "Update"}
          </Button>
        </div>
      </form>
    </div>
  );
}
