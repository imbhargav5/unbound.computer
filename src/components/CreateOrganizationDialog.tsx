"use client";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createOrganization } from "@/data/user/organizations";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { generateSlug } from "@/lib/utils";
import { CreateOrganizationSchema, createOrganizationSchema } from "@/utils/zod-schemas/organization";
import { zodResolver } from "@hookform/resolvers/zod";
import { Network } from "lucide-react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";

type CreateOrganizationDialogProps = {
  variant?: "default" | "outline" | "ghost";
  className?: string;
  isDialogOpen: boolean;
  setIsDialogOpen: (isOpen: boolean) => void;
};

export function CreateOrganizationDialog({
  variant,
  className,
  isDialogOpen,
  setIsDialogOpen,
}: CreateOrganizationDialogProps) {
  const router = useRouter()
  const { mutate: createOrg, isLoading: isCreatingOrg } = useSAToastMutation(
    async ({
      organizationTitle,
      organizationSlug,
    }: { organizationTitle: string; organizationSlug: string }) => {
      const orgSlug = await createOrganization(
        organizationTitle,
        organizationSlug,
        {
          isOnboardingFlow: true,
        },
      );
      return orgSlug;
    },
    {
      successMessage: "Organization created!",
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to create organization ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to create organization';
        }
      },
      onSuccess: (response) => {
        if (response.status === "success" && response.data) {
          router.push(`/${response.data}`);
        }
      },
    },
  );

  const onSubmit = (data: CreateOrganizationSchema) => {
    createOrg({
      organizationTitle: data.organizationTitle,
      organizationSlug: data.organizationSlug,
    });
  };

  const { register, watch, formState: { errors }, handleSubmit, setValue } =
    useForm<CreateOrganizationSchema>({
      resolver: zodResolver(createOrganizationSchema),
      defaultValues: {
        organizationTitle: "",
        organizationSlug: "",
      },
    });

  return (
    <>
      <Dialog
        open={isDialogOpen}
        data-testid="create-organization-dialog"
        onOpenChange={setIsDialogOpen}
      >
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
          <form onSubmit={handleSubmit(onSubmit)} data-testid="create-organization-form">
            <div className="mb-8 space-y-2">
              <div>
                <Label>Organization Name</Label>
                <Input
                  {...register("organizationTitle")}
                  className="mt-1.5 shadow appearance-none border h-11 rounded-lg w-full py-2 px-3 focus:ring-0 leading-tight focus:outline-none focus:shadow-outline text-base"
                  id="name"
                  type="text"
                  onChange={(e) => {
                    setValue("organizationSlug", generateSlug(e.target.value), { shouldValidate: true });
                    setValue("organizationTitle", e.target.value, { shouldValidate: true });
                  }}
                  placeholder="Organization Name"
                  disabled={isCreatingOrg}
                />
              </div>

              <div>
                <Label>Organization Slug</Label>
                <Input
                  {...register("organizationSlug")}
                  className="mt-1.5 shadow appearance-none border h-11 rounded-lg w-full py-2 px-3 focus:ring-0 leading-tight focus:outline-none focus:shadow-outline text-base"
                  id="slug"
                  type="text"
                  placeholder="Organization Slug"
                />
              </div>

            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                disabled={isCreatingOrg}
                className="w-full"
                onClick={() => {
                  setIsDialogOpen(false);
                }}
              >
                Cancel
              </Button>
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
