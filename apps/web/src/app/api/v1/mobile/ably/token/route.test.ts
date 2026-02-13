import { describe, expect, test } from "vitest";
import {
  buildAudienceCapability,
  requestSchema,
  type Capability,
} from "./route";

const requesterDeviceId = "6f5db7f9-c6ef-4d60-88f8-39f62f272f07";
const userId = "2f42d6c9-95fb-420d-9800-fd83a75e3bc5";

describe("Ably token route schema", () => {
  test("defaults audience to mobile", () => {
    const result = requestSchema.parse({
      deviceId: requesterDeviceId,
    });

    expect(result.audience).toBe("mobile");
  });

  test("rejects invalid audience", () => {
    const result = requestSchema.safeParse({
      deviceId: requesterDeviceId,
      audience: "invalid",
    });

    expect(result.success).toBe(false);
  });
});

describe("buildAudienceCapability", () => {
  test("builds mobile capability with wildcard conversation and normalized IDs", () => {
    const capability = buildAudienceCapability(
      "mobile",
      [
        "12703F8A-39F6-43B9-8D68-FD748CA0B949",
        "12703f8a-39f6-43b9-8d68-fd748ca0b949",
        "3e435221-0a3a-4bad-a5d4-e1e47c7ce2ef",
      ],
      requesterDeviceId.toUpperCase(),
      userId.toUpperCase()
    );

    expect(capability["session:*:conversation"]).toEqual(["subscribe"]);
    expect(capability["presence:2f42d6c9-95fb-420d-9800-fd83a75e3bc5"]).toEqual(["subscribe"]);
    expect(capability["remote:12703f8a-39f6-43b9-8d68-fd748ca0b949:commands"]).toEqual([
      "publish",
      "subscribe",
    ]);
    expect(capability["remote:3e435221-0a3a-4bad-a5d4-e1e47c7ce2ef:commands"]).toEqual([
      "publish",
      "subscribe",
    ]);
    expect(capability[`remote:${requesterDeviceId}:commands`]).toEqual(["publish", "subscribe"]);
    expect(
      capability["session:secrets:12703f8a-39f6-43b9-8d68-fd748ca0b949:6f5db7f9-c6ef-4d60-88f8-39f62f272f07"]
    ).toEqual(["subscribe"]);
  });

  test("builds daemon_nagato capability", () => {
    const capability = buildAudienceCapability(
      "daemon_nagato",
      [],
      requesterDeviceId,
      userId
    ) as Capability;

    expect(capability).toEqual({
      [`remote:${requesterDeviceId}:commands`]: ["subscribe", "publish"],
    });
  });

  test("builds daemon_falco capability", () => {
    const capability = buildAudienceCapability("daemon_falco", [], requesterDeviceId, userId);

    expect(capability).toEqual({
      "session:*:conversation": ["publish"],
      [`presence:${userId}`]: ["publish"],
      [`remote:${requesterDeviceId}:commands`]: ["publish"],
      [`session:secrets:${requesterDeviceId}:*`]: ["publish"],
    });
  });
});
