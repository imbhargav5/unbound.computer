"use client";
import { Link } from "@/components/intl-link";
import { zodResolver } from "@hookform/resolvers/zod";
import { useChat } from "ai/react";
import { Bot, CircleUser, Send, Share, Trash2 } from "lucide-react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { PostTweetWrapper } from "./post-tweet-wrapper";
import { Button } from "./ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "./ui/card";
import { Checkbox } from "./ui/checkbox";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
} from "./ui/form";
import { ScrollArea } from "./ui/scroll-area";
import { Textarea } from "./ui/textarea";

const postGenerateSchema = z.object({
  prompt: z
    .string()
    .min(1, { message: "Prompt is required" })
    .max(280, { message: "Prompt must be 280 characters or less" }),
  hashtags: z.boolean(),
});

type PostGenerateFormInput = z.infer<typeof postGenerateSchema>;

export const PostChatContainer = () => {
  const form = useForm<PostGenerateFormInput>({
    resolver: zodResolver(postGenerateSchema),
    defaultValues: {
      prompt: "",
      hashtags: false,
    },
  });

  const {
    messages,
    append,
    handleSubmit: handleSubmitOpenAi,
    setMessages,
  } = useChat();

  const onSubmit = (
    data: PostGenerateFormInput,
    event: React.FormEvent<HTMLFormElement>,
  ) => {
    const promptBase =
      "Create a detailed post for twitter/X with the following content:";
    const prompt = `${promptBase} ${data.prompt} ${data.hashtags ? ", add hashtags related to the content " : "do not insert hashtags"} maximum characters 250`;

    append({
      role: "user",
      content: prompt,
    });

    handleSubmitOpenAi(event);
  };

  const resetForm = () => {
    form.reset();
    setMessages([]);
  };

  return (
    <Card className="w-full max-w-3xl mx-auto">
      <CardHeader>
        <CardTitle>AI Post Generator</CardTitle>
        <CardDescription>
          Create engaging social media posts with our AI assistant
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ScrollArea className="h-[400px] mb-4 border rounded-md p-4">
          {messages.map((message) => (
            <div className="flex items-start gap-3 mb-4" key={message.id}>
              {message.role === "user" ? (
                <CircleUser className="mt-1 size-6 text-blue-500" />
              ) : (
                <Bot className="mt-1 size-6 text-purple-500" />
              )}
              <div className="flex flex-col gap-1">
                <p className="text-sm font-medium">
                  {message.role === "user" ? "You" : "AI Assistant"}
                </p>
                {message.role === "assistant" ? (
                  <PostTweetWrapper>
                    <p className="text-sm text-muted-foreground">
                      {message.content}
                    </p>
                  </PostTweetWrapper>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    {message.content}
                  </p>
                )}
                {message.role === "assistant" && (
                  <Link
                    href="https://x.com/compose/post"
                    target="_blank"
                    className="mt-2"
                  >
                    <Button
                      variant="outline"
                      size="sm"
                      className="flex items-center gap-2"
                      onClick={() => {
                        navigator.clipboard.writeText(message.content);
                        toast.success("Copied to clipboard");
                      }}
                    >
                      <Share className="size-4" /> Copy and Open Twitter
                    </Button>
                  </Link>
                )}
              </div>
            </div>
          ))}
        </ScrollArea>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="prompt"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Post Content</FormLabel>
                  <FormControl>
                    <Textarea
                      {...field}
                      placeholder="What would you like to post about?"
                      className="resize-none"
                    />
                  </FormControl>
                  <FormDescription>
                    Enter the main content or topic for your post. Our AI will
                    expand on this to create an engaging tweet.
                  </FormDescription>
                </FormItem>
              )}
            />
            <div className="flex items-center gap-6">
              <FormField
                control={form.control}
                name="hashtags"
                render={({ field }) => (
                  <FormItem className="flex items-center space-x-2">
                    <FormControl>
                      <Checkbox
                        checked={field.value}
                        onCheckedChange={field.onChange}
                      />
                    </FormControl>
                    <FormLabel className="text-sm font-medium leading-none">
                      Include Hashtags
                    </FormLabel>
                  </FormItem>
                )}
              />
            </div>
            <div className="flex gap-4">
              <Button type="submit" className="flex-1">
                <Send className="mr-2 size-4" /> Generate Post
              </Button>
              <Button type="button" variant="outline" onClick={resetForm}>
                <Trash2 className="mr-2 size-4" /> Reset
              </Button>
            </div>
          </form>
        </Form>
      </CardContent>
    </Card>
  );
};
