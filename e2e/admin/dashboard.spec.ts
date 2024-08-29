import { expect, test } from '@playwright/test';
import { dashboardDefaultOrganizationIdHelper } from '../_helpers/dashboard-default-organization-id.helper';

test.describe.parallel('admin panel', () => {
  test.beforeEach(async ({ browser }, testInfo) => {
    testInfo.setTimeout(testInfo.timeout + 10000);
  });

  test('dashboard for a user with profile', async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: 'playwright/.auth/admin.json',
    });
    const adminPage = await adminContext.newPage();
    await dashboardDefaultOrganizationIdHelper({ page: adminPage });

    const anchorElement = await adminPage.locator('[data-testid="admin-panel-link"]');
    await expect(anchorElement).toHaveAttribute('tagName', 'A', { ignoreCase: true });
    await expect(anchorElement).toHaveText('Admin Panel');
  });

  test('go to admin panel', async ({ browser }) => {
    const adminContext = await browser.newContext({
      storageState: 'playwright/.auth/admin.json',
    });
    const adminPage = await adminContext.newPage();
    await adminPage.goto('/app_admin');

    await expect(adminPage.locator('h2:has-text("Quick Stats")')).toBeVisible({ timeout: 10000 });
  });
});
