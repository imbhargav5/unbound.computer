import { Button } from "@/components/ui/button";
import { CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createOrganization } from "@/data/user/organizations";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { generateSlug } from "@/lib/utils";
import { CreateOrganizationSchema, createOrganizationSchema } from "@/utils/zod-schemas/organization";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";




type OrganizationCreationProps = {
  onSuccess: () => void;
};

export function OrganizationCreation({ onSuccess }: OrganizationCreationProps) {
  const { register, handleSubmit, setValue, formState: { errors, isValid } } = useForm<CreateOrganizationSchema>({
    resolver: zodResolver(createOrganizationSchema),
  });

  const createOrgMutation = useSAToastMutation(async ({ organizationTitle, organizationSlug }: CreateOrganizationSchema) => {
    return createOrganization(organizationTitle, organizationSlug, { isOnboardingFlow: true })
  }, {
    onSuccess: () => {
      onSuccess();
    },
    dismissOnSuccess: true,
    successMessage: "Organization created!",
    errorMessage: err => {
      console.log(err);
      return "Failed to create organization"
    },
    loadingMessage: "Creating organization...",
  });

  const onSubmit = (data: CreateOrganizationSchema) => {
    console.log(data);
    createOrgMutation.mutate(data);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <CardHeader>
        <CardTitle>Create Your Organization</CardTitle>
        <CardDescription>Set up your first organization.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="organizationTitle">Organization Name</Label>
          <Input
            id="organizationTitle"
            {...register("organizationTitle")}
            placeholder="Enter organization name"
            onChange={(e) => {
              setValue("organizationTitle", e.target.value, { shouldValidate: true });
              setValue("organizationSlug", generateSlug(e.target.value, { withNanoIdSuffix: true }), { shouldValidate: true });
            }}
          />
          {errors.organizationTitle && (
            <p className="text-sm text-destructive">{errors.organizationTitle.message}</p>
          )}
        </div>
        <div className="space-y-2">
          <Label htmlFor="organizationSlug">Organization Slug</Label>
          <Input
            id="organizationSlug"
            {...register("organizationSlug")}
            placeholder="organization-slug"
          />
          {errors.organizationSlug && (
            <p className="text-sm text-destructive">{errors.organizationSlug.message}</p>
          )}
        </div>
      </CardContent>
      <CardFooter>
        <Button
          type="submit"
          className="w-full"
          disabled={createOrgMutation.isLoading || !isValid}
        >
          {createOrgMutation.isLoading ? "Creating..." : "Create Organization"}
        </Button>
      </CardFooter>
    </form>
  );
}
