"use client";

import type { BlogPostWithTags } from "@/app/[locale]/(dynamic-pages)/(authenticated-pages)/app_admin/(admin-pages)/blog/(blog-list)/page";
import { TabsList } from "@radix-ui/react-tabs";
import { format } from "date-fns";
import { CalendarDays, Grid2X2, List, MoveUpRight, SquarePen } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useWindowSize } from "rooks";
import { Avatar, AvatarFallback, AvatarImage } from "../ui/avatar";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card } from "../ui/card";
import { Separator } from "../ui/separator";
import { Tabs, TabsContent, TabsTrigger } from "../ui/tabs";

type Props = {
  blogs: BlogPostWithTags[];
};

const BlogViews = ({ blogs }: Props) => {
  const [view, setView] = useState("grid");
  const width = useWindowSize();

  useEffect(() => {
    if (width?.innerWidth && width.innerWidth < 768) {
      setView("list");
    }
  }, [width]);
  return (
    <Tabs defaultValue="grid" value={view} onValueChange={setView} className="w-full grid grid-cols-5">

      <TabsList className="rounded-md bg-muted flex p-2 w-fit self-end justify-self-end col-start-5">
        <TabsTrigger value="list">
          <div className="flex gap-2 items-center">
            <List className="size-4" /> <p>List</p>
          </div>
        </TabsTrigger>
        <TabsTrigger value="grid" className="hidden md:flex">
          <div className="flex gap-2 items-center">
            <Grid2X2 className="size-4" /> <p>Grid</p>
          </div>
        </TabsTrigger>
      </TabsList>

      <TabsContent value="list" className="col-span-5">
        <div className="flex flex-col gap-4">
          {blogs.map((blog) => (
            <Card className="p-4 px-8 flex-col md:flex-row flex items-center justify-between w-full min-h-56 hover:bg-accent transition-colors duration-200 ease-in-out group">
              <div className="flex flex-col gap-2 justify-center">
                <div className="flex items-center gap-4 w-full">
                  <Avatar className="size-6">
                    <AvatarFallback className="bg-muted">
                      NA
                    </AvatarFallback>
                    <AvatarImage src={blog.author?.avatar_url || ""} alt={blog.title} />

                  </Avatar>
                  <p>{blog.author?.display_name}</p>
                  <Separator className="w-8 rotate-90" />
                  <div className="flex items-center gap-2">
                    <CalendarDays className="size-4" />
                    <p className="text-sm md:text-base">{format(new Date(blog.created_at), "do MMMM yyyy")}</p>
                  </div>
                </div>
                <h2 className="text-3xl font-bold mt-2">{blog.title}</h2>

                <p className="text-muted-foreground">
                  {
                    blog.summary.slice(0, 100)
                  }
                  {blog.summary.length > 100 && "..."}</p>
                <div>
                  {blog.tags.map((tag) => (
                    <Badge
                      variant={"secondary"}
                      key={tag.id}
                      className="text-muted-foreground"
                    >
                      {tag.name}
                    </Badge>
                  ))}
                </div>
              </div>
              <div className="flex gap-8 items-center self-end md:self-center">
                <Button variant="outline" className="rounded-full p-4 h-fit bg-accent hover:bg-background group-hover:bg-background border-transparent hover:border-input" asChild>
                  <Link href={`/app_admin/blog/post/${blog.id}/edit`}>
                    <SquarePen className="size-4" />
                  </Link>
                </Button>
                <Button variant="outline" className="rounded-full p-4 h-fit bg-accent hover:bg-background group-hover:bg-background border-transparent hover:border-input" asChild>
                  <Link href={`/blog/${blog.slug}`}>
                    <MoveUpRight className="size-4" />
                  </Link>
                </Button>
                <div className="relative h-32 w-32 hidden md:flex rounded-lg">
                  <Image
                    src={blog.cover_image || ""}
                    alt={blog.title}
                    fill
                    className="object-cover rounded-lg"
                  />
                </div>
              </div>
            </Card>
          ))}
        </div>
      </TabsContent>
      <TabsContent value="grid" className="col-span-5">
        <div className="grid grid-cols-2 gap-8 col-span-5 w-full">
          {blogs.map((blog) => (
            <Link
              href={`/app_admin/blog/post/${blog.id}/edit`}
              className="group col-span-1"
            >
              <Card
                key={blog.id}
                className="p-4 space-y-4 group-hover:bg-accent transition-colors duration-200 ease-in-out min-h-[292px]"
              >
                <div className="relative h-32">
                  <Image
                    src={blog.cover_image || ""}
                    alt={blog.title}
                    fill
                    className="object-cover"
                  />
                </div>

                <div className="flex justify-between">
                  <div>
                    <h2 className="text-lg font-bold">{blog.title}</h2>
                    <p className="text-muted-foreground text-sm lg:text-base">
                      {
                        blog.summary.slice(0, 60)
                      }
                      {blog.summary.length > 60 && "..."}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <MoveUpRight className="size-4" />
                  </div>
                </div>

                <div className="flex gap-4">
                  {blog.tags.length > 0 && <div className="flex gap-2 overflow-x-auto">
                    {blog.tags.map((tag) => (
                      <Badge
                        variant={"secondary"}
                        key={tag.id}
                        className="text-muted-foreground col-span-1"
                      >
                        {tag.name}
                      </Badge>
                    ))}
                  </div>}

                  <Badge
                    variant={"outline"}
                    className="text-muted-foreground col-span-1"
                  >
                    {format(new Date(blog.created_at), "do MMMM yyyy")}
                  </Badge>
                </div>
              </Card>
            </Link>
          ))}
        </div>
      </TabsContent>
    </Tabs>
  );
};

export default BlogViews;
