import { adminMiddleware } from "./admin-middleware";
import { authMiddleware } from "./auth-middleware";
import {
  dashboardOnboardingMiddleware,
  onboardingRedirectMiddleware,
} from "./onboarding-middleware";
import type { MiddlewareConfig } from "./types";

export const middlewareList: MiddlewareConfig[] = [
  authMiddleware,
  dashboardOnboardingMiddleware,
  onboardingRedirectMiddleware,
  adminMiddleware,
];
