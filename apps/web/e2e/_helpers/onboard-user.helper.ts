import { expect, type Page } from "@playwright/test";
import { matchPathAndExtractWorkspaceInfo } from "./workspace.helper";

export async function onboardUserHelper({
  page,
  name,
}: {
  page: Page;
  name: string;
}) {
  const acceptTermsButton = page.getByTestId("accept-terms-button");
  await acceptTermsButton.click();

  // Profile Update
  const fullNameInput = page.getByTestId("full-name-input");
  await expect(fullNameInput).toBeVisible();
  await fullNameInput.fill(name);

  const saveProfileButton = page.getByTestId("save-profile-button");
  await saveProfileButton.click();

  const createWorkspaceButton = page.getByTestId("finish-setup-button");
  await createWorkspaceButton.click();

  // Wait for and click the "Go to Dashboard" button on success screen
  const goToDashboardButton = page.getByTestId("go-to-dashboard-button");
  await goToDashboardButton.waitFor({ state: "visible" });
  await goToDashboardButton.click();

  const { workspaceId } = await matchPathAndExtractWorkspaceInfo({ page });
  expect(workspaceId).not.toBeNull();
}
