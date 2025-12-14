import { test } from "@playwright/test";

test.describe
  .serial("admin panel", () => {
    test("go to admin panel", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();
      await adminPage.goto("/app-admin");
      await adminPage.getByTestId("admin-panel-layout").first().waitFor();
    });
  });
