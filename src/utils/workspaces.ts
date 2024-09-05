import { Enum, SlimWorkspace } from "@/types";
import urlJoin from "url-join";

export function getWorkspaceSubPath(workspace: SlimWorkspace, subPath: string): string;
export function getWorkspaceSubPath(workspaceSlug: Enum<'workspace_membership_type'>, subPath: string): string;
export function getWorkspaceSubPath(arg: SlimWorkspace | Enum<'workspace_membership_type'>, subPath: string): string {
  if (typeof arg === 'object' && 'membershipType' in arg) {
    const workspace = arg as SlimWorkspace;
    if (workspace.membershipType === 'solo') {
      return urlJoin('/', subPath);
    }
    return urlJoin(`/workspace/${workspace.slug}`, subPath);
  }
  return urlJoin(`/workspace/${arg}`, subPath);
}
