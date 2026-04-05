// @vitest-environment jsdom

import { act, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DesktopOnboardingView } from "./desktopOnboardingView";

(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true;

describe("DesktopOnboardingView", () => {
  let container: HTMLDivElement | null = null;
  let root: Root | null = null;

  const render = (
    props: Partial<ComponentProps<typeof DesktopOnboardingView>> = {},
  ) => {
    const nextContainer = document.createElement("div");
    container = nextContainer;
    document.body.appendChild(nextContainer);
    root = createRoot(nextContainer);

    act(() => {
      root?.render(
        <DesktopOnboardingView
          onComplete={() => undefined}
          repositoryCount={2}
          {...props}
        />,
      );
    });

    return nextContainer;
  };

  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
  });

  it("advances through the onboarding pages before completing", () => {
    const onComplete = vi.fn();
    const view = render({ onComplete });

    expect(view.textContent).toContain("Welcome to Unbound Desktop");

    const clickPrimary = () => {
      const buttons = Array.from(view.querySelectorAll("button"));
      const primary = buttons.find(
        (button) =>
          button.textContent?.includes("Next") ||
          button.textContent?.includes("Get started"),
      );
      act(() => {
        primary?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      });
    };

    clickPrimary();
    expect(view.textContent).toContain("Your machines stay in sync");
    expect(onComplete).not.toHaveBeenCalled();

    clickPrimary();
    expect(view.textContent).toContain(
      "Every conversation stays attached to the work",
    );
    expect(onComplete).not.toHaveBeenCalled();

    clickPrimary();
    expect(onComplete).toHaveBeenCalledTimes(1);
  });

  it("allows skipping from the first page", () => {
    const onComplete = vi.fn();
    const view = render({ onComplete });

    const skipButton = Array.from(view.querySelectorAll("button")).find(
      (button) => button.textContent?.includes("Skip"),
    );

    act(() => {
      skipButton?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(onComplete).toHaveBeenCalledTimes(1);
  });
});
