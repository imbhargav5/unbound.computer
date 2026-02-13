import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

export const audienceSchema = z.enum(["mobile", "daemon_falco", "daemon_nagato"]);
export type AblyTokenAudience = z.infer<typeof audienceSchema>;

export const requestSchema = z.object({
  deviceId: z.string().uuid(),
  audience: audienceSchema.default("mobile"),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const ABLY_TOKEN_TTL_MS = 60 * 60 * 1000;
const ABLY_TOKEN_ENDPOINT = "https://main.realtime.ably.net";

export type Capability = Record<string, string[]>;

function parseAblyApiKey(rawApiKey: string): { keyName: string; keySecret: string } | null {
  const separatorIndex = rawApiKey.indexOf(":");
  if (separatorIndex <= 0 || separatorIndex >= rawApiKey.length - 1) {
    return null;
  }

  return {
    keyName: rawApiKey.slice(0, separatorIndex),
    keySecret: rawApiKey.slice(separatorIndex + 1),
  };
}

export function buildMobileCapability(deviceIds: string[], requesterDeviceId: string): Capability {
  const normalizedIds = new Set(deviceIds.map((deviceId) => deviceId.toLowerCase()));
  normalizedIds.add(requesterDeviceId.toLowerCase());

  const capability: Capability = {};
  for (const deviceId of normalizedIds) {
    capability[`remote:${deviceId}:commands`] = ["publish", "subscribe"];
    capability[`session:secrets:${deviceId}:${requesterDeviceId.toLowerCase()}`] = ["subscribe"];
  }
  capability["session:*:conversation"] = ["subscribe"];

  return capability;
}

export function buildDaemonNagatoCapability(requesterDeviceId: string): Capability {
  const normalizedRequester = requesterDeviceId.toLowerCase();
  return {
    [`remote:${normalizedRequester}:commands`]: ["subscribe", "publish"],
  };
}

export function buildDaemonFalcoCapability(requesterDeviceId: string, userId: string): Capability {
  const normalizedRequester = requesterDeviceId.toLowerCase();
  const normalizedUser = userId.toLowerCase();
  return {
    "session:*:conversation": ["publish"],
    [`presence:${normalizedUser}`]: ["publish"],
    [`remote:${normalizedRequester}:commands`]: ["publish"],
    [`session:secrets:${normalizedRequester}:*`]: ["publish"],
  };
}

export function buildAudienceCapability(
  audience: AblyTokenAudience,
  deviceIds: string[],
  requesterDeviceId: string,
  userId: string
): Capability {
  const normalizedUser = userId.toLowerCase();
  switch (audience) {
    case "mobile":
      return {
        ...buildMobileCapability(deviceIds, requesterDeviceId),
        [`presence:${normalizedUser}`]: ["subscribe"],
      };
    case "daemon_falco":
      return buildDaemonFalcoCapability(requesterDeviceId, normalizedUser);
    case "daemon_nagato":
      return buildDaemonNagatoCapability(requesterDeviceId);
  }
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function POST(req: NextRequest) {
  try {
    const apiKey = process.env.ABLY_API_KEY?.trim();
    if (!apiKey) {
      return NextResponse.json(
        { error: "Ably API key is not configured on server" },
        { status: 500, headers: corsHeaders }
      );
    }

    const parsedApiKey = parseAblyApiKey(apiKey);
    if (!parsedApiKey) {
      return NextResponse.json(
        { error: "Ably API key format is invalid" },
        { status: 500, headers: corsHeaders }
      );
    }

    const supabaseClient = createSupabaseMobileClient(req);
    const {
      data: { user },
    } = await supabaseClient.auth.getUser();

    if (!user) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders }
      );
    }

    const body = await req.json();
    const parseResult = requestSchema.safeParse(body);
    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const requesterDeviceId = parseResult.data.deviceId.toLowerCase();
    const { audience } = parseResult.data;

    const { data: requesterDevice, error: requesterDeviceError } = await supabaseClient
      .from("devices")
      .select("id, user_id")
      .eq("id", requesterDeviceId)
      .single();

    if (requesterDeviceError || !requesterDevice) {
      return NextResponse.json(
        { error: "Device not found" },
        { status: 404, headers: corsHeaders }
      );
    }

    if (requesterDevice.user_id !== user.id) {
      return NextResponse.json(
        { error: "Forbidden" },
        { status: 403, headers: corsHeaders }
      );
    }

    const { data: userDevices, error: userDevicesError } = await supabaseClient
      .from("devices")
      .select("id")
      .eq("user_id", user.id);

    if (userDevicesError || !userDevices) {
      return NextResponse.json(
        { error: "Failed to load user devices" },
        { status: 500, headers: corsHeaders }
      );
    }

    const capability = buildAudienceCapability(
      audience,
      userDevices.map((device) => String(device.id)),
      requesterDeviceId,
      user.id
    );

    const tokenRequestResponse = await fetch(
      `${ABLY_TOKEN_ENDPOINT}/keys/${encodeURIComponent(parsedApiKey.keyName)}/requestToken`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${Buffer.from(
            `${parsedApiKey.keyName}:${parsedApiKey.keySecret}`
          ).toString("base64")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          clientId: requesterDeviceId,
          ttl: ABLY_TOKEN_TTL_MS,
          capability: JSON.stringify(capability),
        }),
      }
    );

    if (!tokenRequestResponse.ok) {
      const errorBody = await tokenRequestResponse.text();
      return NextResponse.json(
        {
          error: "Failed to request Ably token",
          statusCode: tokenRequestResponse.status,
          details: errorBody,
        },
        { status: 502, headers: corsHeaders }
      );
    }

    const tokenDetails = await tokenRequestResponse.json();
    if (!(tokenDetails && typeof tokenDetails.token === "string" && tokenDetails.token.length > 0)) {
      return NextResponse.json(
        { error: "Ably token response is invalid" },
        { status: 502, headers: corsHeaders }
      );
    }

    return NextResponse.json(tokenDetails, { headers: corsHeaders });
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}
