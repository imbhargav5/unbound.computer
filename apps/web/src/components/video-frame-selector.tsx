"use client";

import { Check, ImageIcon, Loader, X } from "lucide-react";
import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { Button } from "./ui/button";
import { Label } from "./ui/label";

interface VideoFrameSelectorProps {
  frameCount?: number;
  onPosterRemove: () => void;
  onPosterSelect: (posterUrl: string) => void;
  onUploadPoster: (file: File) => Promise<string>;
  selectedPosterUrl?: string | null;
  videoUrl: string;
}

interface ExtractedFrame {
  dataUrl: string;
  timestamp: number;
}

export function VideoFrameSelector({
  videoUrl,
  selectedPosterUrl,
  onPosterSelect,
  onPosterRemove,
  onUploadPoster,
  frameCount = 6,
}: VideoFrameSelectorProps) {
  console.log("VideoFrameSelector", videoUrl, selectedPosterUrl);
  const [frames, setFrames] = useState<ExtractedFrame[]>([]);
  const [isExtracting, setIsExtracting] = useState(false);
  const [extractionError, setExtractionError] = useState<string | null>(null);
  const [selectedFrameIndex, setSelectedFrameIndex] = useState<number | null>(
    null
  );
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const extractFrames = useCallback(async () => {
    if (!videoUrl) return;

    setIsExtracting(true);
    setExtractionError(null);
    setFrames([]);

    try {
      const video = document.createElement("video");
      video.crossOrigin = "anonymous";
      video.preload = "metadata";
      video.muted = true;
      video.playsInline = true;

      await new Promise<void>((resolve, reject) => {
        video.onloadedmetadata = () => resolve();
        video.onerror = () =>
          reject(new Error("Failed to load video metadata"));
        video.src = videoUrl;
      });

      const duration = video.duration;
      if (!duration || duration === Number.POSITIVE_INFINITY) {
        throw new Error("Could not determine video duration");
      }

      const extractedFrames: ExtractedFrame[] = [];
      const canvas = document.createElement("canvas");
      const ctx = canvas.getContext("2d");

      if (!ctx) {
        throw new Error("Could not create canvas context");
      }

      // Wait for video to be ready to play
      await new Promise<void>((resolve, reject) => {
        video.oncanplay = () => resolve();
        video.onerror = () => reject(new Error("Video cannot be played"));
        video.load();
      });

      // Extract frames at regular intervals
      for (let i = 0; i < frameCount; i++) {
        const timestamp = (duration / (frameCount + 1)) * (i + 1);

        await new Promise<void>((resolve, reject) => {
          const handleSeeked = () => {
            video.removeEventListener("seeked", handleSeeked);
            video.removeEventListener("error", handleError);

            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

            try {
              const dataUrl = canvas.toDataURL("image/jpeg", 0.85);
              extractedFrames.push({ dataUrl, timestamp });
              resolve();
            } catch {
              reject(new Error("Failed to capture frame - CORS issue likely"));
            }
          };

          const handleError = () => {
            video.removeEventListener("seeked", handleSeeked);
            video.removeEventListener("error", handleError);
            reject(new Error("Failed to seek video"));
          };

          video.addEventListener("seeked", handleSeeked);
          video.addEventListener("error", handleError);
          video.currentTime = timestamp;
        });
      }

      setFrames(extractedFrames);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to extract frames";
      setExtractionError(message);
      toast.error("Could not extract video frames", {
        description: "You can upload a custom poster image instead.",
      });
    } finally {
      setIsExtracting(false);
    }
  }, [videoUrl, frameCount]);

  useEffect(() => {
    if (videoUrl) {
      extractFrames();
    }
  }, [videoUrl, extractFrames]);

  const handleFrameSelect = async (frame: ExtractedFrame, index: number) => {
    if (isUploading) return;

    setSelectedFrameIndex(index);
    setIsUploading(true);

    try {
      // Convert data URL to File
      const response = await fetch(frame.dataUrl);
      const blob = await response.blob();
      const file = new File([blob], `poster-frame-${Date.now()}.jpg`, {
        type: "image/jpeg",
      });

      const uploadedUrl = await onUploadPoster(file);
      onPosterSelect(uploadedUrl);
      toast.success("Poster image set successfully");
    } catch {
      toast.error("Failed to set poster image");
      setSelectedFrameIndex(null);
    } finally {
      setIsUploading(false);
    }
  };

  const handleCustomUpload = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    setSelectedFrameIndex(null);

    try {
      const uploadedUrl = await onUploadPoster(file);
      onPosterSelect(uploadedUrl);
      toast.success("Custom poster uploaded successfully");
    } catch {
      toast.error("Failed to upload poster image");
    } finally {
      setIsUploading(false);
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  };

  const handleRemovePoster = () => {
    setSelectedFrameIndex(null);
    onPosterRemove();
  };

  if (!videoUrl) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <Label className="text-sm">Video Poster</Label>
        {selectedPosterUrl && (
          <Button
            className="h-6 px-2 text-xs"
            onClick={handleRemovePoster}
            size="sm"
            type="button"
            variant="ghost"
          >
            <X className="mr-1 h-3 w-3" />
            Remove
          </Button>
        )}
      </div>

      {/* Current poster preview */}
      {selectedPosterUrl && (
        <div className="relative aspect-video w-full overflow-hidden rounded-lg border bg-muted">
          <Image
            alt="Video poster"
            className="object-cover"
            data-selected-poster-url={selectedPosterUrl}
            fill
            sizes="(max-width: 768px) 100vw, 300px"
            src={selectedPosterUrl}
            unoptimized
          />
          <div className="absolute top-2 left-2 flex items-center gap-1 rounded-md bg-black/70 px-2 py-1 text-white text-xs">
            <Check className="h-3 w-3" />
            Current Poster
          </div>
        </div>
      )}

      {/* Frame extraction status */}
      {isExtracting && (
        <div className="flex items-center gap-2 rounded-lg border border-dashed p-4 text-muted-foreground text-sm">
          <Loader className="h-4 w-4 animate-spin" />
          Extracting frames from video...
        </div>
      )}

      {/* Extraction error */}
      {extractionError && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-amber-800 text-sm dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200">
          <p className="font-medium">Could not extract frames automatically</p>
          <p className="mt-1 text-xs opacity-80">
            {extractionError}. Please upload a custom poster image below.
          </p>
        </div>
      )}

      {/* Frame selector grid */}
      {frames.length > 0 && (
        <div className="space-y-2">
          <p className="text-muted-foreground text-xs">
            Select a frame as poster:
          </p>
          <div className="grid grid-cols-3 gap-2">
            {frames.map((frame, index) => (
              <button
                className={cn(
                  "group relative aspect-video overflow-hidden rounded-md border-2 transition-all",
                  "hover:border-primary/50 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-offset-2",
                  selectedFrameIndex === index
                    ? "border-primary ring-2 ring-primary ring-offset-2"
                    : "border-transparent",
                  isUploading && selectedFrameIndex !== index && "opacity-50"
                )}
                disabled={isUploading}
                key={frame.timestamp}
                onClick={() => handleFrameSelect(frame, index)}
                type="button"
              >
                <img
                  alt={`Frame at ${Math.round(frame.timestamp)}s`}
                  className="h-full w-full object-cover"
                  src={frame.dataUrl}
                />
                {isUploading && selectedFrameIndex === index && (
                  <div className="absolute inset-0 flex items-center justify-center bg-black/50">
                    <Loader className="h-4 w-4 animate-spin text-white" />
                  </div>
                )}
                {!isUploading && (
                  <div className="absolute inset-0 flex items-center justify-center bg-black/0 opacity-0 transition-all group-hover:bg-black/30 group-hover:opacity-100">
                    <Check className="h-5 w-5 text-white" />
                  </div>
                )}
                <div className="absolute right-1 bottom-1 rounded bg-black/70 px-1 py-0.5 font-mono text-white text-xs">
                  {Math.round(frame.timestamp)}s
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Custom upload button */}
      <div className="flex items-center gap-2">
        <Button
          className="flex-1"
          disabled={isUploading}
          onClick={() => fileInputRef.current?.click()}
          size="sm"
          type="button"
          variant="outline"
        >
          {isUploading && selectedFrameIndex === null ? (
            <>
              <Loader className="mr-2 h-4 w-4 animate-spin" />
              Uploading...
            </>
          ) : (
            <>
              <ImageIcon className="mr-2 h-4 w-4" />
              Upload Custom Poster
            </>
          )}
        </Button>
        {extractionError && (
          <Button
            disabled={isExtracting}
            onClick={extractFrames}
            size="sm"
            type="button"
            variant="ghost"
          >
            Retry
          </Button>
        )}
      </div>

      <input
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={handleCustomUpload}
        ref={fileInputRef}
        type="file"
      />
    </div>
  );
}
