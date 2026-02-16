import { type NextRequest, NextResponse } from "next/server";
import { randomBytes } from "node:crypto";
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
const DEFAULT_ABLY_REST_ENDPOINT = "https://rest.ably.io";

function resolveAblyRestEndpoint(): string {
  const configured = process.env.ABLY_REST_ENDPOINT?.trim();
  if (!configured) {
    return DEFAULT_ABLY_REST_ENDPOINT;
  }
  return configured.replace(/\/+$/, "");
}

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

export function buildAblyTokenRequestBody(
  keyName: string,
  requesterUserId: string,
  capability: Capability
) {
  return {
    keyName,
    clientId: requesterUserId.toLowerCase(),
    ttl: ABLY_TOKEN_TTL_MS,
    capability: JSON.stringify(capability),
    timestamp: Date.now(),
    nonce: randomBytes(16).toString("hex"),
  };
}

function buildAblyTokenRequestURL(keyName: string): string {
  return `${resolveAblyRestEndpoint()}/keys/${encodeURIComponent(keyName)}/requestToken`;
}

function parseAblyErrorBody(rawBody: string): string {
  if (!rawBody) {
    return "No response body";
  }

  try {
    const parsed = JSON.parse(rawBody) as { error?: { message?: string }; message?: string };
    if (parsed.error?.message) {
      return parsed.error.message;
    }
    if (parsed.message) {
      return parsed.message;
    }
  } catch {
    // Fallback to raw text when the body is not JSON.
  }

  return rawBody;
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
  capability["session:*:status"] = ["object-subscribe"];

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
    "session:*:status": ["object-publish"],
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

    const tokenRequestResponse = await fetch(buildAblyTokenRequestURL(parsedApiKey.keyName), {
      method: "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(
          `${parsedApiKey.keyName}:${parsedApiKey.keySecret}`
        ).toString("base64")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        buildAblyTokenRequestBody(parsedApiKey.keyName, user.id, capability)
      ),
    });

    if (!tokenRequestResponse.ok) {
      const errorBody = parseAblyErrorBody(await tokenRequestResponse.text());
      return NextResponse.json(
        {
          error: "Failed to request Ably token",
          statusCode: tokenRequestResponse.status,
          statusText: tokenRequestResponse.statusText,
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
