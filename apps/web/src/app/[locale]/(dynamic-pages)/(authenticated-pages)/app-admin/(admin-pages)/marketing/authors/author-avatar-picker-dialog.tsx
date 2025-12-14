"use client";

import { Check, ImagePlus, Upload, X } from "lucide-react";
import type React from "react";
import { useCallback, useMemo, useRef, useState } from "react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { generateAvatarPickerGrid, getInitials } from "@/utils/generate-avatar";

interface AuthorAvatarPickerDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentAvatarUrl: string;
  displayName: string;
  onAvatarSelect: (url: string) => void;
  onAvatarUpload: (file: File) => void;
  isUploading: boolean;
}

export function AuthorAvatarPickerDialog({
  open,
  onOpenChange,
  currentAvatarUrl,
  displayName,
  onAvatarSelect,
  onAvatarUpload,
  isUploading,
}: AuthorAvatarPickerDialogProps) {
  const [selectedAvatar, setSelectedAvatar] = useState<string | null>(null);
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);
  const [uploadPreview, setUploadPreview] = useState<string | null>(null);
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const uploadInputRef = useRef<HTMLInputElement>(null);

  const avatarGrid = useMemo(() => generateAvatarPickerGrid(), []);

  const handleFileSelect = (file: File) => {
    if (file && file.type.startsWith("image/")) {
      const url = URL.createObjectURL(file);
      setUploadPreview(url);
      setUploadFile(file);
    }
  };

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleFileSelect(file);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  }, []);

  const confirmAvatarSelection = () => {
    if (selectedAvatar) {
      onAvatarSelect(selectedAvatar);
      setSelectedAvatar(null);
      onOpenChange(false);
    }
  };

  const confirmUpload = () => {
    if (uploadFile) {
      onAvatarUpload(uploadFile);
      setUploadPreview(null);
      setUploadFile(null);
      setIsUploadModalOpen(false);
      onOpenChange(false);
    }
  };

  const openUploadModal = () => {
    setIsUploadModalOpen(true);
  };

  const handleClose = () => {
    setSelectedAvatar(null);
    onOpenChange(false);
  };

  const initials = getInitials(displayName || "Author");

  return (
    <>
      <Dialog onOpenChange={handleClose} open={open}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Choose Author Avatar</DialogTitle>
            <DialogDescription>
              Select from our collection or upload a custom image.
            </DialogDescription>
          </DialogHeader>

          <div className="py-4">
            {/* Current avatar preview */}
            <div className="mb-6 flex items-center gap-4 rounded-lg bg-muted/50 p-3">
              <Avatar className="size-12 ring-1 ring-border">
                <AvatarImage
                  alt="Preview"
                  src={selectedAvatar ?? currentAvatarUrl}
                />
                <AvatarFallback>{initials}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <p className="font-medium text-sm">Preview</p>
                <p className="truncate text-muted-foreground text-xs">
                  {selectedAvatar
                    ? "New selection"
                    : currentAvatarUrl
                      ? "Current avatar"
                      : "No avatar set"}
                </p>
              </div>
              {selectedAvatar ? (
                <Button
                  onClick={() => setSelectedAvatar(null)}
                  size="sm"
                  variant="ghost"
                >
                  <X className="size-4" />
                </Button>
              ) : null}
            </div>

            {/* Avatar grid */}
            <div className="grid max-h-64 grid-cols-9 gap-2 overflow-y-auto pr-1">
              {avatarGrid.map((avatar, index) => (
                <button
                  className={cn(
                    "relative aspect-square overflow-hidden rounded-lg border-2 transition-all hover:scale-105",
                    selectedAvatar === avatar.url
                      ? "border-primary ring-2 ring-primary/20"
                      : "border-transparent hover:border-muted-foreground/30"
                  )}
                  key={`${avatar.style}-${avatar.seed}`}
                  onClick={() => setSelectedAvatar(avatar.url)}
                  type="button"
                >
                  <img
                    alt={`${avatar.style} avatar ${index + 1}`}
                    className="size-full bg-muted object-cover"
                    src={avatar.url}
                  />
                  {selectedAvatar === avatar.url && (
                    <div className="absolute inset-0 flex items-center justify-center bg-primary/10">
                      <Check className="size-4 text-primary" />
                    </div>
                  )}
                </button>
              ))}
            </div>
          </div>

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button
              className="w-full bg-transparent sm:w-auto"
              onClick={openUploadModal}
              variant="outline"
            >
              <Upload className="mr-2 size-4" />
              Upload Custom
            </Button>
            <div className="flex w-full gap-2 sm:w-auto">
              <Button
                className="flex-1 sm:flex-none"
                onClick={handleClose}
                variant="ghost"
              >
                Cancel
              </Button>
              <Button
                className="flex-1 sm:flex-none"
                disabled={!selectedAvatar}
                onClick={confirmAvatarSelection}
              >
                Apply
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Upload Modal */}
      <Dialog onOpenChange={setIsUploadModalOpen} open={isUploadModalOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Upload Image</DialogTitle>
            <DialogDescription>
              Choose an image from your device.
            </DialogDescription>
          </DialogHeader>

          <div className="py-4">
            {uploadPreview ? (
              <div className="space-y-4">
                <div className="flex items-center justify-center">
                  <div className="relative">
                    <Avatar className="size-32 ring-2 ring-border">
                      <AvatarImage alt="Upload preview" src={uploadPreview} />
                      <AvatarFallback>Preview</AvatarFallback>
                    </Avatar>
                    <button
                      className="-top-2 -right-2 absolute flex size-6 items-center justify-center rounded-full bg-destructive text-destructive-foreground hover:bg-destructive/90"
                      onClick={() => {
                        setUploadPreview(null);
                        setUploadFile(null);
                      }}
                      type="button"
                    >
                      <X className="size-3" />
                    </button>
                  </div>
                </div>
                <p className="text-center text-muted-foreground text-sm">
                  Looking good! Click confirm to apply.
                </p>
              </div>
            ) : (
              <div
                className={cn(
                  "cursor-pointer rounded-lg border-2 border-dashed p-8 text-center transition-colors",
                  isDragging
                    ? "border-primary bg-primary/5"
                    : "border-muted-foreground/25 hover:border-muted-foreground/50"
                )}
                onClick={() => uploadInputRef.current?.click()}
                onDragLeave={handleDragLeave}
                onDragOver={handleDragOver}
                onDrop={handleDrop}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    uploadInputRef.current?.click();
                  }
                }}
                role="button"
                tabIndex={0}
              >
                <div className="flex flex-col items-center gap-3">
                  <div className="flex size-12 items-center justify-center rounded-full bg-muted">
                    <ImagePlus className="size-6 text-muted-foreground" />
                  </div>
                  <div>
                    <p className="font-medium text-sm">
                      Drop image here or click to browse
                    </p>
                    <p className="mt-1 text-muted-foreground text-xs">
                      PNG, JPG or GIF up to 5MB
                    </p>
                  </div>
                </div>
                <input
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) handleFileSelect(file);
                  }}
                  ref={uploadInputRef}
                  type="file"
                />
              </div>
            )}
          </div>

          <DialogFooter>
            <Button
              onClick={() => {
                setUploadPreview(null);
                setUploadFile(null);
                setIsUploadModalOpen(false);
              }}
              variant="ghost"
            >
              Cancel
            </Button>
            <Button
              disabled={!uploadFile || isUploading}
              onClick={confirmUpload}
            >
              {isUploading ? "Uploading..." : "Confirm"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
