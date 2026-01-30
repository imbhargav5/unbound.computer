import { createCoolActionClient } from "next-cool-action";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { serverGetUserType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import { userClaimsSchema } from "@/utils/zod-schemas/user-claims-schema";

export const actionClient = createCoolActionClient({
  handleServerError(e, utils) {
    // You can access these properties inside the `utils` object.
    const { clientInput, bindArgsClientInputs, metadata, ctx } = utils;

    // Log to console.
    console.log("Action error:", e.message);
    // You can optionally return a generic message on production
    // Return generic message
    // if(process.env.NODE_ENV !== 'development') {
    //   return "Oh no, something went wrong!";
    // }
    return e.message;
  },
}).use(async ({ next, clientInput, metadata, bindArgsClientInputs, ctx }) => {
  if (process.env.NODE_ENV === "development") {
    console.log("LOGGING MIDDLEWARE");
    console.log("Bind args client inputs ->", bindArgsClientInputs);
    console.log("Context ->", ctx);
    const startTime = performance.now();

    // Here we await the action execution.
    const result = await next();

    const endTime = performance.now();

    console.log("Result ->", result);
    console.log("Client input ->", clientInput);
    console.log("Metadata ->", metadata);
    console.log("Action execution took", endTime - startTime, "ms");

    return result;
  }
  // In production, just execute the action without logging
  return await next();
});

export const authActionClient = actionClient.use(async ({ next }) => {
  const supabase = await createSupabaseUserServerActionClient();
  const { data, error: userError } = await supabase.auth.getClaims();
  if (userError) {
    console.log("User error", { cause: userError });
    throw new Error("User error", { cause: userError });
  }
  if (!data?.claims) {
    console.log("User not logged in");
    throw new Error("User not logged in");
  }
  const userClaims = userClaimsSchema.parse(data.claims);
  return await next({
    ctx: {
      userId: userClaims.sub,
      userEmail: userClaims.email,
    },
  });
});

export const adminActionClient = authActionClient.use(async ({ next }) => {
  const userType = await serverGetUserType();
  if (userType !== userRoles.ADMIN) {
    throw new Error("User is not an admin");
  }
  return await next();
});
