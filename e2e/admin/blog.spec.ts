import { test } from '@playwright/test';

test.describe.parallel('admin panel blog', () => {



  test('go to admin panel', async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: 'playwright/.auth/admin.json',
    })
    const adminPage = await adminContext.newPage();
    await adminPage.goto('/app_admin/marketing/blog/post/create');

    // wait for h2 with text "quick stats"
    await adminPage.waitForSelector('h3:has-text("Create Blog Post")');

  });

})
