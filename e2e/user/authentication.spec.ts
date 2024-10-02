import { expect, request, test } from '@playwright/test';
import { getUserIdHelper } from 'e2e/_helpers/get-user-id.helper';
import { loginUserHelper } from 'e2e/_helpers/login-user.helper';
import { onboardUserHelper } from 'e2e/_helpers/onboard-user.helper';
import { getDefaultWorkspaceInfoHelper, matchPathAndExtractWorkspaceInfo } from 'e2e/_helpers/workspace.helper';
import { uniqueId } from 'lodash';

const INBUCKET_URL = `http://localhost:54324`;

test.describe.serial("Workspace", () => {

  test("create workspace works correctly", async ({ page }) => {
    const { workspaceSlug } = await getDefaultWorkspaceInfoHelper({ page });
    await page.focus('body');
    // pressing w opens the create workspace dialog
    await page.keyboard.press('w');
    const form = page.getByTestId('create-workspace-form');
    await form.waitFor();
    await form.locator('input#name').fill("Lorem Ipsum");
    // read the slug from the form using data-testid
    const slug = await form.getByTestId('workspace-slug-input').inputValue();
    console.log(slug);
    expect(slug).toBeTruthy();
    await form.getByRole('button', { name: 'Create Workspace' }).click();
    // playwright wait for url change
    // there is a locale prefix in the url
    //   await page.waitForURL(/\/[a-z]{2}\/onboarding/);
    // /en/workspace/lorem-ipsum/home
    await page.waitForURL(new RegExp(`/[a-z]{2}/workspace/${slug}/home`));
    // Extract the new workspace slug from the URL
    const { workspaceSlug: newWorkspaceSlug, workspaceId: newWorkspaceId, isSoloWorkspace } = await matchPathAndExtractWorkspaceInfo({ page });
    expect(newWorkspaceSlug).toBe(slug);
    expect(newWorkspaceId).toBeTruthy();
    expect(isSoloWorkspace).toBe(false);
  });

  test.describe("Workspace invite", () => {
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

    test("invite user to a workspace", async ({ page }) => {
      const { workspaceSlug } = await getDefaultWorkspaceInfoHelper({ page });

      await page.goto(`/${workspaceSlug}/settings/members`);
      await page.click('button[data-testid="invite-user-button"]');

      const inviteeIdentifier = getInviteeIdentifier();
      const inviteeEmail = `${inviteeIdentifier}@myapp.com`;

      await page.fill('input[name="email"]', inviteeEmail);
      await page.click('button:has-text("Invite")');
      await page.locator("text=User invited!").waitFor();

      await page.goto("/logout");
      let invitationUrl: string | undefined = undefined;
      await expect.poll(async () => getInvitationEmail(inviteeIdentifier).then(data => {
        invitationUrl = data.url;
        return true;
      }), {
        intervals: [1000, 2000, 5000, 10000, 20000],
        timeout: 10000,
      }).toBe(true);

      if (!invitationUrl) {
        throw new Error("No invitation URL received");
      }

      await page.goto(invitationUrl);
      await page.waitForURL('/onboarding');
      await onboardUserHelper({ page, name: `Invitee John ${inviteeIdentifier}` });

      const inviteeUserId = await getUserIdHelper({ page });

      await page.goto("/user/invitations");
      await page.click('a:has-text("View Invitation")');

      await page.click('button:has-text("Accept Invitation")');
      await page.click('button[data-testid="confirm"]');
      await page.locator("text=Invitation accepted!").waitFor();

      await page.goto(`/${workspaceSlug}/settings/members`);
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
    await matchPathAndExtractWorkspaceInfo({ page });
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

    await matchPathAndExtractWorkspaceInfo({ page });
    await page.goto('/user/settings/security');
    const email = await page.locator('input[name="email"]').getAttribute('value');
    expect(email).toBeTruthy();

    await page.goto('/logout');
    await page.goto('/forgot-password');
    await page.fill('input[name="email"]', email!);
    await page.click('button:has-text("Reset password")');
    await page.locator('text="A password reset link has been sent to your email!"').waitFor();

    const identifier = email!.split('@')[0];
    let resetPasswordUrl: string | undefined = undefined;
    await expect.poll(() => getResetPasswordEmail(identifier).then(data => {
      resetPasswordUrl = data.url;
      return true;
    }), {
      intervals: [1000, 2000, 5000, 10000, 20000],
    }).toBe(true);

    if (!resetPasswordUrl) {
      throw new Error('No reset password URL received');
    }

    await page.goto(resetPasswordUrl);
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
