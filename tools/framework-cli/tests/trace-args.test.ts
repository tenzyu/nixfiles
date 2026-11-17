import { describe, expect, test } from "bun:test";
import { parseTraceArgs } from "../src/trace";

describe("feature trace CLI arguments", () => {
  test("--feature preserves an exact selector", () => {
    const parsed = parseTraceArgs(["--host", "neko5", "--feature", "zsh"]);
    expect(parsed.host).toBe("neko5");
    expect(parsed.feature).toBe("zsh");
    expect(parsed.scope).toBe("all");
  });

  test("--scope home and --user retain selection", () => {
    const parsed = parseTraceArgs([
      "--host", "neko5", "--user", "tenzyu",
      "--scope", "home", "--feature", "steam",
    ]);
    expect(parsed.user).toBe("tenzyu");
    expect(parsed.scope).toBe("home");
    expect(parsed.feature).toBe("steam");
  });
});
