import { expect, test } from '@playwright/test';

test.describe.serial('Blog Post Management', () => {
  let blogPostId: string | undefined;
  let blogPostTitle: string | undefined;

  test('Admin can create a new blog post', async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: 'playwright/.auth/admin.json',
    });
    const adminPage = await adminContext.newPage();

    const randomString = Math.random().toString(36).substring(2, 15);
    blogPostTitle = `Test Post ${randomString}`;

    await adminPage.goto('/app_admin/');

    await adminPage.getByRole('link', { name: 'Marketing Blog', exact: true }).click();
    await adminPage.getByRole('button', { name: 'Create Blog Post' }).click();
    await adminPage.waitForURL(/\/[a-z]{2}\/app_admin\/marketing\/blog\/[a-zA-Z0-9-]+$/);

    // Extract the blog post ID from the URL
    blogPostId = adminPage.url().split('/').pop();
    console.log(`Created blog post with ID: ${blogPostId}`);

    // Ensure the ID is not undefined
    if (!blogPostId) {
      throw new Error('Failed to extract blog post ID from URL');
    }

    await adminPage.getByLabel('Title').fill(blogPostTitle);
    await adminPage.locator('#status').click();
    await adminPage.getByLabel('Published').click();
    await adminPage.getByLabel('Summary').fill('This is a test summary');
    await adminPage.getByLabel('Content').fill('This is the content of the test blog post.');
    await adminPage.getByRole('button', { name: 'Update Blog Post' }).click();

    // Verify the blog post is listed on the admin blog page
    await adminPage.getByRole('link', { name: 'Marketing Blog' }).click();
    await expect(adminPage.getByText(blogPostTitle)).toBeVisible();

    await adminContext.close();
  });

  test('Anonymous user can see the published blog post', async ({ page }) => {
    // Ensure we have a blog post title
    if (!blogPostTitle) {
      throw new Error('Blog post title is undefined');
    }

    // Navigate to the public blog page
    await page.goto('/blog');

    // Verify the blog post is visible
    const blogPostLink = page.getByRole('link', { name: blogPostTitle });
    await expect(blogPostLink).toBeVisible();

    // Click on the blog post
    await blogPostLink.click();

    // Verify we're on the correct blog post page
    await page.waitForURL(/\/blog\/[a-zA-Z0-9-]+$/);
    await expect(page.getByRole('heading', { name: blogPostTitle })).toBeVisible();

    // Verify the content is visible
    await expect(page.getByText('This is the content of the test blog post.')).toBeVisible();
  });

  test('Admin can edit the blog post', async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: 'playwright/.auth/admin.json',
    });
    const adminPage = await adminContext.newPage();

    await adminPage.goto(`/app_admin/marketing/blog/${blogPostId}`);

    const updatedTitle = `${blogPostTitle} (Updated)`;
    await adminPage.getByLabel('Title').fill(updatedTitle);
    await adminPage.getByLabel('Content').fill('This is the updated content of the test blog post.');
    await adminPage.getByRole('button', { name: 'Update Blog Post' }).click();

    // Verify the changes
    await adminPage.getByRole('link', { name: 'Marketing Blog' }).click();
    await expect(adminPage.getByText(updatedTitle)).toBeVisible();

    // Update the blogPostTitle for the next test
    blogPostTitle = updatedTitle;

    await adminContext.close();
  });

  test('Anonymous user can see the updated blog post', async ({ page }) => {
    // Ensure we have an updated blog post title
    if (!blogPostTitle) {
      throw new Error('Updated blog post title is undefined');
    }

    await page.goto('/blog');

    // Verify the updated blog post is visible
    const updatedBlogPostLink = page.getByRole('link', { name: blogPostTitle });
    await expect(updatedBlogPostLink).toBeVisible();

    // Click on the updated blog post
    await updatedBlogPostLink.click();

    // Verify we're on the correct blog post page
    await page.waitForURL(/\/blog\/[a-zA-Z0-9-]+$/);
    await expect(page.getByRole('heading', { name: blogPostTitle })).toBeVisible();

    // Verify the updated content is visible
    await expect(page.getByText('This is the updated content of the test blog post.')).toBeVisible();
  });
});
