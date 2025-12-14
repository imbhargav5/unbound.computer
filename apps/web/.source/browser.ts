// @ts-nocheck
import { browser } from 'fumadocs-mdx/runtime/browser';
import type * as Config from '../source.config';

const create = browser<typeof Config, import("fumadocs-mdx/runtime/types").InternalTypeConfig & {
  DocData: {
  }
}>();
const browserCollections = {
  docs: create.doc("docs", {"api-reference.mdx": () => import("../src/content/docs/api-reference.mdx?collection=docs"), "components.mdx": () => import("../src/content/docs/components.mdx?collection=docs"), "getting-started.mdx": () => import("../src/content/docs/getting-started.mdx?collection=docs"), "test.mdx": () => import("../src/content/docs/test.mdx?collection=docs"), }),
};
export default browserCollections;