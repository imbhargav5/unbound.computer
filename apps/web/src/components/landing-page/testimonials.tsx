import Image from "next/image";
import { reviews } from "@/data/anon/reviews";
import { cn } from "@/utils/cn";
import { Marquee } from "../magicui/marquee";
import TitleBlock from "../title-block";

export default function Testimonials() {
  const firstRow = reviews.slice(0, 3);
  const secondRow = reviews.slice(3, 6);

  return (
    <section className="bg-muted/40 px-6 py-24">
      <div className="mx-auto max-w-6xl space-y-8">
        <TitleBlock
          subtitle="Hear what our satisfied customers have to say about Outbound"
          title="Don't  take our word for it"
        />
        <div className="relative flex h-full w-full flex-col items-center justify-center overflow-hidden pt-10">
          <Marquee className="[--duration:20s]" pauseOnHover>
            {firstRow.map((review) => (
              <ReviewCard key={review.username} {...review} />
            ))}
          </Marquee>
          <Marquee className="[--duration:20s]" pauseOnHover reverse>
            {secondRow.map((review) => (
              <ReviewCard key={review.username} {...review} />
            ))}
          </Marquee>
          <div className="pointer-events-none absolute inset-y-0 left-0 w-1/3 bg-linear-to-r from-muted/40" />
          <div className="pointer-events-none absolute inset-y-0 right-0 w-1/3 bg-linear-to-l from-muted/40" />
        </div>
      </div>
    </section>
  );
}

const ReviewCard = ({
  img,
  name,
  username,
  body,
}: {
  img: string;
  name: string;
  username: string;
  body: string;
}) => (
  <figure
    className={cn(
      "relative w-64 cursor-pointer overflow-hidden rounded-xl border p-4",
      "border-border bg-background hover:bg-accent-foreground hover:text-background"
    )}
  >
    <div className="flex flex-row items-center gap-2">
      <Image alt="" className="rounded-full" height="32" src={img} width="32" />
      <div className="flex flex-col">
        <figcaption className="font-medium text-sm">{name}</figcaption>
        <p className="font-medium text-xs">{username}</p>
      </div>
    </div>
    <blockquote className="mt-2 text-sm">{body}</blockquote>
  </figure>
);
