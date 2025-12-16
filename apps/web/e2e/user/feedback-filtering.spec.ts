import { expect, test } from "@playwright/test";

test.describe
  .serial("Feedback Filtering", () => {
    test("User can filter feedback by status", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto("/feedback");

      // Open filter dialog
      await page.getByTestId("filter-dialog-trigger").click();

      // Select "In Progress" status checkbox
      await page.getByTestId("filter-status-in_progress").click();

      // Click Apply
      await page.getByTestId("filter-apply-button").click();

      // Verify URL contains status filter
      await expect(page).toHaveURL(/statuses=in_progress/);
    });

    test("User can filter feedback by type", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto("/feedback");

      // Open filter dialog
      await page.getByTestId("filter-dialog-trigger").click();

      // Select "Feature Request" type checkbox
      await page.getByTestId("filter-type-feature_request").click();

      // Click Apply
      await page.getByTestId("filter-apply-button").click();

      // Verify URL contains type filter
      await expect(page).toHaveURL(/types=feature_request/);
    });

    test("User can filter feedback by priority", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto("/feedback");

      // Open filter dialog
      await page.getByTestId("filter-dialog-trigger").click();

      // Select "High" priority checkbox
      await page.getByTestId("filter-priority-high").click();

      // Click Apply
      await page.getByTestId("filter-apply-button").click();

      // Verify URL contains priority filter
      await expect(page).toHaveURL(/priorities=high/);
    });

    test("User can search feedback by keyword", async ({ page }) => {
      // Navigate to the feedback page
      await page.goto("/feedback");

      // Open filter dialog
      await page.getByTestId("filter-dialog-trigger").click();

      // Enter search term
      await page.getByTestId("filter-search-input").fill("test");

      // Click Apply
      await page.getByTestId("filter-apply-button").click();

      // Verify URL contains query
      await expect(page).toHaveURL(/query=test/);
    });

    test("User can reset filters", async ({ page }) => {
      // Navigate to the feedback page with existing filters
      await page.goto("/feedback?statuses=open&types=bug");

      // Open filter dialog
      const filterDialog = page.getByRole("dialog", {
        name: "Filter Feedback",
      });
      await page.getByTestId("filter-dialog-trigger").click();
      await expect(filterDialog).toBeVisible();

      // Click Reset and wait for state to update
      await page.getByTestId("filter-reset-button").click();

      // Click Apply to apply the reset
      await page.getByTestId("filter-apply-button").click();

      // Wait for dialog to close (confirms action completed)
      await expect(filterDialog).not.toBeVisible();

      // Verify URL is clean
      await expect(page).not.toHaveURL(/statuses=/);
      await expect(page).not.toHaveURL(/types=/);
    });
  });
