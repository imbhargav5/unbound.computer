"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { Check, Loader, Play, Save, Upload, X } from "lucide-react";
import Image from "next/image";
import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useRef, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { useTimeoutWhen } from "rooks";
import { toast } from "sonner";
import type { z } from "zod";
import { FormInput } from "@/components/form-components/form-input";
import { FormSelect } from "@/components/form-components/form-select";
import { Tiptap } from "@/components/tip-tap";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Form } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { VideoFrameSelector } from "@/components/video-frame-selector";
import { updateChangelogAction } from "@/data/admin/marketing-changelog";
import { uploadChangelogMedia } from "@/data/admin/marketing-upload";
import type { DBTable } from "@/types";
import {
  type ChangelogMediaType,
  getMediaAcceptString,
  getTagColor,
  TAG_OPTIONS,
} from "@/utils/changelog";
import { toSafeJSONB } from "@/utils/jsonb";
import {
  updateMarketingChangelogFormSchema,
  type updateMarketingChangelogSchema,
} from "@/utils/zod-schemas/marketing-changelog";
import { AuthorsSelect } from "./authors-select";

type FormData = z.infer<typeof updateMarketingChangelogFormSchema>;

type EditChangelogFormProps = {
  changelog: DBTable<"marketing_changelog"> & {
    marketing_changelog_author_relationship: { author_id: string }[];
  };
  authors: DBTable<"marketing_author_profiles">[];
};

export const EditChangelogForm: React.FC<EditChangelogFormProps> = ({
  changelog,
  authors,
}) => {
  const toastRef = useRef<string | number | undefined>(undefined);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Media state
  const [mediaUrl, setMediaUrl] = useState(changelog.media_url || "");
  const [mediaType, setMediaType] = useState<ChangelogMediaType | null>(
    (changelog.media_type as ChangelogMediaType) || null
  );
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const [posterUrl, setPosterUrl] = useState(changelog.media_poster || "");
  const [isUploading, setIsUploading] = useState(false);

  // Tags state
  const [selectedTags, setSelectedTags] = useState<string[]>(
    changelog.tags || []
  );
  const [customTagInput, setCustomTagInput] = useState("");

  const updateMutation = useAction(updateChangelogAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating changelog...", {
        description: "Please wait while we update the changelog.",
      });
    },
    onSuccess: () => {
      toast.success("Changelog updated successfully", {
        id: toastRef.current,
        description: "Your changes have been saved.",
      });
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to update changelog: ${error.serverError || "Unknown error"}`,
        {
          id: toastRef.current,
          description:
            "There was an issue saving your changes. Please try again.",
        }
      );
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const hasUpdateMutationSettled =
    updateMutation.status === "hasSucceeded" ||
    updateMutation.status === "hasErrored";
  useTimeoutWhen(
    () => {
      updateMutation.reset();
    },
    1500,
    hasUpdateMutationSettled
  );

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof updateMarketingChangelogSchema
  >(updateMutation.result.validationErrors, { joinBy: "\n" });

  const form = useForm<FormData>({
    resolver: zodResolver(updateMarketingChangelogFormSchema),
    defaultValues: {
      ...changelog,
      created_at: changelog.created_at ?? undefined,
      updated_at: changelog.updated_at ?? undefined,
      json_content: toSafeJSONB(changelog.json_content),
      version: changelog.version ?? "",
      tags: changelog.tags ?? [],
      media_type: (changelog.media_type as ChangelogMediaType) ?? null,
      media_url: changelog.media_url ?? "",
      media_alt: changelog.media_alt ?? "",
      media_poster: changelog.media_poster ?? "",
      technical_details: changelog.technical_details ?? "",
    },
    errors: hookFormValidationErrors,
  });

  const { handleSubmit, control, setValue, watch } = form;

  const onSubmit = async ({ json_content, ...data }: FormData) => {
    updateMutation.execute({
      ...data,
      tags: selectedTags,
      stringified_json_content: JSON.stringify(json_content ?? {}),
    });
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
      description: "Please wait while we upload your file.",
    });

    try {
      const result = await uploadChangelogMedia(formData);
      setMediaUrl(result.url);
      setMediaType(result.type);
      setValue("media_url", result.url);
      setValue("media_type", result.type);
      setIsVideoPlaying(false);
      toast.success("Media uploaded successfully", {
        id: uploadToastId,
        description: "Your media file has been uploaded.",
      });
    } catch (error) {
      toast.error(
        `Failed to upload media: ${error instanceof Error ? error.message : "Unknown error"}`,
        {
          id: uploadToastId,
          description:
            "There was an issue uploading your file. Please try again.",
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
    setValue("media_url", "");
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
    const result = await uploadChangelogMedia(formData);
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
      const result = await uploadChangelogMedia(formData);
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
      const result = await uploadChangelogMedia(formData);
      toast.success("Video uploaded", { id: toastId });
      return result.url;
    } catch (err) {
      toast.error("Upload failed", { id: toastId });
      throw err;
    }
  };

  const handleAddTag = (tag: string) => {
    if (!selectedTags.includes(tag)) {
      const newTags = [...selectedTags, tag];
      setSelectedTags(newTags);
      setValue("tags", newTags);
    }
  };

  const handleRemoveTag = (tag: string) => {
    const newTags = selectedTags.filter((t) => t !== tag);
    setSelectedTags(newTags);
    setValue("tags", newTags);
  };

  const handleAddCustomTag = () => {
    const trimmed = customTagInput.trim();
    if (trimmed && !selectedTags.includes(trimmed)) {
      handleAddTag(trimmed);
      setCustomTagInput("");
    }
  };

  // Shared media upload UI component
  const MediaUploadUI = () => (
    <div className="rounded-lg border bg-muted/30">
      <div
        className="relative mx-auto flex w-full cursor-pointer items-center justify-center overflow-hidden rounded-lg p-3"
        onClick={() =>
          !(mediaUrl || isUploading) && fileInputRef.current?.click()
        }
      >
        <div className="w-full">
          <AspectRatio ratio={4 / 3}>
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
                      alt={watch("media_alt") || "Featured media"}
                      className="rounded-lg object-cover"
                      fill
                      src={mediaUrl}
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

  // Tags section component
  const TagsSection = () => (
    <div>
      <Label className="text-sm">Tags</Label>

      {/* Selected tags */}
      {selectedTags.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {selectedTags.map((tag) => (
            <Badge
              className={`${getTagColor(tag)} cursor-pointer text-xs`}
              key={tag}
              onClick={() => handleRemoveTag(tag)}
              variant="outline"
            >
              {tag}
              <X className="ml-1 h-3 w-3" />
            </Badge>
          ))}
        </div>
      )}

      {/* Predefined tags */}
      <div className="mt-2 flex flex-wrap gap-1.5">
        {TAG_OPTIONS.filter((tag) => !selectedTags.includes(tag)).map((tag) => (
          <Badge
            className="cursor-pointer text-xs opacity-60 transition-opacity hover:opacity-100"
            key={tag}
            onClick={() => handleAddTag(tag)}
            variant="outline"
          >
            + {tag}
          </Badge>
        ))}
      </div>

      {/* Custom tag input */}
      <div className="mt-2 flex gap-2">
        <Input
          className="h-8 text-sm"
          onChange={(e) => setCustomTagInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              handleAddCustomTag();
            }
          }}
          placeholder="Custom tag..."
          value={customTagInput}
        />
        <Button
          className="h-8"
          onClick={handleAddCustomTag}
          size="sm"
          type="button"
          variant="outline"
        >
          Add
        </Button>
      </div>
    </div>
  );

  return (
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
            description="Enter the title of the changelog"
            id="title"
            label="Title"
            name="title"
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

          {/* Technical Details - Accordion */}
          <Accordion className="rounded-lg border" collapsible type="single">
            <AccordionItem className="border-0" value="technical">
              <AccordionTrigger className="px-4 hover:no-underline">
                <span className="font-medium text-sm">
                  Technical Details (Optional)
                </span>
              </AccordionTrigger>
              <AccordionContent className="px-4 pb-4">
                <Controller
                  control={control}
                  name="technical_details"
                  render={({ field }) => (
                    <Textarea
                      {...field}
                      className="min-h-32"
                      id="technical_details"
                      placeholder="Add technical implementation details, API changes, or migration notes..."
                      value={field.value || ""}
                    />
                  )}
                />
              </AccordionContent>
            </AccordionItem>
          </Accordion>

          {/* Mobile-only: Authors section */}
          <div className="md:hidden">
            <AuthorsSelect authors={authors} changelog={changelog} />
          </div>

          <Button disabled={updateMutation.status !== "idle"} type="submit">
            {updateMutation.status === "executing" ? (
              <>
                <Loader className="h-4 w-4 animate-spin" />
                Updating...
              </>
            ) : updateMutation.status === "hasSucceeded" ? (
              <>
                <Check className="h-4 w-4" />
                Updated!
              </>
            ) : (
              <>
                <Save className="h-4 w-4" />
                Update Changelog
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
                    <span className="font-medium text-sm">Featured Media</span>
                    {!!mediaUrl && (
                      <img
                        alt="Preview"
                        className="h-6 w-6 rounded object-cover"
                        src={mediaUrl}
                      />
                    )}
                  </span>
                </AccordionTrigger>
                <AccordionContent className="px-4 pb-4">
                  <MediaUploadUI />
                  {!!mediaUrl && (
                    <div className="mt-3">
                      <Label className="text-sm" htmlFor="media_alt_mobile">
                        Alt Text
                      </Label>
                      <Controller
                        control={control}
                        name="media_alt"
                        render={({ field }) => (
                          <Input
                            {...field}
                            className="mt-1 h-8 text-sm"
                            id="media_alt_mobile"
                            placeholder="Describe the media"
                            value={field.value || ""}
                          />
                        )}
                      />
                    </div>
                  )}
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
              Image, video, or GIF for the changelog entry.
            </p>
            <MediaUploadUI />
            {!!mediaUrl && (
              <div className="mt-2">
                <Label className="text-sm" htmlFor="media_alt_desktop">
                  Alt Text
                </Label>
                <Controller
                  control={control}
                  name="media_alt"
                  render={({ field }) => (
                    <Input
                      {...field}
                      className="mt-1 h-8 text-sm"
                      id="media_alt_desktop"
                      placeholder="Describe the media"
                      value={field.value || ""}
                    />
                  )}
                />
              </div>
            )}
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

          {/* Version + Status row */}
          <div className="flex gap-3">
            <div className="flex-1">
              <Label className="text-sm" htmlFor="version">
                Version
              </Label>
              <Controller
                control={control}
                name="version"
                render={({ field }) => (
                  <Input
                    {...field}
                    className="mt-1 h-8 text-sm"
                    id="version"
                    placeholder="v1.0.0"
                    value={field.value || ""}
                  />
                )}
              />
            </div>
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
          </div>

          {/* Tags */}
          <TagsSection />

          {/* Desktop-only: Authors section */}
          <div className="hidden md:block">
            <AuthorsSelect authors={authors} changelog={changelog} />
          </div>
        </div>
      </form>
    </Form>
  );
};
