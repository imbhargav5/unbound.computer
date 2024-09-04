"use client";
import { convertAndUploadOpenAiImageAction } from "@/data/user/chats";
import { updateUserProfileNameAndAvatarAction } from "@/data/user/user";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { SAPayload } from "@/types";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation } from "@tanstack/react-query";
import axios from "axios";
import { CircleUserRound, Copy, Loader } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import { Controller, useForm, type SubmitHandler } from "react-hook-form";
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


type OpenAIImageList = { created: string; data: { b64_json: string }[] };

const generateImageSchema = z.object({
  prompt: z.string().min(1, { message: "Prompt is required" }),
  size: z.string(),
});

export const DallE = () => {
  const [images, setImages] = useState<string[]>([]);

  const { mutate: updateProfilePictureMutation } = useSAToastMutation(async (data: { avatarUrl: string }) => {
    return await updateUserProfileNameAndAvatarAction(data);
  }, {
    successMessage: "Profile picture updated successfully",
    errorMessage: "Error updating profile picture"
  });

  const { mutate: generateImageMutation, isLoading } = useMutation(
    async (data: { prompt: string; size: string }): Promise<SAPayload<OpenAIImageList>> => {
      try {
        const { data: response } = await axios.post("/api/generate-image", {
          prompt: data.prompt,
          size: data.size,
        });
        return {
          status: "success",
          data: response as unknown as OpenAIImageList,
        };
      } catch (error) {
        return {
          status: "error",
          message: error.message,
        };
      }
    },
    {
      onSuccess: async (response) => {
        if (response.status === "success") {
          const openAIResponse = response.data as unknown as OpenAIImageList;
          const b64Data = openAIResponse.data[0].b64_json;

          try {
            const image = await convertAndUploadOpenAiImageAction(b64Data);
            if (image.status === "success" && image.data) {
              setImages([image.data]);
            }
          } catch (error) {
            console.error("Error uploading image:", error);
          }
        }
      },
    },
  );

  const onSubmit: SubmitHandler<{
    prompt: string;
    size: string;
  }> = (data) => {
    generateImageMutation(data);
  };


  const { register, handleSubmit, control, formState: { errors } } = useForm({
    defaultValues: {
      prompt: "",
      size: "512x512",
    },
    resolver: zodResolver(generateImageSchema),
  });

  return (
    <div className="flex flex-col gap-4">
      {errors.prompt && <div className="text-red-500">{errors.prompt.message}</div>}
      <form onSubmit={handleSubmit(onSubmit)} className="grid grid-cols-8 gap-4 max-w-2xl items-end">
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
              <Select defaultValue="256x256" value={field.value} onValueChange={field.onChange}>
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
        <Button className="col-span-2" type="submit">Generate</Button>
      </form>
      {!images.length && <div>
        Your images will be rendered here!
      </div>}
      {!isLoading ? <div className="flex flex-row gap-4">
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
              <Button className="flex flex-row gap-2" onClick={() => {
                navigator.clipboard.writeText(image)
                toast.success("Copied to clipboard")
              }}><Copy className="size-4" /> Copy link</Button>
              <Button className="flex flex-row gap-2" onClick={() => updateProfilePictureMutation({ avatarUrl: image })}> <CircleUserRound className="size-4" /> Use as Profile Picture</Button>
            </div>
          </div>
        ))}
      </div> : <div className="flex flex-row gap-4">
        <div className="col-span-8">
          <Skeleton className="w-96 h-96 bg-background max-w-screen flex gap-2 items-center justify-center" >
            <Loader className="size-4 animate-spin" />
            <p>Generating...</p>
          </Skeleton>
        </div>
      </div>}


    </div>
  );
};
