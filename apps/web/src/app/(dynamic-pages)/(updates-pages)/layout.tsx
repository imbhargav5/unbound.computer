import { Menu } from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

function UpdatesNavigation() {
  const links = [{ name: "Docs", href: "/docs" }];

  return (
    <nav>
      {/* Mobile Navigation */}
      <div className="flex h-14 items-center md:hidden">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button size="icon" variant="outline">
              <Menu className="h-5 w-5" />
              <span className="sr-only">Toggle navigation menu</span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-48">
            {links.map(({ name, href }) => (
              <DropdownMenuItem asChild key={name}>
                <Suspense>
                  <Link href={href}>{name}</Link>
                </Suspense>
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      {/* Desktop Navigation */}
      <div className="hidden h-14 w-full max-w-4xl items-center md:flex">
        <div className="flex items-center gap-8">
          <ul className="flex items-center gap-8 font-medium">
            {links.map(({ name, href }) => (
              <li
                className="font-regular text-gray-500 text-sm hover:text-gray-800 dark:text-gray-300 dark:hover:text-gray-500"
                key={name}
              >
                <Suspense>
                  <Link href={href}>{name}</Link>
                </Suspense>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </nav>
  );
}

export default async function UpdatesPagesLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative z-0 mx-auto w-full max-w-4xl p-1">
      {/* Decorative top element */}
      <div className="-z-10 pointer-events-none fixed top-0 right-0 left-0 h-64 select-none border-b bg-muted sm:h-52" />
      <UpdatesNavigation />
      <div>{children}</div>
    </div>
  );
}
