"use client";
import { CircleUserRound, Copy, Loader, Wand2 } from "lucide-react";
import Image from "next/image";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { generateImageAction } from "@/data/user/dalle";
import { updateUserProfilePictureAction } from "@/data/user/user";
import { zodResolver } from "@/lib/zod-resolver";
import {
  type GenerateImageFormSchemaType,
  generateImageFormSchema,
} from "@/utils/zod-schemas/dalle";
import { FormInput } from "./form-components/form-input";
import { FormSelect } from "./form-components/form-select";
import { Button } from "./ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "./ui/card";
import { Form } from "./ui/form";
import { Skeleton } from "./ui/skeleton";

const generateImageSchema = z.object({
  prompt: z.string().min(1, { message: "Prompt is required" }),
  size: z.string(),
});

export const DallE = () => {
  const [images, setImages] = useState<string[]>([]);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: updateProfilePicture, isPending: isUpdatingProfilePicture } =
    useAction(updateUserProfilePictureAction, {
      onExecute: () => {
        toastRef.current = toast.loading("Updating profile picture...");
      },
      onSuccess: () => {
        toast.success("Profile picture updated successfully", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage =
          error.serverError ?? "Error updating profile picture";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    });

  const { execute: generateImage, status: generateImageStatus } = useAction(
    generateImageAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Generating image...");
      },
      onSuccess: async ({ data }) => {
        toast.success("Image generated successfully", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        if (data) {
          setImages((images) => [...images, ...data]);
        }
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Error generating image";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  const form = useForm<GenerateImageFormSchemaType>({
    defaultValues: {
      prompt: "",
      size: "512x512",
      n: 1,
    },
    resolver: zodResolver(generateImageFormSchema),
  });

  const { control, handleSubmit } = form;

  const onSubmit = (data: GenerateImageFormSchemaType) => {
    generateImage(data);
  };

  return (
    <Card className="mx-auto w-full max-w-3xl">
      <CardHeader>
        <CardTitle>AI Image Generator</CardTitle>
        <CardDescription>
          Create stunning images with DALL-E AI. Simply enter a prompt and
          choose your desired image size.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Form {...form}>
          <form className="space-y-6" onSubmit={handleSubmit(onSubmit)}>
            <FormInput
              control={control}
              id="prompt"
              inputProps={{
                placeholder:
                  "E.g., A serene landscape with mountains and a lake at sunset",
              }}
              label="Image Prompt"
              name="prompt"
            />

            <FormSelect
              control={control}
              id="size"
              label="Image Size"
              name="size"
              options={[
                { label: "Large (1024x1024)", value: "1024x1024" },
                { label: "Medium (512x512)", value: "512x512" },
                { label: "Small (256x256)", value: "256x256" },
              ]}
            />
            <Button
              disabled={generateImageStatus === "executing"}
              type="submit"
            >
              {generateImageStatus === "executing" ? (
                <>
                  <Loader className="mr-2 h-4 w-4 animate-spin" />
                  Generating...
                </>
              ) : (
                <>
                  <Wand2 className="mr-2 h-4 w-4" />
                  Generate Image
                </>
              )}
            </Button>
          </form>
        </Form>

        <div className="mt-8">
          {!images.length && generateImageStatus !== "executing" && (
            <p className="text-center text-muted-foreground">
              Your generated images will appear here. Start by entering a prompt
              above!
            </p>
          )}
          {generateImageStatus === "executing" ? (
            <Skeleton className="mx-auto flex aspect-square w-full max-w-md items-center justify-center bg-background">
              <Loader className="h-8 w-8 animate-spin" />
            </Skeleton>
          ) : (
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
              {images.map((image) => (
                <Card key={image}>
                  <CardContent className="p-4">
                    <div className="relative mb-4 aspect-square w-full">
                      <Image
                        alt="Generated Image"
                        className="rounded-lg object-cover"
                        fill
                        src={image}
                      />
                    </div>
                    <div className="flex flex-col gap-2 sm:flex-row">
                      <Button
                        className="flex flex-1 items-center justify-center"
                        onClick={() => {
                          navigator.clipboard.writeText(image);
                          toast.success("Image URL copied to clipboard");
                        }}
                        variant="outline"
                      >
                        <Copy className="mr-2 h-4 w-4" /> Copy URL
                      </Button>
                      <Button
                        className="flex flex-1 items-center justify-center"
                        disabled={isUpdatingProfilePicture}
                        onClick={() =>
                          updateProfilePicture({ avatarUrl: image })
                        }
                      >
                        <CircleUserRound className="mr-2 h-4 w-4" /> Set as
                        Profile Picture
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
