import { AspectRatio } from "@radix-ui/react-aspect-ratio";
import type { Tables } from "database/types";
import { formatDistance } from "date-fns";
import { CalendarDaysIcon } from "lucide-react";
import Image from "next/image";
import { TiptapJSONContentToHTML } from "@/components/tiptap-json-content-to-html";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

type Props = {
  changelogs: Tables<"marketing_changelog">[];
};

export const ChangelogPosts = async ({ changelogs }: Props) => (
  <>
    {changelogs.map((changelog, index) => (
      <div
        className="mx-auto grid max-w-5xl grid-cols-5 gap-4 md:p-8"
        key={changelog.id}
      >
        <div className="col-span-1 mb-8 flex flex-col gap-2">
          {changelog.created_at ? (
            <div className="items-center md:flex">
              <CalendarDaysIcon className="mr-2 text-muted-foreground" />
              <span className="w-fit text-muted-foreground text-sm">
                {formatDistance(new Date(changelog.created_at), new Date(), {
                  addSuffix: true,
                })}
              </span>
            </div>
          ) : null}
          {index === 0 && <Badge className="mr-2 w-fit p-2 px-4">NEW</Badge>}
        </div>
        <div className="col-span-4 mb-8 space-y-4">
          {changelog.cover_image && (
            <div className="rounded-lg bg-black 2xl:px-2 2xl:py-12">
              <div className="mx-auto w-full max-w-4xl">
                <AspectRatio ratio={16 / 9}>
                  <Image
                    alt="Changelog cover image"
                    className="rounded-lg object-cover"
                    fill
                    src={changelog.cover_image}
                  />
                </AspectRatio>
              </div>
            </div>
          )}
          <h1 className="font-bold text-2xl">{changelog.title}</h1>
          <div className="max-w-(--breakpoint-lg)">
            <TiptapJSONContentToHTML jsonContent={changelog.json_content} />
          </div>
          <Separator />
        </div>
      </div>
    ))}
  </>
);
