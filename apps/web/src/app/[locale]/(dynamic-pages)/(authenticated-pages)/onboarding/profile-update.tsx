"use client";

import { ArrowRight, Camera } from "lucide-react";
import { useEffect, useState } from "react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { generateAvatarDataUri, getInitials } from "@/utils/generate-avatar";
import { OnboardingAvatarPickerDialog } from "./onboarding-avatar-picker-dialog";
import { useOnboarding } from "./onboarding-context";

export function ProfileUpdate() {
  const {
    userProfile,
    userEmail,
    state,
    avatarUrl,
    updateProfile,
    updateAvatar,
    uploadAvatar,
    goBack,
  } = useOnboarding();

  const [isAvatarPickerOpen, setIsAvatarPickerOpen] = useState(false);
  const [fullName, setFullName] = useState(userProfile.full_name ?? "");

  // Set initial avatar if not already set
  useEffect(() => {
    if (userEmail && !avatarUrl) {
      const initialAvatar = generateAvatarDataUri(userEmail, "initials");
      updateAvatar(initialAvatar);
    }
  }, [userEmail, avatarUrl, updateAvatar]);

  const handleAvatarSelect = (url: string) => {
    updateAvatar(url);
  };

  const handleAvatarUpload = (file: File) => {
    uploadAvatar(file);
  };

  const handleSubmit = async () => {
    if (fullName.trim()) {
      await updateProfile(fullName);
    }
  };

  const initials = getInitials(fullName || userProfile.full_name || "User");
  const currentAvatarUrl =
    avatarUrl || generateAvatarDataUri(userEmail || "user", "initials");

  return (
    <div className="space-y-6">
      <div>
        <h2 className="mb-2 font-semibold text-2xl text-foreground">
          Complete Your Profile
        </h2>
        <p className="text-muted-foreground">
          Tell us a bit about yourself and choose an avatar
        </p>
      </div>

      <div className="space-y-8">
        {/* Profile Photo Row */}
        <div className="flex items-start justify-between border-b pb-8">
          <div>
            <h3 className="font-medium text-sm">Profile Photo</h3>
            <p className="mt-0.5 text-muted-foreground text-sm">
              Click to choose a new avatar.
            </p>
          </div>
          <button
            className="group relative cursor-pointer"
            onClick={() => setIsAvatarPickerOpen(true)}
            type="button"
          >
            <Avatar className="size-16 ring-1 ring-border">
              <AvatarImage alt="Profile avatar" src={currentAvatarUrl} />
              <AvatarFallback className="bg-muted text-base">
                {initials}
              </AvatarFallback>
            </Avatar>
            <div className="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 opacity-0 transition-opacity group-hover:opacity-100">
              <Camera className="size-4 text-white" />
            </div>
          </button>
        </div>

        {/* Full Name Row */}
        <div className="flex items-start justify-between gap-8">
          <div className="shrink-0">
            <h3 className="font-medium text-sm">Full Name</h3>
            <p className="mt-0.5 text-muted-foreground text-sm">
              Your display name.
            </p>
          </div>
          <Input
            className="h-9 w-56"
            data-testid="full-name-input"
            onChange={(e) => setFullName(e.target.value)}
            placeholder="Enter your name"
            value={fullName}
          />
        </div>
      </div>

      {/* Submit button */}
      <div className="flex justify-end gap-3 pt-4">
        <Button
          disabled={state.isLoading || !state.completedSteps.has(1)}
          onClick={goBack}
          type="button"
          variant="outline"
        >
          Back
        </Button>
        <Button
          data-testid="save-profile-button"
          disabled={state.isLoading || !fullName.trim()}
          onClick={handleSubmit}
          size="lg"
        >
          {state.isLoading ? "Saving..." : "Continue"}
          <ArrowRight className="h-5 w-5" />
        </Button>
      </div>

      {/* Avatar Picker Dialog */}
      <OnboardingAvatarPickerDialog
        currentAvatarUrl={currentAvatarUrl}
        fullName={fullName || userProfile.full_name || ""}
        isUploading={state.isLoading}
        onAvatarSelect={handleAvatarSelect}
        onAvatarUpload={handleAvatarUpload}
        onOpenChange={setIsAvatarPickerOpen}
        open={isAvatarPickerOpen}
      />
    </div>
  );
}
