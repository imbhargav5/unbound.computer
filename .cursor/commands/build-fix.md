Build fix

# Overview build the project and fix if there are build errors

1. First always run pnpm tsc and check if there are tsc errors. pnpm tsc finishes faster than pnpm build, so we can find tsc errors quicker than waiting to find them in the build.
2. if there pnpm tsc errors, fix them first.
3. If there are no more pnpm tsc errors, Use pnpm build to build the project and fix build errors.
