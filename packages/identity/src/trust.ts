/**
 * Trust Relationship Management
 *
 * Manages trust relationships between devices in the device-rooted trust model.
 */

import { z } from "zod";

/**
 * Device roles in the trust hierarchy
 */
export const DeviceRoleSchema = z.enum([
  "trust_root", // Phone (iOS) - introduces devices, approves web sessions
  "trusted_executor", // Mac/Desktop - runs Claude Code, streams to viewers
  "temporary_viewer", // Web - gets short-lived session key
]);

export type DeviceRole = z.infer<typeof DeviceRoleSchema>;

/**
 * Trust relationship status
 */
export const TrustStatusSchema = z.enum([
  "pending",
  "active",
  "revoked",
  "expired",
]);

export type TrustStatus = z.infer<typeof TrustStatusSchema>;

/**
 * Trust relationship between two devices
 */
export interface TrustRelationship {
  /** Unique relationship ID */
  id: string;
  /** Device granting trust */
  grantorDeviceId: string;
  /** Device receiving trust */
  granteeDeviceId: string;
  /** Grantee's public key for verification */
  granteePublicKey: string;
  /** Trust level (1 = direct from root, 2+ = transitive) */
  trustLevel: number;
  /** Relationship status */
  status: TrustStatus;
  /** When trust was established */
  establishedAt: Date;
  /** When trust expires (optional) */
  expiresAt?: Date;
}

/**
 * Serializable trust relationship info
 */
export const TrustRelationshipInfoSchema = z.object({
  id: z.string().uuid(),
  grantorDeviceId: z.string().uuid(),
  granteeDeviceId: z.string().uuid(),
  granteePublicKey: z.string(),
  trustLevel: z.number().int().min(1).max(3),
  status: TrustStatusSchema,
  establishedAt: z.string().datetime(),
  expiresAt: z.string().datetime().optional(),
});

export type TrustRelationshipInfo = z.infer<typeof TrustRelationshipInfoSchema>;

/**
 * Options for creating a trust relationship
 */
export interface CreateTrustRelationshipOptions {
  id: string;
  grantorDeviceId: string;
  granteeDeviceId: string;
  granteePublicKey: string;
  trustLevel?: number;
}

/**
 * Create a new trust relationship
 */
export function createTrustRelationship(
  options: CreateTrustRelationshipOptions
): TrustRelationship {
  return {
    id: options.id,
    grantorDeviceId: options.grantorDeviceId,
    granteeDeviceId: options.granteeDeviceId,
    granteePublicKey: options.granteePublicKey,
    trustLevel: options.trustLevel ?? 1,
    status: "pending",
    establishedAt: new Date(),
  };
}

/**
 * Activate a pending trust relationship
 */
export function activateTrust(
  relationship: TrustRelationship,
  expiresAt?: Date
): TrustRelationship {
  return {
    ...relationship,
    status: "active",
    expiresAt,
  };
}

/**
 * Revoke a trust relationship
 */
export function revokeTrust(
  relationship: TrustRelationship
): TrustRelationship {
  return {
    ...relationship,
    status: "revoked",
  };
}

/**
 * Check if a trust relationship is valid (active and not expired)
 */
export function isTrustValid(relationship: TrustRelationship): boolean {
  if (relationship.status !== "active") {
    return false;
  }
  if (relationship.expiresAt && relationship.expiresAt < new Date()) {
    return false;
  }
  return true;
}

/**
 * Serialize a trust relationship for storage/transport
 */
export function serializeTrustRelationship(
  relationship: TrustRelationship
): TrustRelationshipInfo {
  return {
    id: relationship.id,
    grantorDeviceId: relationship.grantorDeviceId,
    granteeDeviceId: relationship.granteeDeviceId,
    granteePublicKey: relationship.granteePublicKey,
    trustLevel: relationship.trustLevel,
    status: relationship.status,
    establishedAt: relationship.establishedAt.toISOString(),
    expiresAt: relationship.expiresAt?.toISOString(),
  };
}

/**
 * Deserialize a trust relationship from storage/transport
 */
export function deserializeTrustRelationship(
  info: TrustRelationshipInfo
): TrustRelationship {
  return {
    id: info.id,
    grantorDeviceId: info.grantorDeviceId,
    granteeDeviceId: info.granteeDeviceId,
    granteePublicKey: info.granteePublicKey,
    trustLevel: info.trustLevel,
    status: info.status,
    establishedAt: new Date(info.establishedAt),
    expiresAt: info.expiresAt ? new Date(info.expiresAt) : undefined,
  };
}

/**
 * Validate trust relationship info
 */
export function validateTrustRelationshipInfo(
  info: unknown
): TrustRelationshipInfo {
  return TrustRelationshipInfoSchema.parse(info);
}
