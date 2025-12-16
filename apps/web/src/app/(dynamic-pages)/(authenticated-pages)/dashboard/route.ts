import { type NextRequest, NextResponse } from "next/server";
import { getMaybeDefaultWorkspace } from "@/data/user/workspaces";
import { toSiteURL } from "@/utils/helpers";
import { getWorkspaceSubPath } from "@/utils/workspaces";

/**
 * Handles GET request for dashboard routing
 * Attempts to redirect user to their default/initial workspace home page
 *
 * @param req - The incoming Next.js server request
 * @returns A redirect response to the user's workspace home or error page
 */
export async function GET(req: NextRequest) {
  // Retrieve the user's default or first available workspace
  const initialWorkspace = await getMaybeDefaultWorkspace();

  // If no workspace is found, redirect to error page
  if (!initialWorkspace) {
    return NextResponse.redirect(toSiteURL("/oops"));
  }

  // Log the membership type for debugging purposes
  console.log("initialWorkspace", initialWorkspace.workspace.membershipType);

  // Construct the redirect URL to the workspace home page
  return NextResponse.redirect(
    new URL(getWorkspaceSubPath(initialWorkspace.workspace, "/home"), req.url)
  );
}
