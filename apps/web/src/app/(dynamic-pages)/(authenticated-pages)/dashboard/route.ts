import { type NextRequest, NextResponse } from "next/server";
import { toSiteURL } from "@/utils/helpers";

/**
 * Handles GET request for dashboard routing
 * Redirects to the user dashboard home page
 *
 * @param req - The incoming Next.js server request
 * @returns A redirect response to the user's dashboard
 */
export async function GET(req: NextRequest) {
  // Redirect to the user dashboard home
  return NextResponse.redirect(toSiteURL("/user"));
}
