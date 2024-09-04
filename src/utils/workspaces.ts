import { SlimWorkspace } from "@/types";
import urlJoin from "url-join";

export function getWorkspaceSubPath(workspace: SlimWorkspace, subPath: string) {
  if (workspace.membershipType === 'solo') {
    return urlJoin('/', subPath);
  }
  return urlJoin(`/workspace/${workspace.slug}`, subPath);
}
