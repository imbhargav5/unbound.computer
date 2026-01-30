"use client";

import { usePostHog } from "posthog-js/react";
import { useEffect } from "react";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";

export default function PosthogIdentify({
  userClaims,
}: {
  userClaims: UserClaimsSchemaType;
}) {
  const posthog = usePostHog();
  useEffect(() => {
    posthog.identify(userClaims.sub);
  }, [userClaims]);

  return null;
}
