"use server";

import { cache } from "react";
import {
  fetchSlimWorkspaces,
  getLoggedInUserWorkspaceRole,
  getMaybeDefaultWorkspace,
  getWorkspaceById,
  getWorkspaceBySlug,
} from "@/data/user/workspaces";

export const getCachedWorkspaceBySlug = cache(getWorkspaceBySlug);

export const getCachedLoggedInUserWorkspaceRole = cache(
  getLoggedInUserWorkspaceRole
);

export const getCachedDefaultWorkspace = cache(getMaybeDefaultWorkspace);

export const getCachedSlimWorkspaces = cache(fetchSlimWorkspaces);

export const getCachedWorkspaceById = cache(getWorkspaceById);
