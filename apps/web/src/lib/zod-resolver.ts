import { zodResolver as baseZodResolver } from "@hookform/resolvers/zod";
import type { FieldValues, Resolver } from "react-hook-form";
import type { z } from "zod";

/**
 * Typed wrapper for zodResolver that works with Zod 4.1.x
 * Workaround for https://github.com/react-hook-form/resolvers/issues/813
 */
export function zodResolver<T extends z.ZodType<FieldValues>>(
  schema: T
): Resolver<z.infer<T>> {
  type ZodResolverInput = Parameters<typeof baseZodResolver>[0];
  return baseZodResolver(schema as ZodResolverInput) as unknown as Resolver<
    z.infer<T>
  >;
}
