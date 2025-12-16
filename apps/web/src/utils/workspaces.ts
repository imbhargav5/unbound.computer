import urlJoin from "url-join";
import type { Enum, SlimWorkspace } from "@/types";

export function getWorkspaceSubPath(
  workspace: SlimWorkspace,
  subPath: string
): string;
export function getWorkspaceSubPath(
  workspaceSlug: string,
  subPath: string
): string;
export function getWorkspaceSubPath(
  arg: SlimWorkspace | string,
  subPath: string
): string {
  if (typeof arg === "object" && "slug" in arg) {
    return urlJoin(`/workspace/${arg.slug}`, subPath);
  }
  return urlJoin(`/workspace/${arg}`, subPath);
}

export function getIsWorkspaceAdmin(
  workspaceRole: Enum<"workspace_member_role_type">
) {
  return workspaceRole === "admin" || workspaceRole === "owner";
}

export function getIsReadOnlyMember(
  workspaceRole: Enum<"workspace_member_role_type">
) {
  return workspaceRole === "readonly";
}
