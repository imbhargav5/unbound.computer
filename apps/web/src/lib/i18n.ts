import { defineI18n } from "fumadocs-core/i18n";
import { DEFAULT_LOCALE, LOCALES } from "@/constants";

export const i18n = defineI18n({
  defaultLanguage: DEFAULT_LOCALE,
  languages: [...LOCALES],
});
