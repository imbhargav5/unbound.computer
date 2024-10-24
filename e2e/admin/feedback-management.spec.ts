import { expect, test } from "@playwright/test";

test.describe.skip("Admin Feedback Management", () => {
  let feedbackId: string | undefined;
  let feedbackTitle: string | undefined;

  test("User creates feedback", async ({ browser, page: userPage }) => {
    await userPage.goto("/en/dashboard");
    await userPage.getByTestId("user-nav-avatar").click();
    await userPage.getByTestId("feedback-link").click();
    const giveFeedbackForm = userPage.getByTestId("give-feedback-form");
    const randomTitleSuffix = Math.random().toString(36).substring(2, 15);
    feedbackTitle = `Admin Test Feedback ${randomTitleSuffix}`;
    const content = `This is a test feedback for admin actions ${randomTitleSuffix}`;
    await giveFeedbackForm
      .getByTestId("feedback-title-input")
      .fill(feedbackTitle);
    await giveFeedbackForm.getByTestId("feedback-content-input").fill(content);
    const selectTrigger = giveFeedbackForm.getByRole("combobox");
    await selectTrigger.waitFor();
    await selectTrigger.click();
    const listBox = userPage.getByRole("listbox");
    await listBox.waitFor();
    await listBox.getByText("Bug").click();
    await giveFeedbackForm.getByTestId("submit-feedback-button").click();

    await userPage.waitForURL(/\/en\/feedback\/[a-zA-Z0-9-]+$/);
    const url = await userPage.url();
    feedbackId = url.split("/").pop();
    expect(feedbackId).toBeDefined();
  });

  test("Admin can view and update feedback", async ({ browser, page }) => {
    const adminContext = await browser.newContext({
      storageState: "playwright/.auth/app_admin.json",
    });
    const adminPage = await adminContext.newPage();
    await adminPage.goto(`/en/feedback/${feedbackId}`);

    const title = adminPage.getByRole("heading", { name: feedbackTitle });
    await title.waitFor();

    // Wait for the feedback details page to load
    await adminPage.getByRole("heading", { name: feedbackTitle }).waitFor();
    const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
    await feedbackVisibility.waitFor();
    const dropdownMenuTrigger = feedbackVisibility.getByTestId(
      "feedback-actions-dropdown-button",
    );
    await dropdownMenuTrigger.waitFor();
    // Apply status
    await dropdownMenuTrigger.click();
    await adminPage.getByRole("menuitem", { name: "Apply Status" }).click();
    const statusSubMenu = adminPage.getByTestId("apply-status-dropdown-menu");
    await statusSubMenu.waitFor();
    await statusSubMenu.getByRole("menuitem", { name: "In Progress" }).click();

    await title.click(); // click away to close dropdown

    // Apply priority
    await dropdownMenuTrigger.click();
    await adminPage.getByRole("menuitem", { name: "Apply Priority" }).click();
    const prioritySubMenu = adminPage.getByTestId(
      "apply-priority-dropdown-menu",
    );
    await prioritySubMenu.waitFor();
    await prioritySubMenu.getByRole("menuitem", { name: "High" }).click();

    await title.click(); // click away to close dropdown

    // Apply type
    await dropdownMenuTrigger.click();
    await adminPage.getByRole("menuitem", { name: "Apply Type" }).click();
    const typeSubMenu = adminPage.getByTestId("apply-type-dropdown-menu");
    await typeSubMenu.waitFor();
    await typeSubMenu
      .getByRole("menuitem", { name: "Feature Request" })
      .click();

    // Verify updates
    await expect(adminPage.getByText("Status: In Progress")).toBeVisible();
    await expect(adminPage.getByText("Priority: High")).toBeVisible();
    await expect(adminPage.getByText("Type: Feature Request")).toBeVisible();
    await adminContext.close();
  });

  test("Admin can add a comment", async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: "playwright/.auth/app_admin.json",
    });
    const adminPage = await adminContext.newPage();
    await adminPage.goto(`/en/feedback/${feedbackId}`);
    const addCommentForm = await adminPage.getByTestId("add-comment-form");
    await addCommentForm.getByRole("textbox").fill("This is an admin comment.");
    await addCommentForm.getByRole("button", { name: "Add Comment" }).click();

    const commentsList = await adminPage.getByTestId(
      "admin-user-feedback-comments",
    );
    await commentsList.getByText("This is an admin comment.").waitFor();
  });

  test("Admin can filter feedback", async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: "playwright/.auth/app_admin.json",
    });
    const adminPage = await adminContext.newPage();
    await adminPage.goto("/en/feedback");

    // Filter by status
    await adminPage.getByTestId("status-filter-button").click();
    await adminPage
      .getByTestId("status-filter-command-list")
      .getByRole("option", { name: "In Progress" })
      .click();

    // wait for the url to change but no need to match the url
    await adminPage.waitForLoadState("load");

    // Filter by priority
    await adminPage.getByTestId("priority-filter-button").click();
    await adminPage
      .getByTestId("priority-filter-command-list")
      .getByRole("option", { name: "High" })
      .click();
    // wait for the url to change but no need to match the url
    await adminPage.waitForLoadState("load");
    // Filter by type
    await adminPage.getByTestId("type-filter-button").click();
    await adminPage
      .getByTestId("type-filter-command-list")
      .getByRole("option", { name: "Feature Request" })
      .click();

    // Check if the filtered list contains our test feedback
    if (!feedbackTitle) {
      throw new Error("Feedback title is undefined");
    }
    await expect(adminPage.getByText(feedbackTitle)).toBeVisible();
    await adminContext.close();
  });

  test("Admin can toggle feedback visibility", async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: "playwright/.auth/app_admin.json",
    });
    const adminPage = await adminContext.newPage();
    await adminPage.goto(`/en/feedback/${feedbackId}`);

    // Toggle visibility
    const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
    await feedbackVisibility.waitFor();
    const dropdownMenuTrigger = feedbackVisibility.getByTestId(
      "feedback-actions-dropdown-button",
    );
    await dropdownMenuTrigger.waitFor();
    await dropdownMenuTrigger.click();
    await adminPage.getByTestId("toggle-visibility-dropdown-menu-item").click();
    // click on title
    await adminPage.getByRole("heading", { name: feedbackTitle }).click();
    // Verify visibility change
    await expect(
      adminPage.getByTestId("feedback-visibility").getByText("Private"),
    ).toBeVisible();

    // Toggle visibility back
    await dropdownMenuTrigger.click();
    await adminPage.getByTestId("toggle-visibility-dropdown-menu-item").click();
    // click on title
    await adminPage.getByRole("heading", { name: feedbackTitle }).click();
    // Verify visibility change back to public
    await expect(
      adminPage.getByTestId("feedback-visibility").getByText("Public"),
    ).toBeVisible();
    await adminContext.close();
  });

  test("User can see admin updates", async ({ page }) => {
    await page.goto(`/en/feedback/${feedbackId}`);
    await page.getByRole("heading", { name: feedbackTitle }).waitFor();

    await expect(page.getByText("Status: In Progress")).toBeVisible();
    await expect(page.getByText("Priority: High")).toBeVisible();
    await expect(page.getByText("Type: Feature Request")).toBeVisible();
    await expect(page.getByText("This is an admin comment.")).toBeVisible();
  });
});
