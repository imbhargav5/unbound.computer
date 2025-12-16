// @src/e2e/_helpers/create-feedback.helper.ts
// NOTE: This helper is currently not used in any tests. It has been updated to match
// the current implementation in case it's needed in the future.
import { expect, type Page } from "@playwright/test";
import { ensureSidebarIsOpen } from "./sidebar.helper";

export async function createFeedbackHelper(
  page: Page,
  title: string,
  content: string
): Promise<void> {
  await page.goto("/dashboard", {
    waitUntil: "domcontentloaded",
    timeout: 30_000,
  });
  await page.waitForLoadState("domcontentloaded", { timeout: 10_000 });

  // Ensure sidebar is open before clicking sidebar elements
  await ensureSidebarIsOpen(page);

  // Click on user avatar in sidebar to open dropdown
  await page.getByTestId("sidebar-user-nav-avatar-button").click();

  // Click on "Feedback" menu item
  await page.getByRole("menuitem", { name: "Feedback" }).click();

  // Click on the heading actions trigger to open the feedback creation dialog
  await page.getByTestId("feedback-heading-actions-trigger").click();
  await page.getByRole("button", { name: "Create Feedback" }).click();

  // Fill in the feedback form
  await page.getByTestId("feedback-title-input").fill(title);
  await page.getByTestId("feedback-content-input").fill(content);

  // Submit the feedback
  await page.getByTestId("submit-feedback-button").click();

  // Wait for navigation to the feedback detail page
  await page.waitForURL(/\/feedback\/[a-zA-Z0-9-]+$/);
  await expect(page.getByRole("heading", { name: title })).toBeVisible();
}
