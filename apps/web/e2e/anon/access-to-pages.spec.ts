import { expect, test } from "@playwright/test";

test.describe
  .parallel("Anonymous access to pages", () => {
    test("Anon users can see home page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/");
      await expect(page.locator("h1")).toContainText(
        "starterkit"
      );
    });

    test("Anon users can see feedback page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/feedback");
      await expect(
        page.getByRole("heading", { name: "Community Feedback" })
      ).toBeVisible();
    });

    test("Anon users can see docs page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/docs");
      await expect(page.getByTestId("page-heading-title")).toContainText(
        "Documentation"
      );
    });

    test("Anon users can see blog page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/blog");
      await expect(
        page.getByRole("heading", { name: "All Blog Posts " })
      ).toBeVisible();
    });

    test("Anon users can see roadmap page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/roadmap");
      await expect(
        page.getByRole("heading", { name: "Roadmap " })
      ).toBeVisible();
    });

    test("Anon users can see changelog page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/changelog");
      await expect(page.getByTestId("page-heading-title")).toContainText(
        "Changelog"
      );
    });

    test("Anon users can see terms page", async ({ page }) => {
      // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
      await page.goto("/terms");
      await expect(
        page.getByRole("heading", { name: "Terms of Service " })
      ).toBeVisible();
    });

    test("Anon users can not see dashboard", async ({ page }) => {
      // expect that they are redirected to login page
      await page.goto("/dashboard");
      await page.waitForURL("/login");
    });

    test("Anon users can not see admin", async ({ page }) => {
      // expect that they are redirected to login page
      await page.goto("/app-admin");
      await page.waitForURL("/login");
    });

    test("Anon users can not see onboarding", async ({ page }) => {
      // expect that they are redirected to login page
      await page.goto("/onboarding");
      await page.waitForURL("/login");
    });
  });
