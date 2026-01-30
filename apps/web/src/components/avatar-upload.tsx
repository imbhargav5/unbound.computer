"use client";
import { Camera } from "lucide-react";
import Image from "next/image";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";

export function AvatarUpload({
  avatarUrl,
  onFileChange,
}: {
  avatarUrl: string;
  onFileChange: (file: File) => void;
}) {
  const [preview, setPreview] = useState(avatarUrl);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => {
        setPreview(reader.result as string);
      };
      reader.readAsDataURL(file);
      onFileChange(file);
    }
  };

  return (
    <div className="flex items-center space-x-4">
      <div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-full bg-gray-200">
        {preview ? (
          <Image
            alt="Avatar preview"
            className="object-cover"
            fill
            src={preview}
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center text-gray-400">
            <Camera size={32} />
          </div>
        )}
      </div>
      <div>
        <Button
          onClick={() => fileInputRef.current?.click()}
          size="sm"
          variant="outline"
        >
          Change Avatar
        </Button>
        <input
          accept="image/*"
          className="hidden"
          onChange={handleFileChange}
          ref={fileInputRef}
          type="file"
        />
      </div>
    </div>
  );
}
