'use server'

import { getLoggedInUserWorkspaceRole, getMaybeDefaultWorkspace, getSoloWorkspace, getWorkspaceBySlug } from "@/data/user/workspaces";
import { cache } from "react";

export const getCachedWorkspaceBySlug = cache(getWorkspaceBySlug);

export const getCachedLoggedInUserWorkspaceRole = cache(getLoggedInUserWorkspaceRole);

export const getCachedDefaultWorkspace = cache(getMaybeDefaultWorkspace);

export const getCachedSoloWorkspace = cache(getSoloWorkspace);
