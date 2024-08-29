import { expect, test } from "@playwright/test";
import { dashboardDefaultOrganizationIdHelper } from "../_helpers/dashboard-default-organization-id.helper";

test.describe("Organization", () => {
  let organizationSlug: string;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    organizationSlug = await dashboardDefaultOrganizationIdHelper({ page });
    await context.close();
  });

  test("should navigate to organization settings", async ({ page }) => {
    await page.goto(`/${organizationSlug}/settings`);
    await expect(page.getByRole("heading", { name: "Edit Organization Title" })).toBeVisible();
  });

  test("should list team members", async ({ page }) => {
    await page.goto(`/${organizationSlug}/settings/members`);
    await expect(page.getByRole("heading", { name: "Team Members" })).toBeVisible();
    await expect(page.getByTestId("members-table")).toBeVisible();
  });

  test.skip("should update organization title and slug", async ({ page }) => {
    await page.goto(`/${organizationSlug}/settings`);

    const newTitle = "Organization Name Updated";
    const titleInput = page.getByTestId("edit-organization-title-input");
    await titleInput.fill(newTitle);

    // Wait for the slug to be automatically generated
    await page.waitForTimeout(500);

    await page.getByRole("button", { name: "Update" }).click();
    await expect(page.getByText("Organization information updated!")).toBeVisible();

    const titleInput2 = page.getByTestId("edit-organization-title-input");
    await expect(titleInput2).toHaveValue(newTitle);
  });
});
