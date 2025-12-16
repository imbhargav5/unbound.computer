// @/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/[postId]/EditBlogPostForm.tsx
"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Check, Loader, Play, Save, Upload, X } from "lucide-react";
import Image from "next/image";
import type React from "react";
import { useEffect, useRef, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { useTimeoutWhen } from "rooks";
import slugify from "slugify";
import { toast } from "sonner";
import type { z } from "zod";
import { FormInput } from "@/components/form-components/form-input";
import { FormSelect } from "@/components/form-components/form-select";
import { FormSwitch } from "@/components/form-components/form-switch";
import { FormTextarea } from "@/components/form-components/form-textarea";
import { Tiptap } from "@/components/tip-tap";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Button } from "@/components/ui/button";
import { Form } from "@/components/ui/form";
import { Label } from "@/components/ui/label";
import { VideoFrameSelector } from "@/components/video-frame-selector";
import { updateBlogPostAction } from "@/data/admin/marketing-blog";
import { uploadBlogMedia } from "@/data/admin/marketing-upload";
import type { DBTable } from "@/types";
import {
  type ChangelogMediaType,
  getMediaAcceptString,
} from "@/utils/changelog";
import { toSafeJSONB } from "@/utils/jsonb";
import { updateMarketingBlogPostSchema } from "@/utils/zod-schemas/marketing-blog";
import { AuthorsSelect } from "./authors-select";
import { TagsSelect } from "./tags-select";

type FormData = z.infer<typeof updateMarketingBlogPostSchema>;

type EditBlogPostFormProps = {
  post: DBTable<"marketing_blog_posts"> & {
    marketing_blog_author_posts?: { author_id: string }[];
    marketing_blog_post_tags_relationship?: { tag_id: string }[];
  };
  authors: DBTable<"marketing_author_profiles">[];
  tags: DBTable<"marketing_tags">[];
};

export function EditBlogPostForm({
  post,
  authors,
  tags,
}: EditBlogPostFormProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Media state
  const [mediaUrl, setMediaUrl] = useState(post.cover_image || "");
  const [mediaType, setMediaType] = useState<ChangelogMediaType | null>(
    (post.media_type as ChangelogMediaType) || null
  );
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const [posterUrl, setPosterUrl] = useState(post.media_poster || "");
  const [isUploading, setIsUploading] = useState(false);

  // Submission state
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitStatus, setSubmitStatus] = useState<
    "idle" | "success" | "error"
  >("idle");

  const form = useForm<FormData>({
    resolver: zodResolver(updateMarketingBlogPostSchema),
    defaultValues: {
      ...post,
      json_content: toSafeJSONB(post.json_content),
      seo_data: toSafeJSONB(post.seo_data),
      cover_image: post.cover_image ?? undefined,
      media_type: (post.media_type as ChangelogMediaType) ?? null,
      media_poster: post.media_poster ?? undefined,
    },
  });

  const {
    handleSubmit,
    formState: { errors },
    control,
    setValue,
    watch,
  } = form;

  const currentTitle = watch("title");

  useEffect(() => {
    if (currentTitle) {
      setValue(
        "slug",
        slugify(currentTitle, {
          lower: true,
          strict: true,
          replacement: "-",
        })
      );
    }
  }, [currentTitle]);

  const onSubmit = async ({ json_content, seo_data, ...data }: FormData) => {
    setIsSubmitting(true);
    setSubmitStatus("idle");

    const toastId = toast.loading("Updating blog post...", {
      description: "Please wait while we update the post.",
    });

    const result = await updateBlogPostAction({
      ...data,
      stringified_json_content: JSON.stringify(json_content ?? {}),
      stringified_seo_data: JSON.stringify(seo_data ?? {}),
    });

    if (result.error) {
      toast.error(`Failed to update blog post: ${result.error}`, {
        id: toastId,
      });
      setSubmitStatus("error");
    } else {
      toast.success("Blog post updated successfully", { id: toastId });
      setSubmitStatus("success");
    }

    setIsSubmitting(false);
  };

  const handleMediaUpload = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const formData = new FormData();
    formData.append("file", file);

    setIsUploading(true);
    const uploadToastId = toast.loading("Uploading media...", {
      description: "Please wait while we upload the file.",
    });

    try {
      const result = await uploadBlogMedia(formData);
      setMediaUrl(result.url);
      setMediaType(result.type);
      setValue("cover_image", result.url);
      setValue("media_type", result.type);
      setIsVideoPlaying(false);
      toast.success("Media uploaded successfully", {
        description: "The media has been uploaded successfully.",
        id: uploadToastId,
      });
    } catch (error) {
      toast.error(
        `Failed to upload media: ${error instanceof Error ? error.message : "Unknown error"}`,
        {
          description: "Please try again.",
          id: uploadToastId,
        }
      );
    } finally {
      setIsUploading(false);
    }
  };

  const handleRemoveMedia = () => {
    setMediaUrl("");
    setMediaType(null);
    setPosterUrl("");
    setValue("cover_image", "");
    setValue("media_type", null);
    setValue("media_poster", "");
    setIsVideoPlaying(false);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  // Poster upload handler for VideoFrameSelector
  const handlePosterUpload = async (file: File): Promise<string> => {
    const formData = new FormData();
    formData.append("file", file);
    const result = await uploadBlogMedia(formData);
    return result.url;
  };

  const handlePosterSelect = (url: string) => {
    setPosterUrl(url);
    setValue("media_poster", url);
  };

  const handlePosterRemove = () => {
    setPosterUrl("");
    setValue("media_poster", "");
  };

  // TipTap inline media upload handlers
  const handleTiptapImageUpload = async (file: File): Promise<string> => {
    const formData = new FormData();
    formData.append("file", file);

    const toastId = toast.loading("Uploading image...");
    try {
      const result = await uploadBlogMedia(formData);
      toast.success("Image uploaded", { id: toastId });
      return result.url;
    } catch (err) {
      toast.error("Upload failed", { id: toastId });
      throw err;
    }
  };

  const handleTiptapVideoUpload = async (file: File): Promise<string> => {
    const formData = new FormData();
    formData.append("file", file);

    const toastId = toast.loading("Uploading video...");
    try {
      const result = await uploadBlogMedia(formData);
      toast.success("Video uploaded", { id: toastId });
      return result.url;
    } catch (err) {
      toast.error("Upload failed", { id: toastId });
      throw err;
    }
  };

  const hasSubmitSettled =
    submitStatus === "success" || submitStatus === "error";
  useTimeoutWhen(
    () => {
      setSubmitStatus("idle");
    },
    1500,
    hasSubmitSettled
  );

  // Media upload UI component supporting images, videos, and GIFs
  const MediaUploadUI = () => (
    <div className="rounded-lg border bg-muted/30">
      <div
        className="relative mx-auto flex w-full cursor-pointer items-center justify-center overflow-hidden rounded-lg p-3"
        onClick={() =>
          !(mediaUrl || isUploading) && fileInputRef.current?.click()
        }
      >
        <div className="w-full">
          <AspectRatio ratio={mediaType === "video" ? 131 / 100 : 4 / 3}>
            {mediaUrl ? (
              <div className="relative h-full w-full">
                {mediaType === "video" ? (
                  <>
                    {isVideoPlaying ? (
                      <video
                        autoPlay
                        className="h-full w-full rounded-lg object-cover"
                        controls
                        src={mediaUrl}
                      >
                        <track kind="captions" />
                      </video>
                    ) : (
                      <button
                        className="group absolute inset-0 flex items-center justify-center"
                        onClick={(e) => {
                          e.stopPropagation();
                          setIsVideoPlaying(true);
                        }}
                        type="button"
                      >
                        <div className="absolute inset-0 bg-black/20 transition-colors group-hover:bg-black/30" />
                        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-white/90 shadow-lg transition-transform group-hover:scale-110">
                          <Play
                            className="ml-1 h-5 w-5 text-foreground"
                            fill="currentColor"
                          />
                        </div>
                      </button>
                    )}
                    {!isVideoPlaying && (
                      <div className="absolute inset-0 rounded-lg bg-muted" />
                    )}
                  </>
                ) : (
                  <>
                    <Image
                      alt="Featured media"
                      className="rounded-lg object-cover"
                      fill
                      src={mediaUrl}
                      unoptimized
                    />
                    {mediaType === "gif" && (
                      <div className="absolute bottom-2 left-2 rounded-md bg-black/70 px-1.5 py-0.5 font-medium text-white text-xs">
                        GIF
                      </div>
                    )}
                  </>
                )}

                {/* Remove button */}
                <button
                  className="absolute top-1.5 right-1.5 rounded-full bg-black/50 p-1 text-white transition-colors hover:bg-black/70"
                  onClick={(e) => {
                    e.stopPropagation();
                    handleRemoveMedia();
                  }}
                  type="button"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>
            ) : (
              <div className="flex h-full w-full flex-col items-center justify-center rounded-lg border-2 border-muted-foreground/25 border-dashed bg-muted/50 transition-colors hover:border-muted-foreground/50">
                {isUploading ? (
                  <Loader className="mb-1.5 h-6 w-6 animate-spin text-muted-foreground" />
                ) : (
                  <Upload className="mb-1.5 h-6 w-6 text-muted-foreground" />
                )}
                <span className="font-medium text-muted-foreground text-xs">
                  {isUploading ? "Uploading..." : "Click to upload"}
                </span>
                {!isUploading && (
                  <span className="mt-0.5 text-center text-muted-foreground text-xs">
                    Image, Video, or GIF
                  </span>
                )}
              </div>
            )}
          </AspectRatio>
        </div>
      </div>
    </div>
  );

  return (
    <>
      <div className="mb-6" data-testid="blog-post-edit-header">
        <p className="text-muted-foreground text-sm">Editing Blog Post</p>
        <h1 className="font-bold text-3xl" data-testid="blog-post-edit-title">
          {currentTitle || "Untitled"}
        </h1>
      </div>
      <Form {...form}>
        <form
          className="flex flex-col gap-6 md:flex-row"
          onSubmit={handleSubmit(onSubmit)}
        >
          {/* Main content column */}
          <div className="grow space-y-6">
            {/* Title */}
            <FormInput
              control={control}
              description="This is the title of the blog post."
              id="title"
              label="Title"
              name="title"
            />

            {/* Slug */}
            <FormInput
              control={control}
              description="This is the slug of the blog post."
              id="slug"
              label="Slug"
              name="slug"
            />

            {/* Content Editor */}
            <div className="nextbase-editor max-w-full overflow-hidden">
              <Label htmlFor="json_content">Content</Label>
              <Controller
                control={control}
                name="json_content"
                render={({ field }) => (
                  <Tiptap
                    initialContent={field.value ?? {}}
                    onImageUpload={handleTiptapImageUpload}
                    onUpdate={({ editor }) => {
                      field.onChange(editor.getJSON());
                    }}
                    onVideoUpload={handleTiptapVideoUpload}
                  />
                )}
              />
            </div>

            {/* Summary - Accordion */}
            <Accordion className="rounded-lg border" collapsible type="single">
              <AccordionItem className="border-0" value="summary">
                <AccordionTrigger className="px-4 hover:no-underline">
                  <span className="font-medium text-sm">
                    Summary (Optional)
                  </span>
                </AccordionTrigger>
                <AccordionContent className="px-4 pb-4">
                  <FormTextarea
                    control={control}
                    description="A brief summary of the blog post."
                    id="summary"
                    label="Summary"
                    name="summary"
                  />
                </AccordionContent>
              </AccordionItem>
            </Accordion>

            {/* Mobile-only: Authors section */}
            <div className="md:hidden">
              <AuthorsSelect authors={authors} post={post} />
            </div>

            <Button
              disabled={isSubmitting || submitStatus !== "idle"}
              type="submit"
            >
              {isSubmitting ? (
                <>
                  <Loader className="h-4 w-4 animate-spin" />
                  Updating...
                </>
              ) : submitStatus === "success" ? (
                <>
                  <Check className="h-4 w-4" />
                  Updated!
                </>
              ) : (
                <>
                  <Save className="h-4 w-4" />
                  Update Blog Post
                </>
              )}
            </Button>
          </div>

          {/* Sidebar */}
          <div className="order-first space-y-4 md:order-none md:w-72 md:shrink-0">
            {/* Mobile: Collapsible Media Upload */}
            <div className="md:hidden">
              <Accordion collapsible defaultValue="" type="single">
                <AccordionItem className="rounded-lg border" value="media">
                  <AccordionTrigger className="px-4 hover:no-underline">
                    <span className="flex items-center gap-2">
                      <span className="font-medium text-sm">
                        Featured Media
                      </span>
                      {mediaUrl ? (
                        <img
                          alt="Preview"
                          className="h-6 w-6 rounded object-cover"
                          src={mediaUrl}
                        />
                      ) : null}
                    </span>
                  </AccordionTrigger>
                  <AccordionContent className="px-4 pb-4">
                    <MediaUploadUI />
                    {mediaType === "video" && mediaUrl && (
                      <div className="mt-3">
                        <VideoFrameSelector
                          onPosterRemove={handlePosterRemove}
                          onPosterSelect={handlePosterSelect}
                          onUploadPoster={handlePosterUpload}
                          selectedPosterUrl={posterUrl}
                          videoUrl={mediaUrl}
                        />
                      </div>
                    )}
                  </AccordionContent>
                </AccordionItem>
              </Accordion>
            </div>

            {/* Desktop: Direct Media Upload */}
            <div className="hidden md:block">
              <Label className="text-sm">Featured Media</Label>
              <p className="mb-2 text-muted-foreground text-xs">
                Image, video, or GIF for the blog post.
              </p>
              <MediaUploadUI />
              {mediaType === "video" && mediaUrl && (
                <div className="mt-3">
                  <VideoFrameSelector
                    onPosterRemove={handlePosterRemove}
                    onPosterSelect={handlePosterSelect}
                    onUploadPoster={handlePosterUpload}
                    selectedPosterUrl={posterUrl}
                    videoUrl={mediaUrl}
                  />
                </div>
              )}
            </div>

            <input
              accept={getMediaAcceptString()}
              className="hidden"
              disabled={isUploading}
              onChange={handleMediaUpload}
              ref={fileInputRef}
              type="file"
            />

            {errors.cover_image ? (
              <p className="text-red-500 text-sm">
                {errors.cover_image.message}
              </p>
            ) : null}

            {/* Status + Is Featured row */}
            <div className="flex gap-3">
              <div className="flex-1">
                <FormSelect
                  control={control}
                  id="status"
                  label="Status"
                  name="status"
                  options={[
                    { label: "Draft", value: "draft" },
                    { label: "Published", value: "published" },
                  ]}
                  placeholder="Status"
                />
              </div>
              <div className="flex items-end pb-1">
                <FormSwitch
                  control={control}
                  id="is_featured"
                  label="Featured"
                  name="is_featured"
                />
              </div>
            </div>

            {/* Tags */}
            <TagsSelect post={post} tags={tags} />

            {/* Desktop-only: Authors section */}
            <div className="hidden md:block">
              <AuthorsSelect authors={authors} post={post} />
            </div>
          </div>
        </form>
      </Form>
    </>
  );
}
