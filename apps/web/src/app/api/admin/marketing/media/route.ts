import { type NextRequest, NextResponse } from "next/server";
import urlJoin from "url-join";
import { v4 as uuidv4 } from "uuid";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { isSupabaseUserClaimAppAdmin } from "@/utils/is-supabase-user-app-admin";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

const ALLOWED_IMAGE_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
];
const ALLOWED_VIDEO_TYPES = ["video/mp4", "video/webm", "video/quicktime"];
const MAX_IMAGE_SIZE = 10 * 1024 * 1024; // 10MB
const MAX_VIDEO_SIZE = 100 * 1024 * 1024; // 100MB

function getMediaTypeFromMimeType(mimeType: string): "image" | "video" | "gif" {
  if (mimeType === "image/gif") {
    return "gif";
  }
  if (mimeType.startsWith("video/")) {
    return "video";
  }
  return "image";
}

export async function POST(request: NextRequest) {
  try {
    const claims = await serverGetLoggedInUserClaims();

    // Check admin role using utility function
    if (!isSupabaseUserClaimAppAdmin(claims)) {
      return NextResponse.json(
        { error: "Admin access required" },
        { status: 403 }
      );
    }

    // 2. Get media category (blog or changelog)
    const searchParams = request.nextUrl.searchParams;
    const mediaCategory = searchParams.get("type"); // 'blog' or 'changelog'

    if (!(mediaCategory && ["blog", "changelog"].includes(mediaCategory))) {
      return NextResponse.json(
        { error: "Invalid media type. Must be 'blog' or 'changelog'" },
        { status: 400 }
      );
    }

    // 3. Parse FormData
    const formData = await request.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    // 4. Validate file type
    const mimeType = file.type.toLowerCase();
    const isImage = ALLOWED_IMAGE_TYPES.includes(mimeType);
    const isVideo = ALLOWED_VIDEO_TYPES.includes(mimeType);

    if (!(isImage || isVideo)) {
      return NextResponse.json(
        {
          error:
            "Invalid file type. Allowed: JPEG, PNG, WebP, GIF, MP4, WebM, MOV",
        },
        { status: 400 }
      );
    }

    // 5. Validate file size
    const maxSize = isVideo ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE;
    if (file.size > maxSize) {
      return NextResponse.json(
        {
          error: `File too large. Max size: ${maxSize / (1024 * 1024)}MB`,
        },
        { status: 400 }
      );
    }

    // 6. Generate unique filename
    const extension = file.name.split(".").pop()?.toLowerCase() || "bin";
    const uniqueFileName = `${uuidv4()}.${extension}`;
    const storagePath = `marketing/${mediaCategory}-media/${uniqueFileName}`;

    // 7. Upload to Supabase using admin client (has service role key)
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    const { error: uploadError } = await supabaseAdminClient.storage
      .from("marketing-assets")
      .upload(storagePath, buffer, {
        contentType: mimeType,
        upsert: false,
      });

    if (uploadError) {
      console.error("Upload error:", uploadError);
      return NextResponse.json({ error: "Upload failed" }, { status: 500 });
    }

    // 8. Construct public URL
    const publicUrl = urlJoin(
      process.env.NEXT_PUBLIC_SUPABASE_URL || "",
      "/storage/v1/object/public/marketing-assets",
      storagePath
    );

    // 9. Determine media type for response
    const detectedType = getMediaTypeFromMimeType(mimeType);

    return NextResponse.json({ url: publicUrl, type: detectedType });
  } catch (error) {
    console.error("Media upload error:", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
