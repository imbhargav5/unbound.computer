import { expect, test } from "@playwright/test";
import { goToWorkspaceArea, matchPathAndExtractWorkspaceInfo } from "../_helpers/workspace.helper";

test.describe("Workspace", () => {
  let workspaceSlug: string;
  let isSoloWorkspace: boolean;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const workspaceInfo = await matchPathAndExtractWorkspaceInfo({ page });
    workspaceSlug = workspaceInfo.workspaceSlug;
    isSoloWorkspace = workspaceInfo.isSoloWorkspace;
    await context.close();
  });

  test("should navigate to workspace settings", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: 'settings',
      workspaceSlug,
      isSoloWorkspace,
    })
    await expect(page.getByRole("heading", { name: "Edit Workspace Title" })).toBeVisible();
  });

  test("should list team members", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: 'settings/members',
      workspaceSlug,
      isSoloWorkspace,
    })
    await expect(page.getByRole("heading", { name: "Team Members" })).toBeVisible();
    await expect(page.getByTestId("members-table")).toBeVisible();
  });

  test.skip("should update workspace title and slug", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: 'settings',
      workspaceSlug,
      isSoloWorkspace,
    })

    const newTitle = "Workspace Name Updated";
    const titleInput = page.getByTestId("edit-workspace-title-input");
    await titleInput.fill(newTitle);

    // Wait for the slug to be automatically generated
    await page.waitForTimeout(500);

    await page.getByRole("button", { name: "Update" }).click();
    await expect(page.getByText("Workspace information updated!")).toBeVisible();

    const titleInput2 = page.getByTestId("edit-workspace-title-input");
    await expect(titleInput2).toHaveValue(newTitle);
  });
});
