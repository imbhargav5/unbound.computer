"use client";
import Link, { LinkProps } from "next/link";
import { usePathname, useRouter } from "next/navigation";
import React, { ComponentProps, useEffect } from "react";
import { match } from "path-to-regexp";
import { cn } from "@/utils/cn";

type TocListItemProps = {
  children: ({ isActive }: { isActive: boolean }) => React.ReactNode;
  hash: string;
};

const useLocationHash = () => {
  const [hash, setHash] = React.useState<string | null>(null);

  useEffect(() => {
    const onHashChange = () => {
      console.log(window.location.hash);
      setHash(window.location.hash);
    };
    window.addEventListener("hashchange", onHashChange);
    onHashChange();
    return () => {
      window.removeEventListener("hashchange", onHashChange);
    };
  }, []);

  return hash;
};

export const HashLink = ({
  href,
  children,
  className: classNameProp,
  ...props
}: ComponentProps<"a">) => {
  const currentLocationHash = useLocationHash();
  const isActive = currentLocationHash === href;
  const className = cn(
    classNameProp,
    "hash-link",
    isActive ? "font-bold !text-blue-500" : "font-normal",
  );
  return (
    <a href={href} className={className} {...props}>
      {children}
    </a>
  );
};
