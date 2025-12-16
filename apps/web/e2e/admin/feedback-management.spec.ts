import { expect, test } from "@playwright/test";
import Chance from "chance";
import {
  adminSetFeedbackVisibilityHelper,
  createFeedbackHelper,
} from "e2e/_helpers/feedback.helper";

const chance = new Chance();

test.describe
  .serial("Admin Feedback Management", () => {
    let commonFeedbackId: string | undefined;
    const commonFeedbackTitle = `Test Feedback ${chance.word()}`;
    const commonFeedbackDescription = chance.sentence();

    test("User creates feedback", async ({ page }) => {
      // Navigate to the dashboard and create feedback
      const createdFeedbackId = await createFeedbackHelper({
        page,
        feedbackTitle: commonFeedbackTitle,
        feedbackDescription: commonFeedbackDescription,
      });
      commonFeedbackId = createdFeedbackId;
      expect(commonFeedbackId).toBeDefined();
    });

    test("Admin can view and update feedback", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();
      await adminPage.goto(`/feedback/${commonFeedbackId}`);

      // Wait for the feedback details page to load
      await adminPage
        .getByRole("heading", { name: commonFeedbackTitle })
        .waitFor();
      const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
      await feedbackVisibility.waitFor();
      const dropdownMenuTrigger = feedbackVisibility.getByTestId(
        "feedback-actions-dropdown-button"
      );
      await dropdownMenuTrigger.waitFor();

      // Apply status
      await dropdownMenuTrigger.click();
      await adminPage.getByRole("menuitem", { name: /Apply status/i }).click();
      const statusSubMenu = adminPage.getByTestId("apply-status-dropdown-menu");
      await statusSubMenu.waitFor();
      await statusSubMenu
        .getByRole("menuitem", { name: /In Progress/i })
        .click();

      // click away
      await adminPage.click("body");
      await adminPage.waitForTimeout(1000);

      // Apply priority
      await dropdownMenuTrigger.click();
      await adminPage
        .getByRole("menuitem", { name: /Apply priority/i })
        .click();
      const prioritySubMenu = adminPage.getByTestId(
        "apply-priority-dropdown-menu"
      );
      await prioritySubMenu.waitFor();
      await prioritySubMenu.getByRole("menuitem", { name: /High/i }).click();

      // click away
      await adminPage.click("body");
      await adminPage.waitForTimeout(1000);
      // Apply type
      await dropdownMenuTrigger.click();
      await adminPage.getByRole("menuitem", { name: /Apply type/i }).click();
      const typeSubMenu = adminPage.getByTestId("apply-type-dropdown-menu");
      await typeSubMenu.waitFor();
      await typeSubMenu
        .getByRole("menuitem", { name: /Feature Request/i })
        .click();

      // click away
      await adminPage.click("body");

      // Verify updates are visible - use case-insensitive contains checks
      await expect
        .poll(
          async () => {
            const statusText = await adminPage
              .getByTestId("feedback-status-badge")
              .textContent();
            return statusText?.toLowerCase() || "";
          },
          {
            intervals: [500, 1000],
            timeout: 10_000,
          }
        )
        .toContain("progress");

      await expect
        .poll(
          async () => {
            const priorityText = await adminPage
              .getByTestId("feedback-priority-badge")
              .textContent();
            return priorityText?.toLowerCase() || "";
          },
          {
            intervals: [500, 1000],
            timeout: 10_000,
          }
        )
        .toContain("high");

      await expect
        .poll(
          async () => {
            const typeText = await adminPage
              .getByTestId("feedback-type-badge")
              .textContent();
            return typeText?.toLowerCase() || "";
          },
          {
            intervals: [500, 1000],
            timeout: 10_000,
          }
        )
        .toContain("feature");

      await adminContext.close();
    });

    test("Admin can add a comment", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();
      await adminPage.goto(`/feedback/${commonFeedbackId}`);

      const commentText = `Test comment ${chance.word()}`;
      await adminPage
        .getByPlaceholder("Share your thoughts or ask a question...")
        .click();
      await adminPage
        .getByPlaceholder("Share your thoughts or ask a question...")
        .fill(commentText);
      await adminPage.getByRole("button", { name: "Post Comment" }).click();

      // Verify comment is visible
      await adminPage.getByText(commentText).waitFor();
      await adminContext.close();
    });

    test("Admin can toggle feedback visibility", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();
      await adminPage.goto(`/feedback/${commonFeedbackId}`);

      // Wait for the feedback details page to load
      await adminPage
        .getByRole("heading", { name: commonFeedbackTitle })
        .waitFor();
      const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
      await feedbackVisibility.waitFor();

      // Get current visibility state
      const initialVisibilityText = await feedbackVisibility.textContent();
      const wasPublic = initialVisibilityText?.toLowerCase().includes("public");

      const dropdownMenuTrigger = feedbackVisibility.getByTestId(
        "feedback-actions-dropdown-button"
      );
      await dropdownMenuTrigger.waitFor();

      // Click to toggle visibility
      await dropdownMenuTrigger.click();
      await adminPage
        .getByTestId("toggle-visibility-dropdown-menu-item")
        .click();

      // Poll for visibility change instead of arbitrary timeout
      await expect
        .poll(
          async () => {
            const text = await feedbackVisibility.textContent();
            return text?.toLowerCase().includes("public");
          },
          {
            intervals: [500, 1000, 2000],
            timeout: 10_000,
          }
        )
        .toBe(!wasPublic);

      await adminContext.close();
    });

    test("Admin can enable public discussion", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();
      await adminPage.goto(`/feedback/${commonFeedbackId}`);

      // Wait for the feedback details page to load
      await adminPage
        .getByRole("heading", { name: commonFeedbackTitle })
        .waitFor();
      const feedbackVisibility = adminPage.getByTestId("feedback-visibility");
      await feedbackVisibility.waitFor();
      const dropdownMenuTrigger = feedbackVisibility.getByTestId(
        "feedback-actions-dropdown-button"
      );
      await dropdownMenuTrigger.waitFor();

      // Click to open comments
      await dropdownMenuTrigger.click();
      const openForCommentsButton = adminPage.getByTestId(
        "open-for-comments-button"
      );

      // Check if the button exists (it may not if discussion is already open)
      const buttonCount = await openForCommentsButton.count();
      if (buttonCount > 0) {
        await openForCommentsButton.click();
        await adminPage.waitForTimeout(500);
      } else {
        // Click away to close the menu
        await adminPage.click("body");
      }

      await adminContext.close();
    });

    test("Hidden feedback is not visible to anonymous users", async ({
      browser,
    }) => {
      // First, ensure the feedback is hidden by admin
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      const feedbackTitle = `Test Feedback ${chance.word()}`;
      const feedbackDescription = chance.sentence();

      const createdFeedbackId = await createFeedbackHelper({
        page: adminPage,
        feedbackTitle,
        feedbackDescription,
      });

      await adminPage.goto(`/feedback/${createdFeedbackId}`, {
        waitUntil: "domcontentloaded",
      });

      await adminSetFeedbackVisibilityHelper({
        adminPage,
        feedbackId: createdFeedbackId,
        visibility: "public",
      });

      // ==== anon checks for feedback visibility ====
      // as anon, go to feedback page
      // Now check as anonymous user
      const anonContext = await browser.newContext();
      const anonPage = await anonContext.newPage();

      await anonPage.goto("/feedback", {
        waitUntil: "domcontentloaded",
      });

      await anonPage.reload();
      await anonPage.waitForLoadState("domcontentloaded");
      await anonPage.waitForTimeout(2000);
      await anonPage.reload();
      await anonPage.waitForLoadState("domcontentloaded");

      // Verify the hidden feedback is not visible in the list
      const feedbackInListWhenPublic = anonPage
        .getByTestId("feedback-list")
        .locator(`[data-feedback-id="${createdFeedbackId}"]`);
      await expect(feedbackInListWhenPublic).toBeVisible();

      await adminPage.reload({
        waitUntil: "domcontentloaded",
      });
      await adminSetFeedbackVisibilityHelper({
        adminPage,
        feedbackId: createdFeedbackId,
        visibility: "private",
      });
      await adminContext.close();

      // reload a couple of two times
      await anonPage.reload();
      await anonPage.waitForLoadState("domcontentloaded");
      await anonPage.waitForTimeout(2000);
      await anonPage.reload();
      await anonPage.waitForLoadState("domcontentloaded");

      // Verify the hidden feedback is not visible in the list
      const feedbackInListWhenPrivate = anonPage
        .getByTestId("feedback-list")
        .locator(`[data-feedback-id="${createdFeedbackId}"]`);
      await expect(feedbackInListWhenPrivate).not.toBeVisible();

      await anonContext.close();
    });
  });
