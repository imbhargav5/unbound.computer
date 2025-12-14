import { z } from "zod";

export const invitationRoleEnum = z.enum(["admin", "member", "readonly"]); // Assuming these are the possible roles
