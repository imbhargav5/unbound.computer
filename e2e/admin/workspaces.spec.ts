import { expect, request, test } from "@playwright/test";
import { getUserDetailsFromAuthJson } from "../_helpers/authjson.helper";
import { onboardUserHelper } from "../_helpers/onboard-user.helper";
import {
  getDefaultWorkspaceInfoHelper,
  goToWorkspaceArea,
  matchPathAndExtractWorkspaceInfo,
} from "../_helpers/workspace.helper";

const INBUCKET_URL = `http://localhost:54324`;

test.describe("Workspace", () => {
  let createdWorkspaceSlug: string | undefined = undefined;
  test("create workspace works correctly", async ({ page }) => {
    const { workspaceSlug } = await getDefaultWorkspaceInfoHelper({ page });
    await page.focus("body");
    // pressing w opens the create workspace dialog
    await page.keyboard.press("w");
    const form = page.getByTestId("create-workspace-form");
    await form.waitFor();
    await form.locator("input#name").fill("Lorem Ipsum");
    // read the slug from the form using data-testid
    const slug = await form.getByTestId("workspace-slug-input").inputValue();
    expect(slug).toBeTruthy();
    await form.getByRole("button", { name: "Create Workspace" }).click();
    // playwright wait for url change
    // there is a locale prefix in the url
    //   await page.waitForURL(/\/[a-z]{2}\/onboarding/);
    // /en/workspace/lorem-ipsum/home
    await page.waitForURL(new RegExp(`/[a-z]{2}/workspace/${slug}/home`));
    // Extract the new workspace slug from the URL
    const {
      workspaceSlug: newWorkspaceSlug,
      workspaceId: newWorkspaceId,
      isSoloWorkspace,
    } = await matchPathAndExtractWorkspaceInfo({ page });
    createdWorkspaceSlug = newWorkspaceSlug;
    expect(newWorkspaceSlug).toBe(slug);
    expect(newWorkspaceId).toBeTruthy();
    expect(isSoloWorkspace).toBe(false);
  });

  test.describe("Workspace invite", () => {
    function getInviteeIdentifier(): string {
      return `johnInvitee${Date.now().toString().slice(-4)}`;
    }

    async function getInvitationEmail(
      username: string,
    ): Promise<{ url: string }> {
      const requestContext = await request.newContext();

      try {
        const response = await requestContext.get(
          `${INBUCKET_URL}/api/v1/search?query=${username}&limit=50`,
        );

        if (!response.ok()) {
          throw new Error(
            `Mailbox not found or not ready yet ${response.status()} for ${username}`,
          );
        }

        const emailResponse = await response.json().catch((error) => {
          throw new Error(`Failed to parse mailbox response: ${error.message}`);
        });

        const messages = emailResponse.messages;

        // Get messages from the last 2 minutes, sorted by date
        const TWO_MINUTES = 2 * 60 * 1000;
        const now = new Date().getTime();
        const recentMessages = messages
          .filter((message) => {
            const messageDate = new Date(message.Created).getTime();
            return now - messageDate < TWO_MINUTES;
          })
          .sort(
            (a, b) =>
              new Date(b.Created).getTime() - new Date(a.Created).getTime(),
          );

        if (recentMessages.length === 0) {
          throw new Error(`No recent messages found for user ${username}`);
        }

        // Try each recent message until we find one with the correct format
        for (const message of recentMessages) {
          try {
            const messageResponse = await requestContext.get(
              `${INBUCKET_URL}/api/v1/message/${message.ID}`,
            );

            if (!messageResponse.ok()) {
              continue; // Try next message if this one fails
            }

            const messageDetails = await messageResponse.json();

            try {
              // Try to extract URL from this message
              const urlMatch = messageDetails.Text.match(
                /View Invitation \( (.+) \)/,
              );
              if (!urlMatch?.[1]) {
                continue; // Try next message if format doesn't match
              }

              return {
                url: urlMatch[1],
              };
            } catch (e) {
              // If this message doesn't match our format, try the next one
              continue;
            }
          } catch (e) {
            // If there's an error fetching this message, try the next one
            continue;
          }
        }

        throw new Error(
          `No valid invitation emails found in the last 2 minutes`,
        );
      } finally {
        await requestContext.dispose();
      }
    }
    test("invite existing user to a workspace", async ({ browser, page }) => {
      const workspaceSlug = createdWorkspaceSlug;
      if (!workspaceSlug) {
        throw new Error("No workspace slug found");
      }

      // Invite the existing user (user2)
      await goToWorkspaceArea({
        page,
        area: "settings/members",
        workspaceSlug: workspaceSlug,
        isSoloWorkspace: false,
      });
      await page.click('button[data-testid="invite-user-button"]');
      const form = page.getByTestId("invite-user-form");
      await form.waitFor();

      // Switch to user2's context
      const user2Context = await browser.newContext({
        storageState: "playwright/.auth/user_2.json",
      });
      const user2Page = await user2Context.newPage();
      const user2Cookies = await user2Context.cookies();
      const user2JWTCookie = user2Cookies.find(
        (cookie) => cookie.name === "sb-localhost-auth-token",
      );
      if (!user2JWTCookie) {
        throw new Error("No user JWT cookie found");
      }
      const user2Details = await getUserDetailsFromAuthJson(
        user2JWTCookie.value,
      );

      const user2Email = user2Details.email; // Adjust this if the email format in user2.setup.ts is different
      await page.fill('input[name="email"]', user2Email);
      await form.getByRole("button", { name: "Invite" }).click();
      await page.locator("text=User invited!").waitFor();

      // Go to invitations page
      await user2Page.goto("/user/invitations");
      await user2Page.click('a:has-text("View Invitation")');

      // Accept the invitation
      await user2Page.click('button:has-text("Accept Invitation")');
      await user2Page.click('button[data-testid="confirm"]');
      await user2Page.locator("text=Invitation accepted!").waitFor();

      // Verify user2 is now a member of the workspace
      await goToWorkspaceArea({
        page: user2Page,
        area: "settings/members",
        workspaceSlug,
        isSoloWorkspace: false,
      });
      const membersTable = user2Page.locator(
        'table[data-testid="members-table"]',
      );
      await membersTable.waitFor();
      const memberRow = membersTable.locator(
        `tr[data-user-id="${user2Details.id}"]`,
      );
      await expect(memberRow).toBeVisible();

      // Clean up: close user2's context
      await user2Context.close();
    });
    test("invite new user to a workspace", async ({ page, browser }) => {
      const workspaceSlug = createdWorkspaceSlug;
      if (!workspaceSlug) {
        throw new Error("No workspace slug found");
      }
      await goToWorkspaceArea({
        page,
        area: "settings/members",
        workspaceSlug: workspaceSlug,
        isSoloWorkspace: false,
      });
      await page.click('button[data-testid="invite-user-button"]');
      const form = page.getByTestId("invite-user-form");
      await form.waitFor();
      const inviteeIdentifier = getInviteeIdentifier();
      const inviteeEmail = `${inviteeIdentifier}@myapp.com`;

      await page.fill('input[name="email"]', inviteeEmail);
      await form.getByRole("button", { name: "Invite" }).click();
      await page.locator("text=User invited!").waitFor();

      await page.goto("/logout");
      let invitationUrl: string | undefined;
      await expect
        .poll(
          async () => {
            try {
              const data = await getInvitationEmail(inviteeIdentifier);
              invitationUrl = data.url;
              return true;
            } catch (error) {
              return false;
            }
          },
          {
            intervals: [1000, 2000, 5000, 10000, 20000],
            timeout: 60000, // Increased timeout
          },
        )
        .toBe(true);

      if (!invitationUrl) {
        throw new Error("No invitation URL received");
      }

      // Create a new context for the invited user
      const inviteeContext = await browser.newContext();
      const inviteePage = await inviteeContext.newPage();

      await inviteePage.goto(invitationUrl);
      await onboardUserHelper({
        page: inviteePage,
        name: `Invitee John ${inviteeIdentifier}`,
      });

      const inviteeCookies = await inviteeContext.cookies();
      const inviteeJWTCookie = inviteeCookies.find(
        (cookie) => cookie.name === "sb-localhost-auth-token",
      );
      if (!inviteeJWTCookie) {
        throw new Error("No user JWT cookie found");
      }
      const inviteeDetails = getUserDetailsFromAuthJson(inviteeJWTCookie.value);

      await inviteePage.goto("/user/invitations");
      await inviteePage.click('a:has-text("View Invitation")');

      await inviteePage.click('button:has-text("Accept Invitation")');
      await inviteePage.click('button[data-testid="confirm"]');
      await inviteePage.locator("text=Invitation accepted!").waitFor();

      await goToWorkspaceArea({
        page: inviteePage,
        area: "settings/members",
        workspaceSlug,
        isSoloWorkspace: false,
      });
      const membersTable = inviteePage.locator(
        'table[data-testid="members-table"]',
      );
      await membersTable.waitFor();
      const memberRow = membersTable.locator(
        `tr[data-user-id="${inviteeDetails.id}"]`,
      );
      await expect(memberRow).toBeVisible();

      // Clean up: close invitee's context
      await inviteeContext.close();
    });
  });
});
