'use server'

import { getLoggedInUserWorkspaceRole, getWorkspaceBySlug } from "@/data/user/workspaces";
import { cache } from "react";

export const getCachedWorkspaceBySlug = cache(getWorkspaceBySlug);

export const getCachedLoggedInUserWorkspaceRole = cache(getLoggedInUserWorkspaceRole);
