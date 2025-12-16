import { redirect } from "next/navigation";
import { Suspense } from "react";
import { serverGetLoggedInUserVerified } from "@/utils/server/server-get-logged-in-user";
import { UpdatePassword } from "./update-password";

async function UpdatePasswordWrapper() {
  try {
    // sensitive operation.
    // recheck user
    await serverGetLoggedInUserVerified();
    return <UpdatePassword />;
  } catch (error) {
    redirect("/logout");
  }
}

export default function UpdatePasswordPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <UpdatePasswordWrapper />
    </Suspense>
  );
}
