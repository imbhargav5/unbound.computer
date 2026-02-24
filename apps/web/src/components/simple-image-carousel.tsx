"use client";

import Image from "next/image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
} from "@/components/ui/carousel";
import { Typography } from "./ui/typography-ui";

interface ImageObject {
  alt: string;
  src: string;
}

interface SimpleImageCarouselProps {
  images: ImageObject[];
}

export function SimpleImageCarousel({ images }: SimpleImageCarouselProps) {
  return (
    <Carousel
      className="mx-auto w-full"
      opts={{
        loop: false,
      }}
    >
      <CarouselContent>
        {images.map((image, index) => (
          <CarouselItem key={index}>
            <div className="space-y-1 px-1 pt-2 pb-4">
              <div className="relative aspect-video overflow-hidden rounded-lg">
                <Image
                  alt={image.alt}
                  blurDataURL="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="
                  className="object-cover"
                  fill
                  placeholder="blur"
                  quality={100}
                  sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
                  src={image.src}
                />
              </div>
              <Typography.Subtle>{image.alt}</Typography.Subtle>
            </div>
          </CarouselItem>
        ))}
      </CarouselContent>
      {images.length > 1 && (
        <>
          <CarouselNext />
          <CarouselPrevious />
        </>
      )}
    </Carousel>
  );
}
