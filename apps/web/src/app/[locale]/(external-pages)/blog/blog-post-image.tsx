"use client";

import Image from "next/image";
import { cn } from "@/lib/utils";

interface BlogPostImageProps {
  src: string;
  alt: string;
}

export function BlogPostImage({ src, alt }: BlogPostImageProps) {
  return (
    <>
      <div className="absolute inset-0 animate-pulse bg-gray-100" />
      <Image
        alt={alt}
        className={cn(
          "object-cover",
          "duration-700 ease-in-out",
          "data-[loading=true]:scale-110 data-[loading=true]:blur-2xl data-[loading=true]:grayscale"
        )}
        data-loading="true"
        fill
        loading="lazy"
        onLoad={(event) => {
          const img = event.target as HTMLImageElement;
          img.setAttribute("data-loading", "false");
        }}
        onLoadingComplete={(img) => {
          img.setAttribute("data-loading", "false");
        }}
        sizes="(max-width: 640px) 100vw, (max-width: 768px) 50vw, (max-width: 1024px) 33vw, 25vw"
        src={src}
        unoptimized
      />
    </>
  );
}
