import * as initials from "@dicebear/collection";
import { createAvatar } from "@dicebear/core";

/**
 * Available avatar styles for user selection
 */
export const AVATAR_STYLES = [
  "initials",
  "shapes",
  "adventurer",
  "bottts",
  "personas",
  "funEmoji",
  "lorelei",
  "notionists",
  "thumbs",
] as const;

/**
 * Default seeds for generating avatar picker grid
 */
export const AVATAR_SEEDS = ["felix", "aneka", "sasha", "leo"] as const;

export type AvatarStyle = (typeof AVATAR_STYLES)[number];

/**
 * Generate a DiceBear avatar SVG string
 * @param seed - Unique identifier (email, userId, or custom string)
 * @param style - Avatar style to use
 * @returns SVG string that can be used as data URI or rendered directly
 */
export function generateAvatar(
  seed: string,
  style: AvatarStyle = "initials"
): string {
  const collection = initials as Record<string, any>;
  const avatarStyle = collection[style];

  if (!avatarStyle) {
    throw new Error(`Avatar style "${style}" not found`);
  }

  const avatar = createAvatar(avatarStyle, {
    seed,
    size: 128,
  });

  return avatar.toString();
}

/**
 * Generate a data URI for use in img src
 * @param seed - Unique identifier
 * @param style - Avatar style
 * @returns Data URI string
 */
export function generateAvatarDataUri(
  seed: string,
  style: AvatarStyle = "initials"
): string {
  const svg = generateAvatar(seed, style);
  // Use URL encoding instead of base64 to avoid Unicode issues with btoa()
  const encoded = encodeURIComponent(svg)
    .replace(/'/g, "%27")
    .replace(/"/g, "%22");
  return `data:image/svg+xml,${encoded}`;
}

/**
 * Get all avatar options for a given seed
 * @param seed - Unique identifier
 * @returns Array of {style, dataUri} objects
 */
export function getAllAvatarOptions(seed: string) {
  return AVATAR_STYLES.map((style) => ({
    style,
    dataUri: generateAvatarDataUri(seed, style),
  }));
}

/**
 * Generate avatar grid for picker dialog
 * Creates avatars for all styles with multiple seeds
 * @returns Array of avatar options with url, seed, and style
 */
export function generateAvatarPickerGrid() {
  const avatars: { url: string; seed: string; style: AvatarStyle }[] = [];
  for (const style of AVATAR_STYLES) {
    for (const seed of AVATAR_SEEDS) {
      avatars.push({
        url: generateAvatarDataUri(seed, style),
        seed,
        style,
      });
    }
  }
  return avatars;
}

/**
 * Generate initials from a full name
 * @param fullName - User's full name
 * @returns Initials (max 2 characters)
 */
export function getInitials(fullName: string): string {
  if (!fullName.trim()) return "?";

  const words = fullName.trim().split(/\s+/);

  if (words.length === 1) {
    return words[0].charAt(0).toUpperCase();
  }

  return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase();
}
