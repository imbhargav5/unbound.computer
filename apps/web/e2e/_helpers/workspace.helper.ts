import type { Page } from "@playwright/test";

/**
 * Extract workspace slug from the current URL.
 * All workspaces use the path format: /workspace/{slug}/...
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
  slug: string;
}): Promise<{
  workspaceId: string;
  workspaceSlug: string;
}> {
  // Use slug to find the specific workspace-details element to avoid race conditions
  // during React concurrent rendering where multiple elements may exist
  const selector = `[data-testid="workspace-details"][data-workspace-slug="${slug}"]`;

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

  // Extract slug from URL
  const slug = extractSlugFromUrl(page.url());
  if (!slug) {
    throw new Error("Could not extract workspace slug from URL");
  }

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
}: {
  page: Page;
  area: "home" | "settings" | "members" | "billing" | "settings/members";
  workspaceSlug: string;
}): Promise<void> {
  const areaPath = area.startsWith("/") ? area : `/${area}`;
  await page.goto(`/workspace/${workspaceSlug}${areaPath}`, {
    waitUntil: "domcontentloaded",
  });
}
