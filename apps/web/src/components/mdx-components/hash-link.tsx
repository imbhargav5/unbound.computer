"use client";
import React, { type ComponentProps, useEffect } from "react";
import { cn } from "@/utils/cn";

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
    isActive ? "font-bold text-blue-500!" : "font-normal"
  );
  return (
    <a className={className} href={href} {...props}>
      {children}
    </a>
  );
};
