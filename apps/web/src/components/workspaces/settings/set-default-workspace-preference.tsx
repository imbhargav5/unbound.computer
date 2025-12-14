"use server";

import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { T } from "@/components/ui/typography-ui";
import { getMaybeDefaultWorkspace } from "@/data/user/workspaces";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { SetDefaultWorkspaceButton } from "./set-default-workspace-button";

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <T.H3 className="dark:text-white">Default Workspace</T.H3>
        <T.Subtle className="max-w-lg text-muted-foreground text-sm">
          If you have multiple workspaces, you can set a default organization,
          which will be the organization that you are first taken to when you
          log in.
        </T.Subtle>
      </div>
      {children}
    </div>
  );
}

export async function SetDefaultWorkspacePreference({
  workspaceSlug,
}: {
  workspaceSlug: string;
}) {
  const [defaultWorkspace, workspace] = await Promise.all([
    getMaybeDefaultWorkspace(),
    getCachedWorkspaceBySlug(workspaceSlug),
  ]);
  const isDefaultWorkspace = defaultWorkspace?.workspace.id === workspace.id;
  if (isDefaultWorkspace) {
    return (
      <Wrapper>
        <Button className="pointer-events-none select-none space-x-2">
          <Check className="mr-2 h-4 w-4" />
          <span>This is your default workspace</span>
        </Button>
      </Wrapper>
    );
  }
  return (
    <Wrapper>
      <SetDefaultWorkspaceButton workspaceId={workspace.id} />
    </Wrapper>
  );
}
