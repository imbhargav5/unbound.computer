import type { Page } from "@playwright/test";
import { match } from 'path-to-regexp';

const matcher = match('/:organizationId');
function getIsOrganizationPath(urlString: string) {
  console.log(urlString);
  if (!urlString.startsWith('/s-')) {
    return false;
  }
  return matcher(urlString);
}

export async function extractOrganizationIdFromUrl({
  page,
}: {
  page: Page;
}): Promise<string> {

  let organizationId: string | undefined;
  await page.waitForURL((url) => {
    const isOrganizationPath = getIsOrganizationPath(url.pathname)
    if (isOrganizationPath) {
      if (isOrganizationPath.params['organizationId']) {
        organizationId = isOrganizationPath.params['organizationId'];
        return true;
      } else {
        return false;
      }

    }
    return false;
  });

  if (!organizationId) {
    throw new Error(`Organization slug doesn't exist`);
  }
  return organizationId;
}

export async function dashboardDefaultOrganizationIdHelper({
  page,
}: {
  page: Page;
}): Promise<string> {
  await page.goto("/dashboard");
  return extractOrganizationIdFromUrl({ page });
}
