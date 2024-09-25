"use client";
import { Link } from '@/components/intl-link';
import { useChat } from "ai/react";
import { Bot, CircleUser, Share } from "lucide-react";
import type { FormEvent } from "react";
import { Controller, useForm, type SubmitHandler } from "react-hook-form";
import { toast } from "sonner";
import { PostTweetWrapper } from "./post-tweet-wrapper";
import { Button } from "./ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "./ui/card";
import { Checkbox } from "./ui/checkbox";
import { Label } from "./ui/label";
import { ScrollArea } from "./ui/scroll-area";
import { Textarea } from "./ui/textarea";

type PostGenerateFormInput = {
  prompt: string;
  hashtags: boolean;
  premium: boolean;
};

export const PostChatContainer = () => {
  const {
    register,
    handleSubmit,
    control,
  } = useForm<PostGenerateFormInput>({
    defaultValues: {
      prompt: "",
      hashtags: false,
      premium: false,
    },
  });

  const { messages, append, handleSubmit: handleSubmitOpenAi } = useChat();

  const handlePostGenerate: SubmitHandler<PostGenerateFormInput> = (
    data: PostGenerateFormInput,
    e: FormEvent<HTMLFormElement>,
  ) => {

    const promptBase = "Create a detailed post for twitter/X with the following content:";
    const prompt = `${promptBase} ${data.prompt} ${data.hashtags ? ", add hashtags related to the content " : "do not insert hashtags"} ${!data.premium ? "maximun characters 250 " : "250 characters or more, focus on content and mininum of hashtags"}`;

    append({
      role: "user",
      content: prompt,
    });

    handleSubmitOpenAi(e)
  };

  return (
    <div className="flex items-center justify-center">
      <Card className="w-full h-full">
        <CardHeader>
          <CardTitle>Post Generate</CardTitle>
          <CardDescription>Create our post with Chat Bot</CardDescription>
        </CardHeader>
        <CardContent>
          <ScrollArea className="h-[500px]">
            {messages.map((message) => (
              <div className="flex flex-row items-start justify-start gap-2 mt-4" key={message.id}>
                {message.role === "user" && (
                  <>
                    <CircleUser className="size-6" />
                    <div className="flex flex-col items-start gap-2 max-w-3xl">
                      <p className="text-md text-muted-foreground">{message.content}</p>
                    </div>
                  </>
                )}
                {message.role === "assistant" && (
                  <>
                    <Bot className="size-6 text-purple-400" />
                    <div className="flex flex-col items-start gap-2">
                      <PostTweetWrapper>
                        <p className="text-md text-muted-foreground">{message.content}</p>
                      </PostTweetWrapper>
                      <Link href={"https://x.com/compose/post"} target="_blank">
                        <Button className="flex items-center gap-2" onClick={() => {
                          navigator.clipboard.writeText(message.content)
                          toast.success("Copied to clipboard")
                        }}>
                          <Share className="size-4" /> Copy and create a post!
                        </Button>
                      </Link>
                    </div>
                  </>

                )}
              </div>
            ))}
          </ScrollArea>
        </CardContent>
        <CardFooter>
          <form
            className="flex flex-col w-full"
            onSubmit={handleSubmit(handlePostGenerate)}
          >
            <div className="flex flex-col gap-4">
              <Card className="w-full p-4 flex flex-col gap-4">
                <Textarea
                  {...register("prompt")}
                  className="resize-none border-none focus-within:outline-none focus:outline-none focus-visible:ring-0 focus-within:border-none focus:ring-0 focus-visible:ring-offset-0"
                  placeholder="What's the subject of your post?"
                />
                <Button className="self-end" type="submit">Generate Post</Button>
              </Card>
              <div className="flex gap-2 items-center">
                <Controller
                  control={control}
                  render={({ field }) => (
                    <div className="flex items-center space-x-2">
                      <Checkbox
                        checked={field.value}
                        onCheckedChange={(value) => field.onChange(value)}
                        id="hashtag"
                      />
                      <Label
                        htmlFor="hashtag"
                        className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                      >
                        Do you want Hashtags?
                      </Label>
                    </div>
                  )}
                  name="hashtags"
                />
                <Controller
                  control={control}
                  render={({ field }) => (
                    <div className="flex items-center space-x-2">
                      <Checkbox
                        checked={field.value}
                        onCheckedChange={(value) => field.onChange(value)}
                        id="premium"
                      />
                      <Label
                        htmlFor="premium"
                        className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                      >
                        Premium account?
                      </Label>
                    </div>
                  )}
                  name="premium"
                />
              </div>

            </div>
          </form>
        </CardFooter>
      </Card>
    </div>
  );
};
