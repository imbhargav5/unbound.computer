import { expect, request, test } from '@playwright/test';
import { getUserIdHelper } from 'e2e/_helpers/get-user-id.helper';
import { loginUserHelper } from 'e2e/_helpers/login-user.helper';
import { onboardUserHelper } from 'e2e/_helpers/onboard-user.helper';
import { uniqueId } from 'lodash';
import { dashboardDefaultOrganizationIdHelper, extractOrganizationIdFromUrl } from '../_helpers/dashboard-default-organization-id.helper';

const INBUCKET_URL = `http://localhost:54324`;

test.describe.serial("Organization", () => {
  let defaultOrganizationSlug: string;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    defaultOrganizationSlug = await dashboardDefaultOrganizationIdHelper({ page });
    await context.close();
  });

  test("create organization works correctly", async ({ page }) => {
    await page.goto("/dashboard");
    await page.locator('button[name="organization-switcher"]').waitFor();

    await page.click('button[name="organization-switcher"]');
    await page.click('button:has-text("New Organization")');

    const form = page.locator('form:has-text("Create Organization")');
    await form.waitFor();
    await form.locator("input[name='organizationTitle']").fill("Lorem Ipsum");

    await form.locator('button:has-text("Create Organization")').click();

    const organizationSlug = await extractOrganizationIdFromUrl({ page });

    await page.goto(`/${organizationSlug}/settings`);

    // const editForm = page.locator('form[data-testid="edit-organization-title-form"]');
    // await editForm.waitFor();
    // await editForm.locator('input[name="organizationTitle"]').fill("Lorem Ipsum 2");
    // await editForm.locator('button:has-text("Update")').click();

    // await page.locator("text=Organization information updated!").waitFor();
  });

  test.describe("Organization invite", () => {
    function getInviteeIdentifier(): string {
      return `johnInvitee${Date.now().toString().slice(-4)}`;
    }

    async function getInvitationEmail(username: string): Promise<{ url: string }> {
      const requestContext = await request.newContext();
      const messages = await requestContext.get(`${INBUCKET_URL}/api/v1/mailbox/${username}`).then(res => res.json());
      const latestMessage = messages[0];

      if (latestMessage) {
        const message = await requestContext.get(`${INBUCKET_URL}/api/v1/mailbox/${username}/${latestMessage.id}`).then(res => res.json());
        const url = message.body.text.match(/View Invitation \( (.+) \)/)[1];
        return { url };
      }

      throw new Error("No email received");
    }

    test("invite user to an organization", async ({ page }) => {
      await page.goto(`/${defaultOrganizationSlug}/settings/members`);
      await page.click('button[data-testid="invite-user-button"]');

      const inviteeIdentifier = getInviteeIdentifier();
      const inviteeEmail = `${inviteeIdentifier}@myapp.com`;

      await page.fill('input[name="email"]', inviteeEmail);
      await page.click('button:has-text("Invite")');
      await page.locator("text=User invited!").waitFor();

      await page.goto("/logout");

      const { url } = await expect.poll(() => getInvitationEmail(inviteeIdentifier), {
        intervals: [1000, 2000, 5000, 10000, 20000],
      });

      await page.goto(url);
      await page.waitForURL('/onboarding');
      await onboardUserHelper({ page, name: `Invitee John ${inviteeIdentifier}` });

      const inviteeUserId = await getUserIdHelper({ page });

      await page.goto("/user/invitations");
      await page.click('a:has-text("View Invitation")');

      await page.click('button:has-text("Accept Invitation")');
      await page.click('button[data-testid="confirm"]');
      await page.locator("text=Invitation accepted!").waitFor();

      await page.goto(`/${defaultOrganizationSlug}/settings/members`);
      const membersTable = page.locator('table[data-testid="members-table"]');
      await membersTable.waitFor();
      const memberRow = membersTable.locator(`tr[data-user-id="${inviteeUserId}"]`);
      await expect(memberRow).toBeVisible();
    });
  });
});

test.describe.serial('Authentication', () => {
  test('login works correctly', async ({ page }) => {
    await page.goto('/user/settings/security');
    const emailAddress = await page.locator('input[name="email"]').getAttribute('value');
    expect(emailAddress).toBeTruthy();

    await page.goto('/logout');
    await loginUserHelper({ page, emailAddress: emailAddress! });
    await dashboardDefaultOrganizationIdHelper({ page });
  });

  test('update password should work', async ({ page }) => {
    await page.goto('/user/settings/security');
    const email = await page.locator('input[name="email"]').getAttribute('value');
    expect(email).toBeTruthy();

    const newPassword = `password-${uniqueId()}`;
    await page.fill('input[name="password"]', newPassword);
    await page.click('button:has-text("Update Password")');
    await page.locator('text=Password updated!').waitFor();

    await page.goto('/logout');
    await page.goto('/login');
    await page.fill('input[data-strategy="email-password"]', email!);
    await page.fill('input[name="password"]', newPassword);
    await page.click('button:text-is("Login")');
    await page.locator('text=Logged in!').waitFor();
  });

  test('forgot password works correctly', async ({ page }) => {
    async function getResetPasswordEmail(username: string): Promise<{ url: string }> {
      const requestContext = await request.newContext();
      const messages = await requestContext.get(`${INBUCKET_URL}/api/v1/mailbox/${username}`).then(res => res.json());
      const latestMessage = messages[0];

      if (latestMessage) {
        const message = await requestContext.get(`${INBUCKET_URL}/api/v1/mailbox/${username}/${latestMessage.id}`).then(res => res.json());
        const urlMatch = message.body.text.match(/Reset password \( (.+) \)/);
        if (!urlMatch) throw new Error('Email format unexpected');
        return { url: urlMatch[1] };
      }

      throw new Error('No email received');
    }

    await dashboardDefaultOrganizationIdHelper({ page });
    await page.goto('/user/settings/security');
    const email = await page.locator('input[name="email"]').getAttribute('value');
    expect(email).toBeTruthy();

    await page.goto('/logout');
    await page.goto('/forgot-password');
    await page.fill('input[name="email"]', email!);
    await page.click('button:has-text("Reset password")');
    await page.locator('text="A password reset link has been sent to your email!"').waitFor();

    const identifier = email!.split('@')[0];
    const { url } = await expect.poll(() => getResetPasswordEmail(identifier), {
      intervals: [1000, 2000, 5000, 10000, 20000],
    });

    await page.goto(url);
    await page.waitForURL('/update-password');
    await page.fill('input[name="password"]', 'newpassword');
    await page.click('button:has-text("Confirm Password")');
    await page.waitForURL('/dashboard');

    await page.goto('/logout');
    await page.goto('/login');
    await page.fill('input[data-strategy="email-password"]', email!);
    await page.fill('input[name="password"]', 'newpassword');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
  });
});
