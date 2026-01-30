import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";

/**
 * Schema for registering a Live Activity push token
 */
const registerActivityTokenSchema = z.object({
  deviceId: z.string().uuid(),
  activityId: z.string().min(1),
  pushToken: z.string().min(1),
  apnsEnvironment: z.enum(["sandbox", "production"]).default("sandbox"),
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
 * PUT: Register or update a Live Activity push token
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
    const parseResult = registerActivityTokenSchema.safeParse(body);

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const { deviceId, activityId, pushToken, apnsEnvironment } =
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

    // Upsert the activity token (update if same device + activity_id exists)
    const { data, error } = await supabaseClient
      .from("live_activity_tokens")
      .upsert(
        {
          device_id: deviceId,
          activity_id: activityId,
          push_token: pushToken,
          apns_environment: apnsEnvironment,
          is_active: true,
          updated_at: new Date().toISOString(),
        },
        {
          onConflict: "device_id,activity_id",
        }
      )
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
        message: "Live Activity token registered successfully",
        activityToken: {
          id: data.id,
          activityId: data.activity_id,
          isActive: data.is_active,
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
 * DELETE: Mark a Live Activity as inactive (ended)
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
    const activityId = searchParams.get("activityId");

    if (!(deviceId && activityId)) {
      return NextResponse.json(
        { error: "deviceId and activityId are required" },
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

    // Mark the activity as inactive
    const { error } = await supabaseClient
      .from("live_activity_tokens")
      .update({
        is_active: false,
        updated_at: new Date().toISOString(),
      })
      .eq("device_id", deviceId)
      .eq("activity_id", activityId);

    if (error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500, headers: corsHeaders }
      );
    }

    return NextResponse.json(
      { message: "Live Activity marked as inactive" },
      { headers: corsHeaders }
    );
  } catch (error) {
    return NextResponse.json(
      { error: String(error) },
      { status: 500, headers: corsHeaders }
    );
  }
}
