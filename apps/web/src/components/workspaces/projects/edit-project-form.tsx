"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import type { Tables } from "database/types";
import { useAction } from "next-cool-action/hooks";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import * as z from "zod";
import { SmartSheet } from "@/components/smart-sheet";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Typography } from "@/components/ui/typography-ui";
import { updateProjectAction } from "@/data/user/projects";
import { projectStatusEnum } from "@/utils/zod-schemas/enums/project-status-enum";

const projectFormSchema = z.object({
  name: z.string().min(1, "Project name is required"),
  project_status: projectStatusEnum,
});

type ProjectFormValues = z.infer<typeof projectFormSchema>;

const statusEmojis = {
  draft: "📝",
  pending_approval: "⏳",
  approved: "🏗️",
  completed: "✅",
} as const;

interface ProjectFormProps {
  project: Tables<"projects"> | null;
  onClose: () => void;
  onSuccess?: () => void;
  isWorkspaceAdmin: boolean;
  canModifyProjects: boolean;
}

export function EditProjectForm({
  project,
  onClose,
  onSuccess,
  isWorkspaceAdmin,
  canModifyProjects,
}: ProjectFormProps) {
  const [isSubmitting, setIsSubmitting] = useState(false);

  const form = useForm<ProjectFormValues>({
    resolver: zodResolver(projectFormSchema),
    defaultValues: project
      ? {
          name: project.name,
          project_status: project.project_status,
        }
      : undefined,
  });

  const { execute: executeUpdate } = useAction(updateProjectAction, {
    onSuccess: () => {
      toast.success("Project updated successfully");
      onSuccess?.();
      onClose();
    },
    onError: (error) => {
      toast.error(error.error?.serverError || "Failed to update project");
    },
    onSettled: () => {
      setIsSubmitting(false);
    },
  });

  const onSubmit = async (values: ProjectFormValues) => {
    if (!project) return;

    setIsSubmitting(true);
    await executeUpdate({
      projectId: project.id,
      ...values,
    });
  };

  return (
    <SmartSheet
      className="md:max-w-[540px]!"
      onOpenChange={onClose}
      open={!!project}
    >
      <div className="p-2">
        <div className="mb-8">
          <Typography.H2>
            {canModifyProjects ? "Edit Project" : "View Project"}
          </Typography.H2>
          <Typography.Subtle>
            {canModifyProjects
              ? "Edit project details and status."
              : "View project details. You have read-only access."}
          </Typography.Subtle>
        </div>
        <Form {...form}>
          <form className="space-y-6" onSubmit={form.handleSubmit(onSubmit)}>
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Project Name</FormLabel>
                  <FormControl>
                    <Input
                      placeholder="Enter project name"
                      {...field}
                      disabled={!canModifyProjects}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="project_status"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Status</FormLabel>
                  <FormDescription className="mb-2 text-muted-foreground text-sm">
                    {isWorkspaceAdmin
                      ? "As a workspace admin, you can modify the project status"
                      : "Only workspace admins and owners can modify the project status"}
                  </FormDescription>
                  <Select
                    defaultValue={field.value}
                    disabled={!(isWorkspaceAdmin && canModifyProjects)}
                    onValueChange={field.onChange}
                  >
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select project status" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {projectStatusEnum.options.map((status) => (
                        <SelectItem key={status} value={status}>
                          {statusEmojis[status]}{" "}
                          {status.charAt(0).toUpperCase() +
                            status.slice(1).replace("_", " ")}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {!isWorkspaceAdmin && project && (
              <FormItem>
                <FormLabel>Status</FormLabel>
                <p className="mb-2 text-muted-foreground text-sm">
                  Only workspace admins and owners can modify the project status
                </p>
                <div className="flex items-center gap-2 rounded-md border p-2">
                  {statusEmojis[project.project_status]}{" "}
                  {project.project_status.charAt(0).toUpperCase() +
                    project.project_status.slice(1).replace("_", " ")}
                </div>
              </FormItem>
            )}

            {canModifyProjects && (
              <div className="flex justify-end space-x-4">
                <Button onClick={onClose} type="button" variant="outline">
                  Cancel
                </Button>
                <Button disabled={isSubmitting} type="submit">
                  {isSubmitting ? "Saving..." : "Save Changes"}
                </Button>
              </div>
            )}
          </form>
        </Form>
      </div>
    </SmartSheet>
  );
}
