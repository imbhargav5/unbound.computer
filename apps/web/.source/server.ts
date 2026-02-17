// @ts-nocheck

import { server } from "fumadocs-mdx/runtime/server";
import type * as Config from "../source.config";
import * as __fd_glob_6 from "../src/content/docs/about.mdx?collection=docs";
import * as __fd_glob_9 from "../src/content/docs/internals/apps/database.mdx?collection=docs";
import * as __fd_glob_10 from "../src/content/docs/internals/apps/ios.mdx?collection=docs";
import * as __fd_glob_11 from "../src/content/docs/internals/apps/macos.mdx?collection=docs";
import { default as __fd_glob_2 } from "../src/content/docs/internals/apps/meta.json?collection=docs";
import * as __fd_glob_12 from "../src/content/docs/internals/apps/web.mdx?collection=docs";
import * as __fd_glob_13 from "../src/content/docs/internals/daemon/armin.mdx?collection=docs";
import * as __fd_glob_14 from "../src/content/docs/internals/daemon/bakugou.mdx?collection=docs";
import * as __fd_glob_15 from "../src/content/docs/internals/daemon/daemon-auth.mdx?collection=docs";
import * as __fd_glob_16 from "../src/content/docs/internals/daemon/daemon-bin.mdx?collection=docs";
import * as __fd_glob_17 from "../src/content/docs/internals/daemon/daemon-config-and-utils.mdx?collection=docs";
import * as __fd_glob_18 from "../src/content/docs/internals/daemon/daemon-database.mdx?collection=docs";
import * as __fd_glob_19 from "../src/content/docs/internals/daemon/daemon-ipc.mdx?collection=docs";
import * as __fd_glob_20 from "../src/content/docs/internals/daemon/daemon-storage.mdx?collection=docs";
import * as __fd_glob_21 from "../src/content/docs/internals/daemon/deku.mdx?collection=docs";
import * as __fd_glob_22 from "../src/content/docs/internals/daemon/eren-machines.mdx?collection=docs";
import * as __fd_glob_23 from "../src/content/docs/internals/daemon/gyomei.mdx?collection=docs";
import * as __fd_glob_24 from "../src/content/docs/internals/daemon/historia-lifecycle.mdx?collection=docs";
import * as __fd_glob_25 from "../src/content/docs/internals/daemon/itachi.mdx?collection=docs";
import * as __fd_glob_26 from "../src/content/docs/internals/daemon/levi.mdx?collection=docs";
import { default as __fd_glob_3 } from "../src/content/docs/internals/daemon/meta.json?collection=docs";
import * as __fd_glob_27 from "../src/content/docs/internals/daemon/one-for-all-protocol.mdx?collection=docs";
import * as __fd_glob_28 from "../src/content/docs/internals/daemon/piccolo.mdx?collection=docs";
import * as __fd_glob_29 from "../src/content/docs/internals/daemon/rengoku-sessions.mdx?collection=docs";
import * as __fd_glob_30 from "../src/content/docs/internals/daemon/sakura-working-dir-resolution.mdx?collection=docs";
import * as __fd_glob_31 from "../src/content/docs/internals/daemon/sasuke-crypto.mdx?collection=docs";
import * as __fd_glob_32 from "../src/content/docs/internals/daemon/tien.mdx?collection=docs";
import * as __fd_glob_33 from "../src/content/docs/internals/daemon/toshinori.mdx?collection=docs";
import * as __fd_glob_34 from "../src/content/docs/internals/daemon/yagami.mdx?collection=docs";
import * as __fd_glob_35 from "../src/content/docs/internals/daemon/yamcha.mdx?collection=docs";
import * as __fd_glob_36 from "../src/content/docs/internals/daemon/ymir.mdx?collection=docs";
import * as __fd_glob_8 from "../src/content/docs/internals/index.mdx?collection=docs";
import { default as __fd_glob_1 } from "../src/content/docs/internals/meta.json?collection=docs";
import * as __fd_glob_40 from "../src/content/docs/internals/packages/agent-runtime.mdx?collection=docs";
import * as __fd_glob_41 from "../src/content/docs/internals/packages/crypto.mdx?collection=docs";
import * as __fd_glob_43 from "../src/content/docs/internals/packages/daemon-ably.mdx?collection=docs";
import * as __fd_glob_42 from "../src/content/docs/internals/packages/daemon-ably-client.mdx?collection=docs";
import * as __fd_glob_44 from "../src/content/docs/internals/packages/daemon-falco.mdx?collection=docs";
import * as __fd_glob_45 from "../src/content/docs/internals/packages/daemon-nagato.mdx?collection=docs";
import * as __fd_glob_46 from "../src/content/docs/internals/packages/git-worktree.mdx?collection=docs";
import { default as __fd_glob_4 } from "../src/content/docs/internals/packages/meta.json?collection=docs";
import * as __fd_glob_47 from "../src/content/docs/internals/packages/observability.mdx?collection=docs";
import * as __fd_glob_48 from "../src/content/docs/internals/packages/protocol.mdx?collection=docs";
import * as __fd_glob_49 from "../src/content/docs/internals/packages/redis.mdx?collection=docs";
import * as __fd_glob_50 from "../src/content/docs/internals/packages/session.mdx?collection=docs";
import * as __fd_glob_51 from "../src/content/docs/internals/packages/transport-reliability.mdx?collection=docs";
import * as __fd_glob_52 from "../src/content/docs/internals/packages/typescript-config.mdx?collection=docs";
import * as __fd_glob_53 from "../src/content/docs/internals/packages/web-session.mdx?collection=docs";
import { default as __fd_glob_5 } from "../src/content/docs/internals/web/meta.json?collection=docs";
import * as __fd_glob_37 from "../src/content/docs/internals/web/navigation-fns.mdx?collection=docs";
import * as __fd_glob_38 from "../src/content/docs/internals/web/request-memoization.mdx?collection=docs";
import * as __fd_glob_39 from "../src/content/docs/internals/web/rsc-data.mdx?collection=docs";
import { default as __fd_glob_0 } from "../src/content/docs/meta.json?collection=docs";
import * as __fd_glob_7 from "../src/content/docs/overview.mdx?collection=docs";

const create = server<
  typeof Config,
  import("fumadocs-mdx/runtime/types").InternalTypeConfig & {
    DocData: {};
  }
>({ doc: { passthroughs: ["extractedReferences"] } });

export const docs = await create.docs(
  "docs",
  "src/content/docs",
  {
    "meta.json": __fd_glob_0,
    "internals/meta.json": __fd_glob_1,
    "internals/apps/meta.json": __fd_glob_2,
    "internals/daemon/meta.json": __fd_glob_3,
    "internals/packages/meta.json": __fd_glob_4,
    "internals/web/meta.json": __fd_glob_5,
  },
  {
    "about.mdx": __fd_glob_6,
    "overview.mdx": __fd_glob_7,
    "internals/index.mdx": __fd_glob_8,
    "internals/apps/database.mdx": __fd_glob_9,
    "internals/apps/ios.mdx": __fd_glob_10,
    "internals/apps/macos.mdx": __fd_glob_11,
    "internals/apps/web.mdx": __fd_glob_12,
    "internals/daemon/armin.mdx": __fd_glob_13,
    "internals/daemon/bakugou.mdx": __fd_glob_14,
    "internals/daemon/daemon-auth.mdx": __fd_glob_15,
    "internals/daemon/daemon-bin.mdx": __fd_glob_16,
    "internals/daemon/daemon-config-and-utils.mdx": __fd_glob_17,
    "internals/daemon/daemon-database.mdx": __fd_glob_18,
    "internals/daemon/daemon-ipc.mdx": __fd_glob_19,
    "internals/daemon/daemon-storage.mdx": __fd_glob_20,
    "internals/daemon/deku.mdx": __fd_glob_21,
    "internals/daemon/eren-machines.mdx": __fd_glob_22,
    "internals/daemon/gyomei.mdx": __fd_glob_23,
    "internals/daemon/historia-lifecycle.mdx": __fd_glob_24,
    "internals/daemon/itachi.mdx": __fd_glob_25,
    "internals/daemon/levi.mdx": __fd_glob_26,
    "internals/daemon/one-for-all-protocol.mdx": __fd_glob_27,
    "internals/daemon/piccolo.mdx": __fd_glob_28,
    "internals/daemon/rengoku-sessions.mdx": __fd_glob_29,
    "internals/daemon/sakura-working-dir-resolution.mdx": __fd_glob_30,
    "internals/daemon/sasuke-crypto.mdx": __fd_glob_31,
    "internals/daemon/tien.mdx": __fd_glob_32,
    "internals/daemon/toshinori.mdx": __fd_glob_33,
    "internals/daemon/yagami.mdx": __fd_glob_34,
    "internals/daemon/yamcha.mdx": __fd_glob_35,
    "internals/daemon/ymir.mdx": __fd_glob_36,
    "internals/web/navigation-fns.mdx": __fd_glob_37,
    "internals/web/request-memoization.mdx": __fd_glob_38,
    "internals/web/rsc-data.mdx": __fd_glob_39,
    "internals/packages/agent-runtime.mdx": __fd_glob_40,
    "internals/packages/crypto.mdx": __fd_glob_41,
    "internals/packages/daemon-ably-client.mdx": __fd_glob_42,
    "internals/packages/daemon-ably.mdx": __fd_glob_43,
    "internals/packages/daemon-falco.mdx": __fd_glob_44,
    "internals/packages/daemon-nagato.mdx": __fd_glob_45,
    "internals/packages/git-worktree.mdx": __fd_glob_46,
    "internals/packages/observability.mdx": __fd_glob_47,
    "internals/packages/protocol.mdx": __fd_glob_48,
    "internals/packages/redis.mdx": __fd_glob_49,
    "internals/packages/session.mdx": __fd_glob_50,
    "internals/packages/transport-reliability.mdx": __fd_glob_51,
    "internals/packages/typescript-config.mdx": __fd_glob_52,
    "internals/packages/web-session.mdx": __fd_glob_53,
  }
);
