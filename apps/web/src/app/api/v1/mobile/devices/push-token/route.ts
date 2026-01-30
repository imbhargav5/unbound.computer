import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

/**
 * Schema for registering an APNs push token
 */
const registerPushTokenSchema = z.object({
  deviceId: z.string().uuid(),
  apnsToken: z.string().min(1),
  apnsEnvironment: z.enum(["sandbox", "production"]).default("sandbox"),
  pushEnabled: z.boolean().default(true),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

/**
 * OPTIONS handler for CORS preflight
 */
export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

/**
 * PUT: Register or update an APNs push token for a device
 */
export async function PUT(req: NextRequest) {
  try {
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
    const parseResult = registerPushTokenSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const { deviceId, apnsToken, apnsEnvironment, pushEnabled } =
      parseResult.data;

    // Verify the device belongs to this user
    const { data: existingDevice, error: deviceError } = await supabaseClient
      .from("devices")
      .select("id, user_id")
      .eq("id", deviceId)
      .single();

    if (deviceError || !existingDevice) {
      return NextResponse.json(
        { error: "Device not found" },
        { status: 404, headers: corsHeaders }
      );
    }

    if (existingDevice.user_id !== user.id) {
      return NextResponse.json(
        { error: "Forbidden" },
        { status: 403, headers: corsHeaders }
      );
    }

    // Update the device with the push token
    const { data, error } = await supabaseClient
      .from("devices")
      .update({
        apns_token: apnsToken,
        apns_environment: apnsEnvironment,
        push_enabled: pushEnabled,
        apns_token_updated_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", deviceId)
      .select()
      .single();

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(
      {
        message: "Push token registered successfully",
        device: {
          id: data.id,
          pushEnabled: data.push_enabled,
          apnsEnvironment: data.apns_environment,
        },
      },
      { headers: corsHeaders }
    );
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}

/**
 * DELETE: Disable push notifications for a device
 */
export async function DELETE(req: NextRequest) {
  try {
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

    const { searchParams } = new URL(req.url);
    const deviceId = searchParams.get("deviceId");

    if (!deviceId) {
      return NextResponse.json(
        { error: "deviceId is required" },
        { status: 400, headers: corsHeaders }
      );
    }

    // Verify the device belongs to this user
    const { data: existingDevice, error: deviceError } = await supabaseClient
      .from("devices")
      .select("id, user_id")
      .eq("id", deviceId)
      .single();

    if (deviceError || !existingDevice) {
      return NextResponse.json(
        { error: "Device not found" },
        { status: 404, headers: corsHeaders }
      );
    }

    if (existingDevice.user_id !== user.id) {
      return NextResponse.json(
        { error: "Forbidden" },
        { status: 403, headers: corsHeaders }
      );
    }

    // Clear push token and disable push notifications
    const { error } = await supabaseClient
      .from("devices")
      .update({
        apns_token: null,
        push_enabled: false,
        apns_token_updated_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", deviceId);

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(
      { message: "Push notifications disabled" },
      { headers: corsHeaders }
    );
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}
