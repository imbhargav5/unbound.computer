/**
 * v0 by Vercel.
 * @see https://v0.dev/t/GnejQa8qF4r
 * Documentation: https://v0.dev/docs#integrating-generated-code-into-your-nextjs-app
 */
import { WaitlistNavbar } from '@/components/NavigationMenu/ExternalNavbar/WaitlistNavbar';
import { Avatar } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import Link from 'next/link';

export default function Component() {
  return (
    <>
      <WaitlistNavbar />
      <section className="w-full py-12 md:py-24 lg:py-32 xl:py-48">
        <div className="container px-4 md:px-6 space-y-4">
          <div className="flex items-center justify-center">
            <Badge variant="default"> Launching in 2 weeks!</Badge>
          </div>

          <div className="flex flex-col items-center space-y-4 text-center">
            <div className="space-y-2">
              <h1 className="text-4xl font-bold tracking-tighter sm:text-5xl md:text-6xl lg:text-7xl/none leading-tight">
                The complete platform for
                <br />
                building the Web{'\n                          '}
              </h1>
              <p className="mx-auto max-w-[600px] text-gray-500 md:text-xl dark:text-gray-400">
                Give your team the toolkit to stop configuring and start
                innovating. Securely build, deploy, and scale the best web
                experiences.
              </p>
            </div>
            <div className="w-full max-w-sm space-y-2">
              <form className="flex space-x-2">
                <Input
                  className="max-w-lg flex-1"
                  placeholder="Enter your email"
                  type="email"
                />
                <Button>Sign Up</Button>
              </form>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                Sign up to get notified when we launch.
                <Link className="underline underline-offset-2" href="#">
                  Terms & Conditions
                </Link>
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                Hurry! Join the waitlist now to get a discounted offer when the
                app becomes available. 3519 people have already joined. 🎉
              </p>
            </div>
          </div>
        </div>
      </section>
      <div className="container mx-auto grid grid-cols-5 gap-4 py-8">
        <Avatar />
        <Avatar />
        <Avatar />
        <Avatar />
        <Avatar />
      </div>
    </>
  );
}

function FlagIcon(props) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
      <line x1="4" x2="4" y1="22" y2="15" />
    </svg>
  );
}
