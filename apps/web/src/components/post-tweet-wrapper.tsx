import { HeartIcon, MessageCircleIcon, UploadIcon } from "lucide-react";
import type React from "react";
import { Avatar, AvatarFallback, AvatarImage } from "./ui/avatar";
import { Card } from "./ui/card";

type Props = {
  children: React.ReactNode;
};

export const PostTweetWrapper = ({ children }: Props) => (
  <Card className="max-w-md p-4">
    <div className="mb-4 flex items-center space-x-2">
      <Avatar>
        <AvatarImage
          alt="User avatar"
          src="/placeholder.svg?height=40&width=40"
        />
        <AvatarFallback>E.G</AvatarFallback>
      </Avatar>
      <div>
        <div className="text-sm">@username</div>
        <div className="text-muted-foreground text-xs">
          {new Date().toLocaleString()}
        </div>
      </div>
    </div>
    <div className="mb-4 text-sm">{children}</div>
    <div className="flex items-center justify-between px-8 text-sm">
      <MessageCircleIcon className="size-4 text-muted-foreground hover:text-foreground" />

      <HeartIcon className="size-4 text-muted-foreground hover:text-foreground" />

      <UploadIcon className="size-4 text-muted-foreground hover:text-foreground" />
    </div>
  </Card>
);
