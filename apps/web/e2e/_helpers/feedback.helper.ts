import type { Page } from "@playwright/test";
import { ensureSidebarIsOpen } from "./sidebar.helper";

export async function createFeedbackHelper({
  page,
  feedbackTitle,
  feedbackDescription,
}: {
  page: Page;
  feedbackTitle: string;
  feedbackDescription: string;
}) {
  // Navigate to the dashboard and create feedback
  await page.goto("/en/dashboard", {
    waitUntil: "domcontentloaded",
    timeout: 30_000,
  });

  // Ensure sidebar is open before clicking sidebar elements
  await ensureSidebarIsOpen(page);

  await page.getByTestId("sidebar-user-nav-avatar-button").click();
  await page.getByRole("menuitem", { name: "Feedback" }).click();
  await page.getByTestId("feedback-heading-actions-trigger").click();
  await page.getByRole("button", { name: "Create Feedback" }).click();
  await page.getByTestId("feedback-title-input").fill(feedbackTitle);
  await page.getByTestId("feedback-content-input").fill(feedbackDescription);
  await page.getByTestId("submit-feedback-button").click();

  // Wait for the feedback to be created and get its ID
  await page.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);
  const url = page.url();
  const feedbackId = url.split("/").pop();
  if (!feedbackId) {
    throw new Error("Feedback ID is not defined");
  }
  return feedbackId;
}

export async function adminSetFeedbackVisibilityHelper({
  adminPage,
  feedbackId,
  visibility,
}: {
  adminPage: Page;
  feedbackId: string;
  visibility: "public" | "private";
}) {
  const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
  await feedbackVisibility.waitFor();
  const feedbackActionsDropdownTrigger = feedbackVisibility.getByTestId(
    "feedback-actions-dropdown-button"
  );
  await feedbackActionsDropdownTrigger.waitFor();
  const currentFeedbackVisibility = String(
    await feedbackVisibility.textContent()
  ).toLowerCase();
  if (currentFeedbackVisibility === visibility) {
    throw new Error(`Feedback visibility is already ${visibility}`);
  }

  // it is not the same, so we need to toggle it

  await feedbackActionsDropdownTrigger.click();
  await adminPage.getByTestId("toggle-visibility-dropdown-menu-item").click();
}
