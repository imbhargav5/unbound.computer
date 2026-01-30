import { redirect } from "next/navigation";
import { Suspense } from "react";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { LogoutClient } from "./logout-client";

async function LogoutContent() {
  const userClaims = await serverGetLoggedInUserClaims();
  if (userClaims) {
    return <LogoutClient />;
  }
  redirect("/");
}

export default async function Logout() {
  return (
    <Suspense>
      <LogoutContent />
    </Suspense>
  );
}
