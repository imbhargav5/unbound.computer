import { describe, expect, it } from "vitest";
import {
  buildAudienceCapability,
  buildAblyTokenRequestBody,
  buildDaemonFalcoCapability,
  buildMobileCapability,
} from "./route";

describe("Ably token capability builders", () => {
  it("adds session status object-subscribe capability for mobile", () => {
    const capability = buildMobileCapability(
      ["11111111-1111-1111-1111-111111111111"],
      "22222222-2222-2222-2222-222222222222"
    );

    expect(capability["session:*:status"]).toEqual(["object-subscribe"]);
  });

  it("adds session status object-publish capability for daemon_falco", () => {
    const capability = buildDaemonFalcoCapability("22222222-2222-2222-2222-222222222222");

    expect(capability["session:*:status"]).toEqual(["object-publish"]);
  });

  it("buildAudienceCapability keeps session status object-subscribe for mobile", () => {
    const capability = buildAudienceCapability(
      "mobile",
      ["11111111-1111-1111-1111-111111111111"],
      "22222222-2222-2222-2222-222222222222",
      "USER-ID"
    );

    expect(capability["session:*:status"]).toEqual(["object-subscribe"]);
  });

  it("buildAblyTokenRequestBody includes numeric timestamp and nonce", () => {
    const capability = buildMobileCapability(
      ["11111111-1111-1111-1111-111111111111"],
      "22222222-2222-2222-2222-222222222222"
    );
    const body = buildAblyTokenRequestBody(
      "app.key",
      "USER-ID",
      capability
    );

    expect(body.keyName).toBe("app.key");
    expect(body.clientId).toBe("user-id");
    expect(typeof body.timestamp).toBe("number");
    expect(Number.isFinite(body.timestamp)).toBe(true);
    expect(typeof body.nonce).toBe("string");
    expect(body.nonce.length).toBeGreaterThan(0);
  });
});
