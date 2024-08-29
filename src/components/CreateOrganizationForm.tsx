"use client";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createOrganization } from "@/data/user/organizations";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { generateOrganizationSlug } from "@/lib/utils";
import { CreateOrganizationSchema, createOrganizationSchema } from "@/utils/zod-schemas/organization";
import { zodResolver } from "@hookform/resolvers/zod";
import { Network } from "lucide-react";
import { redirect } from "next/navigation";
import { useForm } from "react-hook-form";

type CreateOrganizationDialogProps = {
  className?: string;
  isDialogOpen: boolean;
};

export function CreateOrganizationForm({
  isDialogOpen,
}: CreateOrganizationDialogProps) {
  const { mutate: createOrg, isLoading: isCreatingOrg } = useSAToastMutation(
    async ({
      organizationTitle,
      organizationSlug,
    }: { organizationTitle: string; organizationSlug: string }) => {
      const orgId = await createOrganization(
        organizationTitle,
        organizationSlug,
        {
          isOnboardingFlow: true,
        },
      );
      return orgId;
    },
    {
      successMessage: "Organization created!",
      errorMessage: "Failed to create organization",
      onSuccess: (orgId) => {
        redirect("/dashboard");
      },
    },
  );

  const onSubmit = (data: CreateOrganizationSchema) => {
    createOrg({
      organizationTitle: data.organizationTitle,
      organizationSlug: data.organizationSlug,
    });
  };

  const { register, formState, handleSubmit, setValue } =
    useForm<CreateOrganizationSchema>({
      resolver: zodResolver(createOrganizationSchema),
      defaultValues: {
        organizationTitle: "",
        organizationSlug: "",
      },
    });

  return (
    <>
      <Dialog open={isDialogOpen} data-testid="create-organization-form">
        <DialogContent>
          <DialogHeader>
            <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 mb-2 rounded-lg">
              <Network className=" w-6 h-6" />
            </div>
            <div className="p-1">
              <DialogTitle className="text-lg">Create Organization</DialogTitle>
              <DialogDescription className="text-base mt-0">
                Create a new organization and get started.
              </DialogDescription>
            </div>
          </DialogHeader>
          <form
            onSubmit={handleSubmit(onSubmit)}
            data-testid="create-organization-form"
          >
            <div className="mb-8 space-y-2">
              <div>
                <Label className="text-muted-foreground">Organization Name</Label>
                <Input
                  {...register("organizationTitle")}
                  required
                  className="mt-1.5 shadow appearance-none border h-11 rounded-lg w-full py-2 px-3 focus:ring-0 text-gray-700 leading-tight focus:outline-none focus:shadow-outline text-base"
                  id="name"
                  type="text"
                  placeholder="Organization Name"
                  onChange={(e) => setValue("organizationTitle", generateOrganizationSlug(e.target.value))}
                  disabled={isCreatingOrg}
                />
              </div>

            </div>
            <div>
              <Label>Organization Slug</Label>
              <Input
                {...register("organizationSlug")}
                required
                className="mt-1.5 shadow appearance-none border h-11 rounded-lg w-full py-2 px-3 focus:ring-0 text-gray-700 leading-tight focus:outline-none focus:shadow-outline text-base"
                disabled
              />
            </div>


            <DialogFooter>
              <Button
                variant="default"
                type="submit"
                className="w-full"
                disabled={isCreatingOrg}
              >
                Create Organization
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
