import { Link } from "@/components/intl-link";
import { HashLink } from "./hash-link";

interface MdxLinkProps extends React.AnchorHTMLAttributes<HTMLAnchorElement> {
  href?: string;
  children: React.ReactNode;
}

export function MdxLink({ children, href, ...props }: MdxLinkProps) {
  if (!href) {
    return (
      <a href={href} {...props}>
        {children}
      </a>
    );
  }

  const isTocLink = href.startsWith("#");
  if (isTocLink) {
    return (
      <HashLink href={href} {...props}>
        {children}
      </HashLink>
    );
  }

  return (
    <Link href={href} {...props}>
      {children}
    </Link>
  );
}
