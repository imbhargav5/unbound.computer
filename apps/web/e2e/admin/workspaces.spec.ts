import { expect, request, test } from "@playwright/test";
import { getUserDetailsFromAuthJson } from "../_helpers/authjson.helper";
import {
  inbucketEmailMessageDetailSchema,
  inbucketEmailSchema,
} from "../_helpers/inbucket-email-schema";
import { onboardUserHelper } from "../_helpers/onboard-user.helper";
import { ensureSidebarIsOpen } from "../_helpers/sidebar.helper";
import { getSupabaseClaimsFromContext } from "../_helpers/supabase.helper";
import {
  getDefaultWorkspaceInfoHelper,
  goToWorkspaceArea,
  matchPathAndExtractWorkspaceInfo,
} from "../_helpers/workspace.helper";

const INBUCKET_URL = "http://localhost:54324";

test.describe("Workspace", () => {
  test.describe.configure({ mode: "serial" });

  let createdWorkspaceSlug: string;

  test("create workspace works correctly", async ({ page }) => {
    await getDefaultWorkspaceInfoHelper({ page });

    // Wait for page to fully load
    await page.waitForLoadState("networkidle");

    // Ensure sidebar is open before interacting with it
    await ensureSidebarIsOpen(page);

    // Wait for workspace switcher to load (inside Suspense) and click it
    const workspaceSwitcher = page.getByTestId("workspace-switcher-trigger");
    await workspaceSwitcher.waitFor();
    await workspaceSwitcher.click();

    // Click Create Workspace in dropdown
    await page.getByTestId("ws-create-workspace-trigger").click();

    // Wait for dialog
    const form = page.getByTestId("create-workspace-form");
    await expect(form).toBeVisible();

    // Fill workspace name
    const nameInput = form.locator("input#name");
    await nameInput.fill("Lorem Ipsum");

    // Wait for slug to auto-generate by checking it has a value
    const slugInput = form.getByTestId("workspace-slug-input");
    await expect(slugInput).toHaveValue(/.+/);
    const slug = await slugInput.inputValue();

    // Submit form by clicking the button
    await form.getByRole("button", { name: "Create Workspace" }).click();

    // Wait for navigation to new workspace
    await page.waitForURL(new RegExp(`/[a-z]{2}/workspace/${slug}/home`), {
      timeout: 20_000,
    });

    // Extract and verify workspace info
    const { workspaceSlug: newWorkspaceSlug, workspaceId: newWorkspaceId } =
      await matchPathAndExtractWorkspaceInfo({ page });

    createdWorkspaceSlug = newWorkspaceSlug;
    expect(newWorkspaceSlug).toBe(slug);
    expect(newWorkspaceId).toBeTruthy();
  });

  test.describe("Workspace invite", () => {
    function getInviteeIdentifier(): string {
      return `johnInvitee${Date.now().toString().slice(-4)}`;
    }

    async function getInvitationEmail(
      username: string
    ): Promise<{ url: string }> {
      const requestContext = await request.newContext();

      try {
        const response = await requestContext.get(
          `${INBUCKET_URL}/api/v1/search?query=${username}&limit=50`
        );

        if (!response.ok()) {
          throw new Error(
            `Mailbox not found or not ready yet ${response.status()} for ${username}`
          );
        }

        const emailResponse = await response.json();
        const parsedEmailResponse = inbucketEmailSchema.parse(emailResponse);
        const messages = parsedEmailResponse.messages;

        // Get messages from the last 2 minutes, sorted by date
        const TWO_MINUTES = 2 * 60 * 1000;
        const now = Date.now();
        const recentMessages = messages
          .filter((message) => {
            const messageDate = new Date(message.Created).getTime();
            return now - messageDate < TWO_MINUTES;
          })
          .sort(
            (a, b) =>
              new Date(b.Created).getTime() - new Date(a.Created).getTime()
          );

        if (recentMessages.length === 0) {
          throw new Error(`No recent messages found for user ${username}`);
        }

        // Try each recent message until we find one with the correct format
        for (const message of recentMessages) {
          const messageResponse = await requestContext.get(
            `${INBUCKET_URL}/api/v1/message/${message.ID}`
          );

          if (!messageResponse.ok()) {
            continue;
          }

          const messageDetailsResponse = await messageResponse.json();
          const messageDetails = inbucketEmailMessageDetailSchema.parse(
            messageDetailsResponse
          );

          const urlMatch = messageDetails.Text.match(
            /View Invitation \( (.+) \)/
          );
          if (urlMatch?.[1]) {
            return { url: urlMatch[1] };
          }
        }

        throw new Error(
          "No valid invitation emails found in the last 2 minutes"
        );
      } finally {
        await requestContext.dispose();
      }
    }

    test("invite existing user to a workspace", async ({ browser, page }) => {
      expect(createdWorkspaceSlug).toBeTruthy();

      // Navigate to members settings
      await goToWorkspaceArea({
        page,
        area: "settings/members",
        workspaceSlug: createdWorkspaceSlug,
        workspaceType: "team",
      });

      // Open invite dialog
      await page.getByTestId("invite-user-button").click();
      const form = page.getByTestId("invite-user-form");
      await expect(form).toBeVisible();

      // Get user2's email from their context
      const user2Context = await browser.newContext({
        storageState: "playwright/.auth/user_2.json",
      });
      const user2Page = await user2Context.newPage();
      const user2Details = await getSupabaseClaimsFromContext(user2Context);

      // Fill and submit invite form
      await form
        .getByRole("textbox", { name: "email" })
        .fill(user2Details.email);
      await form.getByRole("button", { name: "Invite" }).click();
      // Wait for the "Invited!" text to appear before checking for the invitation row
      await expect(
        form.getByRole("button", { name: "Invited!" })
      ).toBeVisible();
      // Wait for the invitation row to appear in the table
      await page.getByTestId(`invitation-row-${user2Details.email}`).waitFor();

      // User2 accepts the invitation
      await user2Page.goto("/user/invitations", {
        waitUntil: "domcontentloaded",
      });

      const firstInvitationButton = user2Page
        .getByRole("link", { name: "View Invitation" })
        .first();

      await firstInvitationButton.waitFor();
      const firstInvitationId =
        await firstInvitationButton.getAttribute("data-invitation-id");
      // Wait for the invitation table to load and link to be visible
      await firstInvitationButton.click();

      try {
        await user2Page.waitForURL(/\/(en|de)\/user\/invitations\/[^/]+\/?$/, {
          waitUntil: "domcontentloaded",
          timeout: 5000,
        });
      } catch {
        await user2Page.goto(`/en/user/invitations/${firstInvitationId}`, {
          waitUntil: "domcontentloaded",
        });
      }

      const dialogAcceptInvitationTrigger = user2Page.getByTestId(
        "dialog-accept-invitation-trigger"
      );
      await dialogAcceptInvitationTrigger.waitFor();

      await dialogAcceptInvitationTrigger.click();
      await user2Page.getByTestId("confirm").click();

      // Wait for navigation to workspace after accepting
      await user2Page.waitForURL(/\/(en|de)\/workspace\/.*\//, {
        timeout: 20_000,
      });

      // Verify user2 is now a member
      await goToWorkspaceArea({
        page: user2Page,
        area: "settings/members",
        workspaceSlug: createdWorkspaceSlug,
        workspaceType: "team",
      });

      const membersTable = user2Page.getByTestId("members-table").first();
      await expect(membersTable).toBeVisible();

      const memberRow = membersTable.locator(
        `tr[data-user-id="${user2Details.sub}"]`
      );
      await expect(memberRow).toBeVisible();

      await user2Context.close();
    });

    test("invite new user to a workspace", async ({ page, browser }) => {
      expect(createdWorkspaceSlug).toBeTruthy();

      // Navigate to members settings
      await goToWorkspaceArea({
        page,
        area: "settings/members",
        workspaceSlug: createdWorkspaceSlug,
        workspaceType: "team",
      });

      // Open invite dialog
      await page.getByTestId("invite-user-button").click();
      const form = page.getByTestId("invite-user-form");
      await expect(form).toBeVisible();

      // Create unique invitee email
      const inviteeIdentifier = getInviteeIdentifier();
      const inviteeEmail = `${inviteeIdentifier}@myapp.com`;

      // Fill and submit invite form
      await form.getByRole("textbox", { name: "email" }).fill(inviteeEmail);
      await form.getByRole("button", { name: "Invite" }).click();
      // Wait for the "Invited!" text to appear before checking for the invitation row
      await expect(
        form.getByRole("button", { name: "Invited!" })
      ).toBeVisible();
      // Wait for the invitation row to appear in the table
      await page.getByTestId(`invitation-row-${inviteeEmail}`).waitFor();

      // Poll for invitation email
      let invitationUrl: string | undefined;
      await expect
        .poll(
          async () => {
            try {
              const data = await getInvitationEmail(inviteeIdentifier);
              invitationUrl = data.url;
              return true;
            } catch {
              return false;
            }
          },
          {
            intervals: [1000, 2000, 5000, 10_000],
            timeout: 60_000,
          }
        )
        .toBe(true);

      if (!invitationUrl) {
        throw new Error("No invitation URL received");
      }

      // New user follows invitation link and onboards
      const inviteeContext = await browser.newContext();
      const inviteePage = await inviteeContext.newPage();

      await inviteePage.goto(invitationUrl);
      await onboardUserHelper({
        page: inviteePage,
        name: `Invitee John ${inviteeIdentifier}`,
      });

      // Get invitee's user ID from cookies
      const inviteeCookies = await inviteeContext.cookies();
      const inviteeJWTCookie = inviteeCookies.find(
        (cookie) => cookie.name === "sb-localhost-auth-token"
      );
      if (!inviteeJWTCookie) {
        throw new Error("No auth cookie found for invitee");
      }
      const inviteeDetails = getUserDetailsFromAuthJson(inviteeJWTCookie.value);

      // Accept the invitation
      await inviteePage.goto("/user/invitations", {
        waitUntil: "domcontentloaded",
      });
      const invitationLink = inviteePage
        .getByRole("link", { name: "View Invitation" })
        .first();
      await invitationLink.waitFor();
      const invitationId =
        await invitationLink.getAttribute("data-invitation-id");
      await invitationLink.click();
      try {
        await inviteePage.waitForURL(
          /\/(en|de)\/user\/invitations\/[^/]+\/?$/,
          {
            timeout: 5000,
          }
        );
      } catch {
        await inviteePage.goto(`/en/user/invitations/${invitationId}`, {
          waitUntil: "domcontentloaded",
        });
      }

      await inviteePage.getByTestId("dialog-accept-invitation-trigger").click();
      await inviteePage.getByTestId("confirm").click();
      await expect(inviteePage.getByText("Invitation accepted!")).toBeVisible();

      // Verify invitee is now a member
      await goToWorkspaceArea({
        page: inviteePage,
        area: "settings/members",
        workspaceSlug: createdWorkspaceSlug,
        workspaceType: "team",
      });

      const membersTable = inviteePage.getByTestId("members-table").first();
      await expect(membersTable).toBeVisible();

      const memberRow = membersTable.locator(
        `tr[data-user-id="${inviteeDetails.id}"]`
      );
      await expect(memberRow).toBeVisible();

      await inviteeContext.close();
    });
  });
});
