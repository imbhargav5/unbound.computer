"use client";
import { generateImageAction } from "@/data/user/dalle";
import { updateUserProfilePictureAction } from "@/data/user/user";
import { GenerateImageSchemaType } from "@/utils/zod-schemas/dalle";
import { zodResolver } from "@hookform/resolvers/zod";
import { CircleUserRound, Copy, Loader } from "lucide-react";
import { useAction } from "next-safe-action/hooks";
import Image from "next/image";
import { useRef, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Label } from "./ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
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
    },
  );

  const {
    register,
    handleSubmit,
    control,
    formState: { errors },
  } = useForm<GenerateImageSchemaType>({
    defaultValues: {
      prompt: "",
      size: "512x512",
    },
    resolver: zodResolver(generateImageSchema),
  });

  return (
    <div className="flex flex-col gap-4">
      {errors.prompt && (
        <div className="text-red-500">{errors.prompt.message}</div>
      )}
      <form
        onSubmit={handleSubmit(generateImage)}
        className="grid grid-cols-8 gap-4 max-w-2xl items-end"
      >
        <div className="col-span-4">
          <Label>Prompt</Label>
          <Input type="text" {...register("prompt")} />
        </div>

        <div className="col-span-2">
          <Label>Size</Label>
          <Controller
            control={control}
            name="size"
            render={({ field }) => (
              <Select
                defaultValue="256x256"
                value={field.value}
                onValueChange={field.onChange}
              >
                <SelectTrigger>
                  <SelectValue>{field.value}</SelectValue>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="1024x1024">1024x1024</SelectItem>
                  <SelectItem value="512x512">512x512</SelectItem>
                  <SelectItem value="256x256">256x256</SelectItem>
                </SelectContent>
              </Select>
            )}
          />
        </div>
        <Button className="col-span-2" type="submit">
          Generate
        </Button>
      </form>
      {!images.length && <div>Your images will be rendered here!</div>}
      {generateImageStatus !== "executing" ? (
        <div className="flex flex-row gap-4">
          {images.map((image) => (
            <div key={image} className="flex flex-col gap-4">
              <div className="relative h-96 w-96 max-w-screen">
                <Image
                  src={image}
                  className="rounded-lg"
                  alt="Generated Image"
                  key={image}
                  fill
                />
              </div>

              <div className="w-full flex flex-row gap-4">
                <Button
                  className="flex flex-row gap-2"
                  onClick={() => {
                    navigator.clipboard.writeText(image);
                    toast.success("Copied to clipboard");
                  }}
                >
                  <Copy className="size-4" /> Copy link
                </Button>
                <Button
                  disabled={isUpdatingProfilePicture}
                  className="flex flex-row gap-2"
                  onClick={() => updateProfilePicture({ avatarUrl: image })}
                >
                  {" "}
                  <CircleUserRound className="size-4" /> Use as Profile Picture
                </Button>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex flex-row gap-4">
          <div className="col-span-8">
            <Skeleton className="w-96 h-96 bg-background max-w-screen flex gap-2 items-center justify-center">
              <Loader className="size-4 animate-spin" />
              <p>Generating...</p>
            </Skeleton>
          </div>
        </div>
      )}
    </div>
  );
};
