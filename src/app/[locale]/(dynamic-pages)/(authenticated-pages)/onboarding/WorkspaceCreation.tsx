import { Button } from "@/components/ui/button";
import {
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createWorkspaceAction } from "@/data/user/workspaces";
import { generateWorkspaceSlug } from "@/lib/utils";
import {
  CreateWorkspaceSchema,
  createWorkspaceSchema,
} from "@/utils/zod-schemas/workspaces";
import { zodResolver } from "@hookform/resolvers/zod";
import { useAction } from "next-safe-action/hooks";
import { useRef } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";

type WorkspaceCreationProps = {
  onSuccess: () => void;
};

export function WorkspaceCreation({ onSuccess }: WorkspaceCreationProps) {
  const {
    register,
    handleSubmit,
    setValue,
    formState: { errors, isValid },
  } = useForm<CreateWorkspaceSchema>({
    resolver: zodResolver(createWorkspaceSchema),
  });
  const toastRef = useRef<string | number | undefined>(undefined);
  const { execute: createWorkspaceExecute, isPending } = useAction(
    createWorkspaceAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Creating workspace...", {
          description: "Please wait while we create your workspace.",
        });
      },
      onSuccess: () => {
        toast.success("Workspace created!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        onSuccess();
      },
      onError: (error) => {
        toast.error("Failed to create workspace.", {
          description: String(error),
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    },
  );

  const onSubmit = (data: CreateWorkspaceSchema) => {
    createWorkspaceExecute({
      name: data.name,
      slug: data.slug,
      workspaceType: "solo",
      isOnboardingFlow: true,
    });
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <CardHeader>
        <CardTitle>Create Your Personal Workspace</CardTitle>
        <CardDescription>Set up your first workspace.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="workspaceTitle">Workspace Name</Label>
          <Input
            id="workspaceTitle"
            {...register("name")}
            placeholder="Enter workspace name"
            onChange={(e) => {
              setValue("name", e.target.value, { shouldValidate: true });
              setValue("slug", generateWorkspaceSlug(e.target.value), {
                shouldValidate: true,
              });
            }}
          />
          {errors.name && (
            <p className="text-sm text-destructive">{errors.name.message}</p>
          )}
        </div>
      </CardContent>
      <CardFooter>
        <Button
          type="submit"
          className="w-full"
          disabled={isPending || !isValid}
        >
          {isPending ? "Creating..." : "Create Workspace"}
        </Button>
      </CardFooter>
    </form>
  );
}
