"use client";

import Image from "next/image";
import { cn } from "@/lib/utils";

interface AuthorProfileImageProps {
  avatarUrl: string;
  name: string;
}

export function AuthorProfileImage({
  avatarUrl,
  name,
}: AuthorProfileImageProps) {
  return (
    <div className="relative h-8 w-8">
      <div className="absolute inset-0 animate-pulse rounded-full bg-gray-100" />
      <Image
        alt={name}
        className={cn(
          "h-full w-full rounded-full object-cover",
          "duration-700 ease-in-out",
          "data-[loading=true]:scale-110 data-[loading=true]:blur-2xl data-[loading=true]:grayscale"
        )}
        data-loading="true"
        height={32}
        loading="lazy"
        onLoad={(event) => {
          const img = event.target as HTMLImageElement;
          img.setAttribute("data-loading", "false");
        }}
        onLoadingComplete={(img) => {
          img.setAttribute("data-loading", "false");
        }}
        src={avatarUrl}
        width={32}
      />
    </div>
  );
}
