// @ts-nocheck

import { server } from "fumadocs-mdx/runtime/server";
import type * as Config from "../source.config";
import * as __fd_glob_0 from "../src/content/docs/api-reference.mdx?collection=docs";
import * as __fd_glob_1 from "../src/content/docs/components.mdx?collection=docs";
import * as __fd_glob_2 from "../src/content/docs/getting-started.mdx?collection=docs";
import * as __fd_glob_3 from "../src/content/docs/test.mdx?collection=docs";

const create = server<
  typeof Config,
  import("fumadocs-mdx/runtime/types").InternalTypeConfig & {
    DocData: {};
  }
>({ doc: { passthroughs: ["extractedReferences"] } });

export const docs = await create.docs(
  "docs",
  "src/content/docs",
  {},
  {
    "api-reference.mdx": __fd_glob_0,
    "components.mdx": __fd_glob_1,
    "getting-started.mdx": __fd_glob_2,
    "test.mdx": __fd_glob_3,
  }
);
