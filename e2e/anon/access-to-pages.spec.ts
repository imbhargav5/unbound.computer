import { expect, test } from "@playwright/test";

test.describe.parallel("Anonymous access to pages", () => {
  test("Anon users can see home page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/");
    await expect(page.locator("h1")).toContainText(
      "Nextbase Ultimate Landing Page",
    );
  });

  test("Anon users can see feedback page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/feedback");
    await expect(
      page.getByRole("heading", { name: "Community Feedback" }),
    ).toBeVisible();
  });

  test("Anon users can see docs page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/docs");
    await expect(
      page.getByRole("heading", { name: "Documentation " }),
    ).toBeVisible();
  });

  test("Anon users can see blog page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/blog");
    await expect(
      page.getByRole("heading", { name: "All Blog Posts " }),
    ).toBeVisible();
  });

  test("Anon users can see roadmap page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/roadmap");
    await expect(page.getByRole("heading", { name: "Roadmap " })).toBeVisible();
  });

  test("Anon users can see changelog page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/changelog");
    await expect(page.getByTestId("page-heading-title")).toContainText(
      "Changelog",
    );
  });

  test("Anon users can see terms page", async ({ page }) => {
    // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
    await page.goto("/en/terms");
    await expect(
      page.getByRole("heading", { name: "Terms of Service " }),
    ).toBeVisible();
  });

  test("Anon users can not see dashboard", async ({ page }) => {
    // expect that they are redirected to login page
    await page.goto("/en/dashboard");
    await page.waitForURL("/en/login");
  });

  test("Anon users can not see admin", async ({ page }) => {
    // expect that they are redirected to login page
    await page.goto("/en/app_admin");
    await page.waitForURL("/en/login");
  });

  test("Anon users can not see onboarding", async ({ page }) => {
    // expect that they are redirected to login page
    await page.goto("/en/onboarding");
    await page.waitForURL("/en/login");
  });
});
