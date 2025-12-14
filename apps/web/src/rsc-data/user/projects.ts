"use server";

import { cache } from "react";
import {
  getProjectById,
  getProjectBySlug,
  getProjectComments,
  getProjects,
  getProjectsForWorkspace,
  getProjectsTotalCount,
  getProjectsTotalCountForWorkspace,
  getProjectTitleById,
  getSlimProjectById,
  getSlimProjectByIdForWorkspace,
  getSlimProjectBySlug,
  getSlimProjectBySlugForWorkspace,
} from "@/data/user/projects";

export const getCachedSlimProjectById = cache(getSlimProjectById);
export const getCachedSlimProjectBySlug = cache(getSlimProjectBySlug);
export const getCachedProjectById = cache(getProjectById);
export const getCachedProjectBySlug = cache(getProjectBySlug);
export const getCachedProjectTitleById = cache(getProjectTitleById);
export const getCachedProjectComments = cache(getProjectComments);
export const getCachedProjects = cache(getProjects);
export const getCachedProjectsTotalCount = cache(getProjectsTotalCount);
export const getCachedSlimProjectByIdForWorkspace = cache(
  getSlimProjectByIdForWorkspace
);
export const getCachedSlimProjectBySlugForWorkspace = cache(
  getSlimProjectBySlugForWorkspace
);
export const getCachedProjectsForWorkspace = cache(getProjectsForWorkspace);
export const getCachedProjectsTotalCountForWorkspace = cache(
  getProjectsTotalCountForWorkspace
);
