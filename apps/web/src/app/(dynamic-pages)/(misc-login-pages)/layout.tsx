import { AuthIllustration } from "@/components/authentication/auth-illustration";

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="dark flex min-h-screen bg-black">
      {/* Left Panel - Form */}
      <div className="flex flex-1 flex-col justify-center px-6 py-12 lg:px-8">
        <div className="sm:mx-auto sm:w-full sm:max-w-md">{children}</div>
      </div>

      {/* Right Panel - Illustration */}
      <div className="relative hidden items-center justify-center overflow-hidden border-white/10 border-l bg-black lg:flex lg:flex-1">
        <AuthIllustration />
      </div>
    </div>
  );
}
