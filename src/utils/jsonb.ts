
export type SafeJSONB =
  | string
  | number
  | boolean
  | null
  | { [key: string]: SafeJSONB }
  | SafeJSONB[]

export function toSafeJSONB(input: unknown): Json {
  return typeof input === 'string'
    ? JSON.parse(input)
    : typeof input === 'object' && input !== null
      ? input
      : {}
}
