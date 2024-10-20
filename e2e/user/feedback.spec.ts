import { expect, test } from "@playwright/test";

test.describe.serial("Users can submit and view submitted feedback", () => {
  let feedbackId: string | undefined = undefined;
  test("User can open feedback dialog and submit feedback", async ({
    page,
  }) => {
    // Navigate to the dashboard
    await page.goto("/en/dashboard");

    // Open user nav dropdown
    await page.getByTestId("user-nav-avatar").click();

    // Click on the feedback link
    await page.getByTestId("feedback-link").click();

    // Wait for the feedback dialog to appear
    const giveFeedbackForm = await page.getByTestId("give-feedback-form");
    const titleInput = await giveFeedbackForm.getByTestId(
      "feedback-title-input",
    );
    const contentInput = await giveFeedbackForm.getByTestId(
      "feedback-content-input",
    );
    const selectTrigger = await giveFeedbackForm.getByRole("combobox");

    // Fill in the feedback form
    await titleInput.fill("Test Feedback Title");
    await contentInput.fill("This is a test feedback content.");
    await selectTrigger.click();
    // wait for listbox
    const listBox = page.getByRole("listbox");
    await listBox.waitFor();
    await listBox.getByText("Feature Request").click();

    // Submit the feedback
    await giveFeedbackForm.getByTestId("submit-feedback-button").click();

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
    await page.goto(`/en/feedback`);

    // Check if the recently created feedback is visible
    await expect(page.getByText("Test Feedback Title")).toBeVisible();
    await expect(
      page.getByText("This is a test feedback content."),
    ).toBeVisible();
  });

  test("User can view feedback details", async ({ page }) => {
    // Navigate to the feedback page
    await page.goto(`/en/feedback/${feedbackId}`);

    // Wait for the feedback details page to load
    await page.getByRole("heading", { name: "Test Feedback Title" }).waitFor();

    // Check if the feedback details are visible
    await expect(
      page.getByText("This is a test feedback content."),
    ).toBeVisible();
    await expect(page.getByText("Feature Request")).toBeVisible();
  });

  test("User can add a comment to feedback and view it", async ({ page }) => {
    // Navigate to the feedback page
    await page.goto(`/en/feedback/${feedbackId}`);

    // Wait for the feedback details page to load
    await page.getByRole("heading", { name: "Test Feedback Title" }).waitFor();

    const randomText = Math.random().toString(36).substring(2, 15);
    const commentText = `This is a test comment ${randomText}.`;

    // Find the comment form
    const addCommentForm = await page.getByTestId("add-comment-form");

    // Type a comment
    await addCommentForm.getByRole("textbox").fill(commentText);

    // Submit the comment
    await addCommentForm.getByRole("button").click();

    // Wait for the comment to be added (you might need to adjust this based on your UI behavior)
    await page.waitForTimeout(1000);

    const commentsList = await page.getByTestId(
      "logged-in-user-feedback-comments",
    );
    // find the li > p which has the text of the comment
    await commentsList.getByText(commentText).waitFor();
  });
});
