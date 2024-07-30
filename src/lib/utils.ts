import { clsx, type ClassValue } from 'clsx';
import { customAlphabet } from 'nanoid';
import slugify from 'slugify';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const generateSlug = (title: string, {
  withNanoIdSuffix = true
}: {
  withNanoIdSuffix?: boolean
} = {}) => {
  const slug = slugify(title, {
    lower: true,
    strict: true,
    replacement: '-',
  });
  return withNanoIdSuffix ? `${slug}-${nanoid()}` : slug;
}

export const nanoid = customAlphabet(
  '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
  7,
); //
