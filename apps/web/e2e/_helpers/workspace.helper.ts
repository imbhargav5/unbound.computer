import type { Page } from "@playwright/test";

/**
 * Extract workspace slug from the current URL.
 * Handles both team workspaces (/workspace/{slug}/...) and solo workspaces (/home, /settings, etc.)
 */
function extractSlugFromUrl(url: string): string | null {
  const match = url.match(/\/workspace\/([^/]+)/);
  return match ? match[1] : null;
}

export async function extractInfoFromWorkspaceDashboard({
  page,
  slug,
}: {
  page: Page;
  slug: string | null;
}): Promise<{
  workspaceId: string;
  workspaceSlug: string;
}> {
  // Use slug to find the specific workspace-details element to avoid race conditions
  // during React concurrent rendering where multiple elements may exist
  const selector = slug
    ? `[data-testid="workspace-details"][data-workspace-slug="${slug}"]`
    : '[data-testid="workspace-details"][data-workspace-membership-type="solo"]';

  const workspaceDetails = page.locator(selector).first();
  await workspaceDetails.waitFor({ state: "attached", timeout: 10_000 });

  const workspaceId = await workspaceDetails.getAttribute("data-workspace-id");
  const workspaceSlug = await workspaceDetails.getAttribute(
    "data-workspace-slug"
  );

  if (!(workspaceId && workspaceSlug)) {
    throw new Error("Workspace information not found");
  }

  return { workspaceId, workspaceSlug };
}

export async function matchPathAndExtractWorkspaceInfo({
  page,
}: {
  page: Page;
}): Promise<{
  workspaceId: string;
  workspaceSlug: string;
}> {
  // Wait for the URL to end with '/home'
  await page.waitForURL((url) => url.pathname.endsWith("/home"));
  // Wait for network idle to ensure page transition is complete
  await page.waitForLoadState("domcontentloaded");

  // Extract slug from URL to match the correct workspace component
  const slug = extractSlugFromUrl(page.url());

  return await extractInfoFromWorkspaceDashboard({ page, slug });
}

export async function getDefaultWorkspaceInfoHelper({
  page,
}: {
  page: Page;
}): Promise<{
  workspaceId: string;
  workspaceSlug: string;
}> {
  await page.goto("/dashboard");
  return await matchPathAndExtractWorkspaceInfo({ page });
}

export async function goToWorkspaceArea({
  page,
  area,
  workspaceSlug,
  workspaceType,
}: {
  page: Page;
  area: "home" | "settings" | "members" | "billing" | "settings/members";
  workspaceSlug: string;
  workspaceType: "solo" | "team";
}): Promise<void> {
  const areaPath = area.startsWith("/") ? area : `/${area}`;
  if (workspaceType === "solo") {
    await page.goto(areaPath, {
      waitUntil: "domcontentloaded",
    });
  } else {
    await page.goto(`/workspace/${workspaceSlug}${areaPath}`, {
      waitUntil: "domcontentloaded",
    });
  }
}
