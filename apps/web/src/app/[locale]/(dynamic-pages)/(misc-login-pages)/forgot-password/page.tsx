import { Suspense } from "react";
import { ForgotPassword } from "./forgot-password";

export default function ForgotPasswordPage() {
  return (
    <Suspense>
      <ForgotPassword />
    </Suspense>
  );
}
