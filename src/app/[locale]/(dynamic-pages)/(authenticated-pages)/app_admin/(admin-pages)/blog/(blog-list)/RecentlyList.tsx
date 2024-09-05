import { getAllBlogPosts } from "@/data/admin/internal-blog";
import Image from "next/image";
import Link from "next/link";

type Props = {
  typeList: "draft" | "published";
};

export const SmallBlogPostList = async ({ typeList }: Props) => {
  const blogs = await getAllBlogPosts({ status: typeList });
  if (blogs.length === 0) {
    return <div className="text-muted-foreground text-sm">No posts</div>;
  }
  return (
    <div className="flex flex-col gap-4">
      {blogs.map((blog) => (
        <Link href={`/blog/${blog.id}`} key={blog.id} className="flex flex-row gap-4 items-center border-input border rounded-lg p-2 hover:bg-accent transition-colors duration-200 ease-in-out">
          <div className="relative size-14 lg:size-18 xl:size-20 rounded-lg">
            <Image src={blog.cover_image ?? ""} alt={blog.title} fill className="object-cover rounded-lg" />
          </div>

          <div>
            <h3 className="text-md font-bold">{blog.title}</h3>
            <p className="text-muted-foreground text-sm">{blog.summary.slice(0, 30)}...</p>
          </div>

        </Link>
      ))}
    </div>
  );
};

