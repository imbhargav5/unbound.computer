"use client";

import type React from "react";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useReducer,
  useState,
} from "react";
import slugify from "slugify";
import { toast } from "sonner";
import { v4 as uuidv4 } from "uuid";
import { bulkSettleInvitationsAction } from "@/data/user/invitation";
import {
  acceptTermsOfServiceAction,
  updateProfilePictureUrlAction,
  updateUserFullNameAction,
  uploadPublicUserAvatarAction,
} from "@/data/user/user";
import { createWorkspaceAction } from "@/data/user/workspaces";
import type { DBTable, WorkspaceInvitation } from "@/types";
import type { AuthUserMetadata } from "@/utils/zod-schemas/auth-user-metadata";
export type OnboardingStep = 1 | 2 | 3 | "success";

type OnboardingState = {
  currentStep: OnboardingStep;
  completedSteps: Set<number>;
  isLoading: boolean;
};

type OnboardingAction =
  | { type: "COMPLETE_STEP"; step: number }
  | { type: "GO_TO_STEP"; step: OnboardingStep }
  | { type: "SET_LOADING"; isLoading: boolean }
  | { type: "GO_TO_SUCCESS" };

function onboardingReducer(
  state: OnboardingState,
  action: OnboardingAction
): OnboardingState {
  switch (action.type) {
    case "COMPLETE_STEP": {
      const newCompletedSteps = new Set(state.completedSteps);
      newCompletedSteps.add(action.step);

      // Auto-advance to next step
      let nextStep: OnboardingStep = state.currentStep;
      if (action.step === 1) nextStep = 2;
      else if (action.step === 2) nextStep = 3;
      else if (action.step === 3) nextStep = "success";

      return {
        ...state,
        completedSteps: newCompletedSteps,
        currentStep: nextStep,
        isLoading: false,
      };
    }
    case "GO_TO_STEP": {
      // Can only go back to completed steps
      if (
        typeof action.step === "number" &&
        !state.completedSteps.has(action.step)
      ) {
        return state;
      }
      return { ...state, currentStep: action.step };
    }
    case "SET_LOADING":
      return { ...state, isLoading: action.isLoading };
    case "GO_TO_SUCCESS":
      return { ...state, currentStep: "success", isLoading: false };
    default:
      return state;
  }
}

function getInitialStep(onboardingStatus: AuthUserMetadata): OnboardingStep {
  if (!onboardingStatus.onboardingHasAcceptedTerms) return 1;
  if (!onboardingStatus.onboardingHasCompletedProfile) return 2;
  if (!onboardingStatus.onboardingHasCompletedWorkspaceSetup) return 3;
  return "success";
}

function getCompletedSteps(onboardingStatus: AuthUserMetadata): Set<number> {
  const completed = new Set<number>();
  if (onboardingStatus.onboardingHasAcceptedTerms) completed.add(1);
  if (onboardingStatus.onboardingHasCompletedProfile) completed.add(2);
  if (onboardingStatus.onboardingHasCompletedWorkspaceSetup) completed.add(3);
  return completed;
}

type OnboardingContextType = {
  state: OnboardingState;
  userProfile: DBTable<"user_profiles">;
  userEmail: string | undefined;
  pendingInvitations: WorkspaceInvitation[];
  avatarUrl: string | undefined;
  setAvatarUrl: (url: string) => void;
  goToStep: (step: OnboardingStep) => void;
  goBack: () => void;
  acceptTerms: () => Promise<void>;
  updateProfile: (fullName: string) => Promise<void>;
  updateAvatar: (url: string) => Promise<void>;
  uploadAvatar: (file: File) => Promise<void>;
  createWorkspace: (invitationIds?: string[]) => Promise<void>;
};

const OnboardingContext = createContext<OnboardingContextType | undefined>(
  undefined
);

export function useOnboarding() {
  const context = useContext(OnboardingContext);
  if (!context) {
    throw new Error("useOnboarding must be used within an OnboardingProvider");
  }
  return context;
}

type OnboardingProviderProps = {
  children: React.ReactNode;
  userProfile: DBTable<"user_profiles">;
  onboardingStatus: AuthUserMetadata;
  userEmail: string | undefined;
  pendingInvitations: WorkspaceInvitation[];
};

export function OnboardingProvider({
  children,
  userProfile,
  onboardingStatus,
  userEmail,
  pendingInvitations,
}: OnboardingProviderProps) {
  const [state, dispatch] = useReducer(onboardingReducer, {
    currentStep: getInitialStep(onboardingStatus),
    completedSteps: getCompletedSteps(onboardingStatus),
    isLoading: false,
  });

  const [avatarUrl, setAvatarUrl] = useState<string | undefined>(
    userProfile.avatar_url ?? undefined
  );

  const goToStep = useCallback((step: OnboardingStep) => {
    dispatch({ type: "GO_TO_STEP", step });
  }, []);

  const goBack = useCallback(() => {
    if (state.currentStep === 2 && state.completedSteps.has(1)) {
      dispatch({ type: "GO_TO_STEP", step: 1 });
    } else if (state.currentStep === 3 && state.completedSteps.has(2)) {
      dispatch({ type: "GO_TO_STEP", step: 2 });
    }
  }, [state.currentStep, state.completedSteps]);

  const acceptTerms = useCallback(async () => {
    dispatch({ type: "SET_LOADING", isLoading: true });
    try {
      const result = await acceptTermsOfServiceAction();
      if (result?.serverError) {
        toast.error("Failed to accept terms");
        dispatch({ type: "SET_LOADING", isLoading: false });
        return;
      }
      dispatch({ type: "COMPLETE_STEP", step: 1 });
    } catch {
      toast.error("Failed to accept terms");
      dispatch({ type: "SET_LOADING", isLoading: false });
    }
  }, []);

  const updateProfile = useCallback(async (fullName: string) => {
    dispatch({ type: "SET_LOADING", isLoading: true });
    try {
      const result = await updateUserFullNameAction({
        fullName,
        isOnboardingFlow: true,
      });
      if (result?.serverError) {
        toast.error("Failed to update profile");
        dispatch({ type: "SET_LOADING", isLoading: false });
        return;
      }
      dispatch({ type: "COMPLETE_STEP", step: 2 });
    } catch {
      toast.error("Failed to update profile");
      dispatch({ type: "SET_LOADING", isLoading: false });
    }
  }, []);

  const updateAvatar = useCallback(async (url: string) => {
    try {
      setAvatarUrl(url);
      await updateProfilePictureUrlAction({ profilePictureUrl: url });
    } catch {
      toast.error("Failed to update avatar");
    }
  }, []);

  const uploadAvatar = useCallback(
    async (file: File) => {
      const toastId = toast.loading("Uploading avatar...");
      try {
        // Optimistic update with local file URL
        const fileUrl = URL.createObjectURL(file);
        setAvatarUrl(fileUrl);

        const formData = new FormData();
        formData.append("file", file);
        const result = await uploadPublicUserAvatarAction({
          formData,
          fileName: file.name,
          fileOptions: {
            upsert: true,
          },
        });

        if (result?.data) {
          setAvatarUrl(result.data);
          toast.success("Avatar uploaded!", { id: toastId });
        } else {
          throw new Error("Upload failed");
        }
      } catch {
        toast.error("Failed to upload avatar", { id: toastId });
        setAvatarUrl(userProfile.avatar_url ?? undefined);
      }
    },
    [userProfile.avatar_url]
  );

  const createWorkspace = useCallback(async (invitationIds?: string[]) => {
    dispatch({ type: "SET_LOADING", isLoading: true });
    try {
      // Handle invitations if any
      if (invitationIds && invitationIds.length > 0) {
        const acceptedInvitations = invitationIds.map((id) => ({
          invitationId: id,
          action: "accepted" as const,
        }));
        await bulkSettleInvitationsAction({
          invitationActions: acceptedInvitations,
        });
      }

      const uuid = uuidv4();
      // Create personal workspace
      const result = await createWorkspaceAction({
        name: "Personal Workspace",
        workspaceType: "solo",
        isOnboardingFlow: true,
        slug: slugify(`personal-${uuid}`, { lower: true }),
      });

      if (result?.serverError) {
        toast.error("Failed to create workspace");
        dispatch({ type: "SET_LOADING", isLoading: false });
        return;
      }

      dispatch({ type: "COMPLETE_STEP", step: 3 });
    } catch {
      toast.error("Failed to create workspace");
      dispatch({ type: "SET_LOADING", isLoading: false });
    }
  }, []);

  const value: OnboardingContextType = useMemo(
    () => ({
      state,
      userProfile,
      userEmail,
      pendingInvitations,
      avatarUrl,
      setAvatarUrl,
      goToStep,
      goBack,
      acceptTerms,
      updateProfile,
      updateAvatar,
      uploadAvatar,
      createWorkspace,
    }),
    [
      state,
      userProfile,
      userEmail,
      pendingInvitations,
      avatarUrl,
      goToStep,
      goBack,
      acceptTerms,
      updateProfile,
      updateAvatar,
      uploadAvatar,
      createWorkspace,
    ]
  );

  return (
    <OnboardingContext.Provider value={value}>
      {children}
    </OnboardingContext.Provider>
  );
}
