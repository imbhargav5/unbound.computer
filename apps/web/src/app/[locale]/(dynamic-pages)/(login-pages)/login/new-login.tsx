import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export function NewLoginPage() {
  return (
    <div className="flex min-h-screen">
      <div className="flex w-1/2 items-center justify-center bg-gray-100">
        <Card className="w-full max-w-md p-4">
          <div className="mb-4 text-center">
            <h2 className="font-bold text-2xl">Welcome Back</h2>
            <p className="text-muted-foreground">
              Please log in to your account
            </p>
          </div>
          <Tabs className="w-full" defaultValue="magic-link">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="magic-link">Magic Link</TabsTrigger>
              <TabsTrigger value="email-password">Email & Password</TabsTrigger>
            </TabsList>
            <TabsContent value="magic-link">
              <form className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    placeholder="Enter your email"
                    type="email"
                  />
                </div>
                <Button>Send Magic Link</Button>
              </form>
            </TabsContent>
            <TabsContent value="email-password">
              <form className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    placeholder="Enter your email"
                    type="email"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="password">Password</Label>
                  <Input
                    id="password"
                    placeholder="Enter your password"
                    type="password"
                  />
                </div>
                <Button>Login</Button>
              </form>
            </TabsContent>
          </Tabs>
          <div className="my-4">
            <div className="text-center text-muted-foreground text-sm">
              Or login with
            </div>
            <div className="mt-2 flex flex-col space-y-2">
              <Button
                className="flex w-full items-center justify-center"
                variant="outline"
              >
                <ChromeIcon className="mr-2 h-5 w-5" />
                Google
              </Button>
              <Button
                className="flex w-full items-center justify-center"
                variant="outline"
              >
                <GithubIcon className="mr-2 h-5 w-5" />
                Github
              </Button>
              <Button
                className="flex w-full items-center justify-center"
                variant="outline"
              >
                <TwitterIcon className="mr-2 h-5 w-5" />
                Twitter
              </Button>
            </div>
          </div>
          <div className="flex justify-between text-muted-foreground text-sm">
            <Link className="block" href="#" prefetch={false}>
              Already have an account?
            </Link>
            <Link className="block" href="#" prefetch={false}>
              Forgot password?
            </Link>
          </div>
        </Card>
      </div>
      <div className="h-screen w-1/2">
        <img
          alt="Background Image"
          className="h-full w-full object-cover"
          height={800}
          src="/placeholder.svg"
          width={1200}
        />
      </div>
    </div>
  );
}

function ChromeIcon(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      fill="none"
      height="24"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <circle cx="12" cy="12" r="10" />
      <circle cx="12" cy="12" r="4" />
      <line x1="21.17" x2="12" y1="8" y2="8" />
      <line x1="3.95" x2="8.54" y1="6.06" y2="14" />
      <line x1="10.88" x2="15.46" y1="21.94" y2="14" />
    </svg>
  );
}

function GithubIcon(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      fill="none"
      height="24"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
      <path d="M9 18c-4.51 2-5-2-7-2" />
    </svg>
  );
}

function TwitterIcon(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      fill="none"
      height="24"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M22 4s-.7 2.1-2 3.4c1.6 10-9.4 17.3-18 11.6 2.2.1 4.4-.6 6-2C3 15.5.5 9.6 3 5c2.2 2.6 5.6 4.1 9 4-.9-4.2 4-6.6 7-3.8 1.1 0 3-1.2 3-1.2z" />
    </svg>
  );
}

function XIcon(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      fill="none"
      height="24"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
      width="24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </svg>
  );
}
