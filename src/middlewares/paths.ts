import urlJoin from "url-join";
import { LOCALE_GLOB_PATTERN } from "../constants";

export const publicPaths = [
  `/`,
  `/changelog`,
  `/feedback(/.*)?`,
  `/roadmap`,
  `/auth(/.*)?`,
  `/confirm-delete-user(/.*)?`,
  `/forgot-password(/.*)?`,
  `/login(/.*)?`,
  `/sign-up(/.*)?`,
  `/update-password(/.*)?`,
  `/roadmap`,
  `/version2`,
  `/blog(/.*)?`,
  `/docs(/.*)?`,
  `/terms`,
  `/waitlist(/.*)?`,
  `/500(/.*)?`,
  `/404(/.*)?`,
  `/oops(/.*)?`,
];

export const dashboardRoutes = [
  `/dashboard(/.*)?`,
  `/settings(/.*)?`,
  `/profile(/.*)?`,
  `/workspace(/.*)?`,
  `/project(/.*)?`,
  `/home(/.*)?`,
  `/settings(/.*)?`,
  `/user(/.*)?`,
  `/logout`,
];

const onboardingPaths = [`/onboarding(/.*)?`];
const appAdminPaths = [`/app_admin(/.*)?`];
const protectedPaths = [
  ...dashboardRoutes,
  ...onboardingPaths,
  ...appAdminPaths,
];
const rootPaths = ["/"];
export const allPaths = [...publicPaths, ...protectedPaths];

// Paths with locale
export const publicPathsWithLocale = publicPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

export const dashboardRoutesWithLocale = dashboardRoutes.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

export const onboardingPathsWithLocale = onboardingPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

export const appAdminPathsWithLocale = appAdminPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

export const protectedPathsWithLocale = [
  ...dashboardRoutesWithLocale,
  ...onboardingPathsWithLocale,
  ...appAdminPathsWithLocale,
];

export const rootPathsWithLocale = rootPaths.map((path) =>
  urlJoin("/", `(${LOCALE_GLOB_PATTERN})`, path),
);

export const allSubPathsWithLocale = [
  ...rootPathsWithLocale,
  ...publicPathsWithLocale,
  ...protectedPathsWithLocale,
];
