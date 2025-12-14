import { expect, test } from "@playwright/test";

test.describe
  .serial("Changelog Management", () => {
    let changelogId: string | undefined;
    let changelogTitle: string | undefined;

    test("Admin creates a new changelog", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto("/en/app-admin/marketing/changelog");
      const createButton = adminPage.getByRole("button", {
        name: "Create Changelog",
      });
      await createButton.waitFor({ state: "visible" });
      await createButton.click();

      // Wait for either URL change (success) OR error toast (failure)
      const result = await Promise.race([
        adminPage
          .waitForURL(/\/en\/app-admin\/marketing\/changelog\/[a-zA-Z0-9-]+$/, {
            timeout: 10_000,
          })
          .then(() => ({ type: "success" as const })),
        adminPage
          .getByText(/Failed to create changelog/)
          .waitFor({ timeout: 10_000 })
          .then(() => ({ type: "error" as const })),
        adminPage
          .getByText(/User is not an admin/)
          .waitFor({ timeout: 10_000 })
          .then(() => ({ type: "auth_error" as const })),
      ]).catch(() => ({ type: "timeout" as const }));

      if (
        result.type === "error" ||
        result.type === "auth_error" ||
        result.type === "timeout"
      ) {
        // Capture error details
        const pageContent = await adminPage.content();
        const toasts = await adminPage
          .locator("[data-sonner-toast]")
          .allTextContents();
        console.log("=== CHANGELOG CREATION DEBUG INFO ===");
        console.log("Result type:", result.type);
        console.log("Toast messages:", toasts);
        console.log("Current URL:", adminPage.url());

        // Try to get more specific error
        const errorToast = adminPage
          .locator("[data-sonner-toast]")
          .filter({ hasText: /Failed|error|Error/ });
        if ((await errorToast.count()) > 0) {
          const errorText = await errorToast.first().textContent();
          console.log("Error toast content:", errorText);
        }

        throw new Error(
          `Changelog creation failed: ${result.type}. Check console for details.`
        );
      }

      const url = await adminPage.url();
      changelogId = url.split("/").pop();
      expect(changelogId).toBeDefined();

      const randomTitleSuffix = Math.random().toString(36).substring(2, 15);
      changelogTitle = `Test Changelog ${randomTitleSuffix}`;

      await adminPage.getByLabel("Title").fill(changelogTitle);
      await adminPage.locator("#status").click();
      await adminPage.getByLabel("Published").click();
      await adminPage.getByRole("button", { name: "Update Changelog" }).click();

      // Wait for update to complete before navigating away (check for success toast or button change)
      await expect(
        adminPage.getByText(/Changelog updated|Updated!/i).first()
      ).toBeVisible({ timeout: 15_000 });

      await adminPage.goto("/en/app-admin/marketing/changelog");

      // Verify the changelog appears in the list (check it's in the DOM)
      await expect(adminPage.getByText(changelogTitle).first()).toBeAttached();

      await adminContext.close();
    });

    test("Anonymous user can see the published changelog", async ({ page }) => {
      await page.goto("/en/changelog");
      if (!changelogTitle) {
        throw new Error("Changelog title is undefined");
      }
      await expect(page.getByText(changelogTitle)).toBeVisible();
    });

    test("Admin can edit the changelog", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto(`/en/app-admin/marketing/changelog/${changelogId}`);

      const updatedTitle = `${changelogTitle} (Updated)`;
      await adminPage.getByLabel("Title").fill(updatedTitle);
      await adminPage.getByRole("button", { name: "Update Changelog" }).click();

      // Wait for update to complete before navigating away (check for success toast or button change)
      await expect(
        adminPage.getByText(/Changelog updated|Updated!/i).first()
      ).toBeVisible({ timeout: 15_000 });

      await adminPage.goto("/en/app-admin/marketing/changelog");
      await adminPage.waitForURL("/en/app-admin/marketing/changelog");

      // Verify the updated changelog appears in the list
      await expect(
        adminPage.getByTestId(`changelog-title-${changelogId}`)
      ).toHaveText(updatedTitle);

      if (!changelogTitle) {
        throw new Error("Changelog title is undefined");
      }
      changelogTitle = updatedTitle;

      await adminContext.close();
    });

    test("Anonymous user can see the updated changelog", async ({ page }) => {
      await page.goto("/en/changelog");
      if (!changelogTitle) {
        throw new Error("Changelog title is undefined");
      }
      await expect(page.getByText(changelogTitle)).toBeVisible();
    });

    test("Admin can change changelog status", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto(`/en/app-admin/marketing/changelog/${changelogId}`);

      await adminPage.locator("#status").first().click();
      await adminPage.getByLabel("Draft").click();
      await adminPage.getByRole("button", { name: "Update Changelog" }).click();

      // Wait for update to complete before navigating away (check for success toast or button change)
      await expect(
        adminPage.getByText(/Changelog updated|Updated!/i).first()
      ).toBeVisible({ timeout: 15_000 });

      await adminPage.goto("/en/app-admin/marketing/changelog");
      const row = adminPage.getByRole("row", { name: changelogTitle });
      const statusCell = row.getByRole("cell", { name: "Draft" });
      await expect(statusCell).toBeVisible();

      await adminContext.close();
    });

    test("Anonymous user cannot see the draft changelog", async ({ page }) => {
      await page.goto("/en/changelog");
      if (!changelogTitle) {
        throw new Error("Changelog title is undefined");
      }
      await expect(page.getByText(changelogTitle)).not.toBeVisible();
    });

    test("Admin can delete the changelog", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto("/en/app-admin/marketing/changelog");

      await adminPage.waitForLoadState("load", { timeout: 15_000 });

      // Try to find the delete button, with retry logic
      const deleteButton = adminPage
        .getByRole("row", { name: changelogTitle })
        .getByTestId("delete-changelog-dialog-trigger");

      // Wait for the delete button to be visible
      await deleteButton.waitFor({ state: "visible", timeout: 15_000 });
      await deleteButton.click();
      await adminPage.getByTestId("confirm-delete-button").waitFor();
      await adminPage.getByTestId("confirm-delete-button").click();
      if (!changelogTitle) {
        throw new Error("Changelog title is undefined");
      }

      // Wait for either success or the delete operation to complete
      // Use Promise.race to handle either toast appearing or timeout
      await Promise.race([
        adminPage
          .getByText("Changelog deleted successfully")
          .waitFor({ timeout: 45_000 }),
        adminPage.waitForTimeout(45_000),
      ]).catch(() => {
        // If toast doesn't appear, that's okay - we'll verify via reload
      });

      await adminPage.goto("/en/app-admin/marketing/changelog");

      // Verify the changelog is no longer in the list
      await expect(
        adminPage.getByRole("row", { name: changelogTitle })
      ).not.toBeVisible({ timeout: 10_000 });

      await adminContext.close();
    });
  });
