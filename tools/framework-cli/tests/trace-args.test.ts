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

  test("retains an absent host for command validation", () => {
    expect(parseTraceArgs(["--feature", "zsh"]).host).toBe("");
  });

  test("selects the documented implementation edit target", () => {
    const parsed = parseTraceArgs(["--host", "neko5", "--edit-implementation"]);
    expect(parsed.edit).toBe(true);
    expect(parsed.editTarget).toBe("implementation");
  });

  test("rejects missing values, bad scopes and unknown flags", () => {
    expect(() => parseTraceArgs(["--host", "--json"])).toThrow("--host requires a value");
    expect(() => parseTraceArgs(["--scope", "wrong"])).toThrow("--scope must be one of");
    expect(() => parseTraceArgs(["--unknown"])).toThrow("unknown argument: --unknown");
  });
});
