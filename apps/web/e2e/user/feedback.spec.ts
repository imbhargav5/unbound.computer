import { expect, test } from "@playwright/test";
import Chance from "chance";
import { ensureSidebarIsOpen } from "../_helpers/sidebar.helper";

const chance = new Chance();

test.describe
  .serial("Users can submit and view submitted feedback", () => {
    let feedbackId: string | undefined;
    const feedbackTitle = `Test Feedback ${chance.word()}_${Date.now()}`;
    const feedbackDescription = chance.sentence();

    test("User can open feedback dialog and submit feedback", async ({
      page,
    }) => {
      // Navigate to the dashboard
      await page.goto("/en/dashboard", {
        waitUntil: "domcontentloaded",
        timeout: 30_000,
      });
      await page.waitForLoadState("domcontentloaded", { timeout: 10_000 });

      // Ensure sidebar is open before clicking sidebar elements
      await ensureSidebarIsOpen(page);

      await page.getByTestId("sidebar-user-nav-avatar-button").click();
      await page.getByRole("menuitem", { name: "Feedback" }).click();
      await page.getByTestId("feedback-heading-actions-trigger").click();
      await page.getByRole("button", { name: "Create Feedback" }).click();
      await page.getByTestId("feedback-title-input").fill(feedbackTitle);
      await page.getByTestId("feedback-title-input").press("Tab");
      await page
        .getByTestId("feedback-content-input")
        .fill(feedbackDescription);
      await page.getByTestId("submit-feedback-button").click();
      await expect(
        page.getByRole("heading", { name: feedbackTitle })
      ).toBeVisible();

      // Submit the feedback

      // Wait for the success toast
      await page.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);
      const url = await page.url();
      feedbackId = url.split("/").pop();
      expect(feedbackId).toBeDefined();
      if (!feedbackId) {
        throw new Error("Feedback ID not found");
      }
    });

    test("Created feedback is visible on the feedback list page", async ({
      page,
    }) => {
      // Navigate to the feedback page
      await page.goto("/en/feedback");

      // Check if the recently created feedback is visible
      await expect(page.getByText(feedbackTitle)).toBeVisible();
      await expect(page.getByText(feedbackDescription)).toBeVisible();
    });

    test("User can view feedback details", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto(`/en/feedback/${feedbackId}`);

      // Wait for the feedback details page to load
      await page.getByText(feedbackTitle).waitFor();

      // Check if the feedback details are visible
      await expect(page.getByText(feedbackDescription)).toBeVisible();
    });

    test("User can add a comment to feedback and view it", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto(`/en/feedback/${feedbackId}`, {
        waitUntil: "domcontentloaded",
      });

      const commentText = `Test comment ${chance.word()}`;

      await page
        .getByPlaceholder("Share your thoughts or ask a question...")
        .fill(commentText);
      const postCommentButton = page.getByRole("button", {
        name: "Post Comment",
      });
      // wait for not disabled
      await expect(postCommentButton).not.toBeDisabled();
      await postCommentButton.click();

      // Wait for the comment to be visible
      await page.getByText(commentText).waitFor();
    });

    test("User can upvote a feedback item", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto(`/en/feedback/${feedbackId}`);

      const upvoteButton = page.getByTestId("upvote-button");
      await upvoteButton.waitFor();

      // Get initial state - button should not have text-primary class initially
      const initialClasses = await upvoteButton.getAttribute("class");
      const wasUpvoted = initialClasses?.includes("text-primary") ?? false;

      // Click to upvote
      await upvoteButton.click();

      // Verify the button state changed (optimistic update is instant)
      const updatedClasses = await upvoteButton.getAttribute("class");
      const isNowUpvoted = updatedClasses?.includes("text-primary") ?? false;
      expect(isNowUpvoted).toBe(!wasUpvoted);
    });

    test("User can remove their upvote", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto(`/en/feedback/${feedbackId}`);

      const upvoteButton = page.getByTestId("upvote-button");
      await upvoteButton.waitFor();

      // Get current upvote state
      const currentClasses = await upvoteButton.getAttribute("class");
      const isCurrentlyUpvoted =
        currentClasses?.includes("text-primary") ?? false;

      // If not upvoted, upvote first
      if (!isCurrentlyUpvoted) {
        await upvoteButton.click();
        // Wait a moment for the optimistic update
        await page.waitForTimeout(100);
      }

      // Now click to remove upvote
      await upvoteButton.click();

      // Verify the button state changed to not upvoted (optimistic update is instant)
      const updatedClasses = await upvoteButton.getAttribute("class");
      const isStillUpvoted = updatedClasses?.includes("text-primary") ?? false;
      expect(isStillUpvoted).toBe(false);
    });
  });
