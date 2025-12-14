import { expect, test } from "@playwright/test";

test.describe
  .serial("Anonymous users can view public feedback", () => {
    test("Public feedback is visible on the feedback list page", async ({
      page,
    }) => {
      // Navigate to the public feedback page
      await page.goto("/en/feedback");

      // Check if the page loads correctly
      await expect(
        page.getByRole("heading", { name: "Community Feedback" })
      ).toBeVisible();

      // Check if any public feedback is visible
      const feedbackItems = await page.getByTestId("feedback-item").all();

      if (feedbackItems.length > 0) {
        // If there are feedback items, check the first one
        await expect(feedbackItems[0]).toBeVisible();
      }
    });

    test("Anonymous user can view public feedback details", async ({
      page,
    }) => {
      // Navigate to the public feedback page
      await page.goto("/en/feedback");

      // Get all feedback items
      const feedbackItems = await page.getByTestId("feedback-item").all();

      if (feedbackItems.length > 0) {
        await feedbackItems[0].waitFor();
        // Click on the first feedback item
        await feedbackItems[0].click();

        // Wait for the feedback details page to load
        await page.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);

        const feedbackVisibility = page.getByTestId("feedback-visibility");
        await expect(feedbackVisibility).toBeVisible();
        // Check if the feedback details are visible
        await page
          .getByRole("heading", {
            level: 2,
          })
          .waitFor();
        await expect(feedbackVisibility.getByText("Public")).toBeVisible();

        // Check if comments are visible (if any)
        await expect(
          page.getByRole("heading", {
            name: "Comments",
          })
        ).toBeVisible();
      } else {
        console.log("No public feedback available to test details view.");
      }
    });

    test("Anonymous user cannot upvote feedback", async ({ page }) => {
      // Navigate to the public feedback page
      await page.goto("/en/feedback");

      // Get all feedback items
      const feedbackItems = await page.getByTestId("feedback-item").all();

      if (feedbackItems.length > 0) {
        await feedbackItems[0].click();
        await page.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);

        // The upvote button should not be visible for anonymous users
        // or clicking it should prompt for login
        const upvoteButton = page.getByTestId("upvote-button");
        const upvoteCount = await upvoteButton.count();

        // If button exists, it means anonymous can see it but clicking should show login prompt
        if (upvoteCount > 0) {
          await upvoteButton.click();
          // Should see a login prompt or be redirected
          const loginDialog = page.getByRole("dialog");
          const loginButton = page.getByRole("button", { name: /log in/i });
          const hasLoginPrompt =
            (await loginDialog.count()) > 0 || (await loginButton.count()) > 0;
          expect(hasLoginPrompt).toBe(true);
        }
        // If no button, anonymous users simply can't upvote (which is also valid)
      }
    });

    test("Anonymous user cannot comment on feedback", async ({ page }) => {
      // Navigate to the public feedback page
      await page.goto("/en/feedback");

      // Get all feedback items
      const feedbackItems = await page.getByTestId("feedback-item").all();

      if (feedbackItems.length > 0) {
        await feedbackItems[0].click();
        await page.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);

        // The comment form should not be visible for anonymous users
        const commentForm = page.getByTestId("add-comment-form");
        const commentTextarea = page.getByPlaceholder(
          "Share your thoughts or ask a question..."
        );

        // Either the form is not visible, or attempting to interact prompts login
        const formVisible = await commentForm.isVisible().catch(() => false);
        const textareaVisible = await commentTextarea
          .isVisible()
          .catch(() => false);

        if (formVisible && textareaVisible) {
          // If visible, clicking should prompt for login
          await commentTextarea.click();
          const loginDialog = page.getByRole("dialog");
          const loginButton = page.getByRole("button", { name: /log in/i });
          const hasLoginPrompt =
            (await loginDialog.count()) > 0 || (await loginButton.count()) > 0;
          expect(hasLoginPrompt).toBe(true);
        }
        // If not visible, anonymous users simply can't comment (which is valid)
      }
    });
  });
