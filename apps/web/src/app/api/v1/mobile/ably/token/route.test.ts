import { describe, expect, it } from "vitest";
import {
  buildAudienceCapability,
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
    const capability = buildDaemonFalcoCapability(
      "22222222-2222-2222-2222-222222222222",
      "USER-ID"
    );

    expect(capability["session:*:status"]).toEqual(["object-publish"]);
  });

  it("buildAudienceCapability keeps mobile presence subscribe with status object-subscribe", () => {
    const capability = buildAudienceCapability(
      "mobile",
      ["11111111-1111-1111-1111-111111111111"],
      "22222222-2222-2222-2222-222222222222",
      "USER-ID"
    );

    expect(capability["session:*:status"]).toEqual(["object-subscribe"]);
    expect(capability["presence:user-id"]).toEqual(["subscribe"]);
  });
});
