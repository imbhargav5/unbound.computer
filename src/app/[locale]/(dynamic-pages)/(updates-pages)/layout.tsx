import { Link } from "@/components/intl-link";

function UpdatesNavigation() {
  const links = [
    { name: "Docs", href: "/docs" },
    { name: "Community Support", href: "/feedback" },
    { name: "Blog", href: "/blog" },
    { name: "Changelog", href: "/changelog" },
    { name: "Roadmap", href: "/roadmap" },
  ];

  return (
    <nav className="">
      <div className="flex h-14 max-w-screen-2xl items-center">
        <div className="flex items-center gap-8">
          <ul className="flex gap-8 font-medium items-center">
            {links.map(({ name, href }) => (
              <li
                key={name}
                className="text-gray-500 dark:text-gray-300 font-regular text-sm hover:text-gray-800 dark:hover:text-gray-500"
              >
                <Link href={href}>{name}</Link>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </nav>
  );
}

export default function PublicLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative z-0 max-w-4xl mx-auto">
      {/* Decorative top element */}
      <div className="fixed top-0 left-0 right-0 h-64 sm:h-52 -z-10 pointer-events-none select-none bg-muted border-b" />
      <UpdatesNavigation />
      <div>{children}</div>
    </div>
  );
}
