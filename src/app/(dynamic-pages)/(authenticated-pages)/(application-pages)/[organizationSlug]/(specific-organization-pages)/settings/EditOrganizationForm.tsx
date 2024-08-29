"use client";
import { Button } from "@/components/Button";
import { T } from "@/components/ui/Typography";
import { Input } from "@/components/ui/input";
import { updateOrganizationInfo } from "@/data/user/organizations";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { generateOrganizationSlug } from "@/lib/utils";
import { createOrganizationSchema } from "@/utils/zod-schemas/organization";
import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { useForm, type SubmitHandler } from "react-hook-form";

export function EditOrganizationForm({
  initialTitle,
  organizationId,
  initialSlug,
}: {
  initialTitle: string;
  organizationId: string;
  initialSlug: string;
}) {

  const router = useRouter()

  const { register, handleSubmit, formState, setValue } = useForm<{
    organizationTitle: string;
    organizationSlug: string;
  }>({
    resolver: zodResolver(createOrganizationSchema),
    defaultValues: {
      organizationTitle: initialTitle,
      organizationSlug: initialSlug,
    },
  });

  const { mutate, isLoading } = useSAToastMutation(
    async ({ organizationTitle, organizationSlug }: { organizationTitle: string, organizationSlug: string }) => {
      return await updateOrganizationInfo(
        organizationId,
        organizationTitle,
        organizationSlug,
      );
    },
    {
      loadingMessage: "Updating organization information...",
      successMessage: "Organization information updated!",
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update organization information ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return "Failed to update organization information";
        }
      },
      onSuccess(response) {
        if (response.status === "success" && response.data) {
          router.push(`/${response.data.slug}/settings`)
        }
      },
    },
  );

  const onSubmit: SubmitHandler<{
    organizationTitle: string;
    organizationSlug: string;
  }> = (data) => {
    mutate(data);
  };

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <T.H4>Edit Organization Title</T.H4>
        <T.P className="text-muted-foreground">
          This is the title that will be displayed on the organization page.
        </T.P>
      </div>
      <form
        data-testid="edit-organization-title-form"
        onSubmit={handleSubmit(onSubmit)}
        className="space-y-4 max-w-md"
      >
        <Input
          type="text"
          id="organization-title"
          data-testid="edit-organization-title-input"
          {...register("organizationTitle")}
          onChange={(e) => {
            setValue("organizationTitle", e.target.value, { shouldValidate: true });
            setValue("organizationSlug", generateOrganizationSlug(e.target.value), { shouldValidate: true });
          }}
        />
        <div className="space-y-2">
          <T.H4>Edit Organization Slug</T.H4>
          <T.P className="text-muted-foreground">
            This is the slug that will be displayed in the URL.
          </T.P>
        </div>
        <Input

          type="text"
          id="organization-slug"
          data-testid="edit-organization-slug-input"
          {...register("organizationSlug")}
        />
        <div className="inline-block">
          <Button
            disabled={isLoading || !formState.isValid}
            type="submit"
            id="update-organization-title-button"
          >
            {isLoading ? "Updating..." : "Update"}
          </Button>
        </div>
      </form>
    </div>
  );
}
