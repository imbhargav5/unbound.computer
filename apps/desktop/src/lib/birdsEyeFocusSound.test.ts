import { describe, expect, it } from "vitest";

import { shouldPlayBirdsEyeFocusSound } from "./birdsEyeFocusSound";

describe("shouldPlayBirdsEyeFocusSound", () => {
  it("plays for keyboard-driven focus changes", () => {
    expect(
      shouldPlayBirdsEyeFocusSound("project:1", "folder:1", "keyboard"),
    ).toBe(true);
  });

  it("plays for click-driven focus changes", () => {
    expect(shouldPlayBirdsEyeFocusSound("folder:1", "chat:1", "click")).toBe(
      true,
    );
  });

  it("stays silent for programmatic focus changes", () => {
    expect(
      shouldPlayBirdsEyeFocusSound("chat:1", "chat:2", "programmatic"),
    ).toBe(false);
  });

  it("stays silent when focus does not actually change", () => {
    expect(shouldPlayBirdsEyeFocusSound("chat:1", "chat:1", "keyboard")).toBe(
      false,
    );
    expect(shouldPlayBirdsEyeFocusSound("chat:1", null, "keyboard")).toBe(
      false,
    );
  });
});
