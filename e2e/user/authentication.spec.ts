import { expect, request, test } from "@playwright/test";
import { matchPathAndExtractWorkspaceInfo } from "e2e/_helpers/workspace.helper";
import { uniqueId } from "lodash";

const INBUCKET_URL = `http://localhost:54324`;
// test("Users can Login", async ({ page }) => {
//   await page.goto("/user/settings/security");
//   const emailAddress = await page
//     .locator('input[name="email"]')
//     .getAttribute("value");
//   expect(emailAddress).toBeTruthy();
//   if (!emailAddress) {
//     throw new Error("Email not found");
//   }
//   await page.goto("/logout");
//   await loginUserHelper({ page, emailAddress });
//   await matchPathAndExtractWorkspaceInfo({ page });
// });

test("Users can update password", async ({ page }) => {
  await page.goto("/user/settings/security");
  const email = await page.locator('input[name="email"]').getAttribute("value");
  expect(email).toBeTruthy();
  if (!email) {
    throw new Error("Email not found");
  }
  const newPassword = `password-${uniqueId()}`;
  await page.fill('input[name="password"]', newPassword);
  await page.click('button:has-text("Update Password")');
  await page.locator("text=Password updated!").waitFor();

  await page.goto("/logout");
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(newPassword);
  await page.click('button:text-is("Login")');
  await page.locator("text=Logged in!").waitFor();
});

test("Users can forget password and reset", async ({ page }) => {
  async function getResetPasswordEmail(
    username: string,
  ): Promise<{ url: string }> {
    const requestContext = await request.newContext();
    const messages = await requestContext
      .get(`${INBUCKET_URL}/api/v1/mailbox/${username}`)
      .then((res) => res.json());
    const latestMessage = messages[0];

    if (latestMessage) {
      const message = await requestContext
        .get(`${INBUCKET_URL}/api/v1/mailbox/${username}/${latestMessage.id}`)
        .then((res) => res.json());
      const urlMatch = message.body.text.match(/Reset password \( (.+) \)/);
      if (!urlMatch) throw new Error("Email format unexpected");
      return { url: urlMatch[1] };
    }

    throw new Error("No email received");
  }

  await matchPathAndExtractWorkspaceInfo({ page });
  await page.goto("/user/settings/security");
  const email = await page.locator('input[name="email"]').getAttribute("value");
  expect(email).toBeTruthy();

  await page.goto("/logout");
  await page.goto("/forgot-password");
  if (!email) {
    throw new Error("Email not found");
  }
  await page.fill('input[name="email"]', email);
  await page.click('button:has-text("Reset password")');
  await page
    .locator('text="A password reset link has been sent to your email!"')
    .waitFor();

  const identifier = email.split("@")[0];
  let resetPasswordUrl: string | undefined = undefined;
  await expect
    .poll(
      () =>
        getResetPasswordEmail(identifier).then((data) => {
          resetPasswordUrl = data.url;
          return true;
        }),
      {
        intervals: [1000, 2000, 5000, 10000, 20000],
      },
    )
    .toBe(true);

  if (!resetPasswordUrl) {
    throw new Error("No reset password URL received");
  }

  await page.goto(resetPasswordUrl);
  await page.waitForURL("/update-password");
  await page.fill('input[name="password"]', "newpassword");
  await page.click('button:has-text("Confirm Password")');
  await page.waitForURL("/dashboard");

  await page.goto("/logout");
  await page.goto("/login");
  await page.fill('input[data-strategy="email-password"]', email);
  await page.fill('input[name="password"]', "newpassword");
  await page.click('button[type="submit"]');
  await page.waitForURL("/dashboard");
});
