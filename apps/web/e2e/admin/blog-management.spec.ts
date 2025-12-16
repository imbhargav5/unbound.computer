import { expect, test } from "@playwright/test";

test.describe
  .serial("Blog Post Management", () => {
    let blogPostId: string | undefined;
    let blogPostTitle: string | undefined;

    test("Admin creates a new blog post", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      // Navigate to blog list page
      await adminPage.goto("/app-admin/marketing/blog", {
        waitUntil: "domcontentloaded",
      });

      const createLink = adminPage.getByTestId("create-blog-post-button");
      await createLink.waitFor({ state: "visible" });
      await createLink.click();

      // Wait for navigation to create page, fallback to manual navigation if needed
      try {
        await adminPage.waitForURL(/\/app-admin\/marketing\/blog\/create/, {
          waitUntil: "domcontentloaded",
          timeout: 5000,
        });
      } catch {
        await adminPage.goto("/app-admin/marketing/blog/create", {
          waitUntil: "domcontentloaded",
        });
      }

      // Generate unique title for test
      const randomTitleSuffix = Math.random().toString(36).substring(2, 15);
      blogPostTitle = `Test Blog Post ${randomTitleSuffix}`;

      // Fill in the create form
      await adminPage.getByLabel("Title").fill(blogPostTitle);
      await adminPage.getByLabel("Summary").fill("This is a test summary");
      await adminPage.locator("#status").click();
      await adminPage.getByLabel("Published").click();

      // Submit the form
      const createBlogFormButton = adminPage.getByRole("button", {
        name: "Create Blog Post",
      });

      await createBlogFormButton.click();

      await adminPage
        .getByTestId("blog-post-edit-header")
        .waitFor({ state: "visible" });
      adminPage.waitForURL(
        /\/app-admin\/marketing\/blog\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
        { timeout: 15_000 }
      );

      // Extract the blog post ID from the URL
      const url = adminPage.url();
      blogPostId = url.split("/").pop();
      expect(blogPostId).toBeDefined();

      // Verify we're on the edit page
      await expect(adminPage.getByLabel("Title")).toHaveValue(blogPostTitle);

      await adminPage.goto("/app-admin/marketing/blog", {
        waitUntil: "domcontentloaded",
      });

      // Verify the blog post appears in the list using the specific row test ID
      const blogTitle = adminPage.getByTestId(
        `admin-blog-list-title-${blogPostId}`
      );
      await expect(blogTitle).toBeVisible({ timeout: 10_000 });

      await adminContext.close();
    });

    test("Anonymous user can see the published blog post", async ({
      page,
      request,
    }) => {
      await page.goto("/blog", { waitUntil: "load" });
      // this will still fetch stale data, but it will fetch fresh data in the background for the next request.
      // hence reload
      await page.reload();

      // Look for the blog post title in the card - the blog posts are rendered as cards with CardTitle
      // The title is inside a Link -> Card -> CardHeader -> CardTitle
      const titleElement = page.locator(`text="${blogPostTitle}"`).first();
      await expect(titleElement).toBeVisible();

      // Click on the card/link containing the blog post
      await page.locator(`text="${blogPostTitle}"`).first().click();

      await page.waitForURL(/\/blog\/[a-zA-Z0-9-]+$/);
      await expect(
        page.getByRole("heading", { name: blogPostTitle })
      ).toBeVisible();
    });

    test("Admin can edit the blog post", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto(`/app-admin/marketing/blog/${blogPostId}`);

      const updatedTitle = `${blogPostTitle} (Updated)`;
      await adminPage.getByLabel("Title").fill(updatedTitle);
      await adminPage.getByRole("button", { name: "Update Blog Post" }).click();

      // Wait for update to complete before navigating away (check for success toast)
      await expect(
        adminPage.getByText("Blog post updated successfully")
      ).toBeVisible({ timeout: 15_000 });

      await adminPage.goto("/app-admin/marketing/blog");

      // Wait for the list page to fully load
      await adminPage
        .getByTestId("create-blog-post-button")
        .waitFor({ state: "visible" });

      // Verify the updated blog post appears in the list with polling
      const blogTitle = adminPage.getByTestId(
        `admin-blog-list-title-${blogPostId}`
      );
      await expect(blogTitle).toBeVisible({ timeout: 10_000 });
      await expect(blogTitle).toHaveText(updatedTitle);

      blogPostTitle = updatedTitle;

      await adminContext.close();
    });

    test("Anonymous user can see the updated blog post", async ({ page }) => {
      await page.goto("/blog", { waitUntil: "load" });
      // this will still fetch stale data, but it will fetch fresh data in the background for the next request.
      // hence reload
      await page.reload();

      const updatedBlogPostLink = page.getByRole("link", {
        name: blogPostTitle,
      });
      await expect(updatedBlogPostLink).toBeVisible();

      await updatedBlogPostLink.click();

      await page.waitForURL(/\/blog\/[a-zA-Z0-9-]+$/);
      await expect(
        page.getByRole("heading", { name: blogPostTitle })
      ).toBeVisible();
    });

    test("Admin can change blog post status", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto(`/app-admin/marketing/blog/${blogPostId}`);

      await adminPage.locator("#status").first().click();
      await adminPage.getByLabel("Draft").click();
      await adminPage.getByRole("button", { name: "Update Blog Post" }).click();

      // Wait for update to complete before navigating away (check for success toast or button change)
      await expect(
        adminPage.getByText(/Blog post updated|Updated!/i).first()
      ).toBeVisible({ timeout: 15_000 });

      await adminPage.goto("/app-admin/marketing/blog");
      const row = adminPage.getByTestId(`admin-blog-list-row-${blogPostId}`);
      // Use case-insensitive regex - status cell shows lowercase "draft"
      const statusCell = row.getByRole("cell", { name: /draft/i });
      await expect(statusCell).toBeVisible({ timeout: 10_000 });

      await adminContext.close();
    });

    test("Anonymous user cannot see the draft blog post", async ({ page }) => {
      await page.goto("/blog", { waitUntil: "load" });
      // this will still fetch stale data, but it will fetch fresh data in the background for the next request.
      // hence reload
      await page.reload();

      const blogPostLink = page.getByRole("link", { name: blogPostTitle });
      await expect(blogPostLink).not.toBeVisible();
    });

    test("Admin can delete the blog post", async ({ browser }) => {
      const adminContext = await browser.newContext({
        storageState: "playwright/.auth/app-admin.json",
      });
      const adminPage = await adminContext.newPage();

      await adminPage.goto("/app-admin/marketing/blog");

      const deleteButton = adminPage
        .getByRole("row", { name: blogPostTitle })
        .getByTestId("delete-blog-post-dialog-trigger");
      await deleteButton.click();
      await adminPage.getByTestId("confirm-delete-button").waitFor();
      await adminPage.getByTestId("confirm-delete-button").click();

      if (!blogPostTitle) {
        throw new Error("Blog post title is undefined");
      }

      // Verify the blog post is gone
      await expect(
        adminPage.getByRole("row", { name: blogPostTitle })
      ).not.toBeVisible();

      await adminContext.close();
    });
  });
