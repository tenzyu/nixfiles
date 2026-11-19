import { describe, expect, test } from "bun:test";
import { parseTraceArgs } from "../src/trace";

function traceArgs(argv: string[]) {
  const parsed = parseTraceArgs(argv);
  if (parsed.kind !== "trace") throw new Error("expected trace arguments");
  return parsed.args;
}

describe("feature trace CLI arguments", () => {
  test("--feature preserves an exact selector", () => {
    const parsed = traceArgs(["--host", "neko5", "--feature", "zsh"]);
    expect(parsed.host).toBe("neko5");
    expect(parsed.feature).toBe("zsh");
    expect(parsed.scope).toBe("all");
  });

  test("--scope home and --user retain selection", () => {
    const parsed = traceArgs([
      "--host", "neko5", "--user", "tenzyu",
      "--scope", "home", "--feature", "steam",
    ]);
    expect(parsed.user).toBe("tenzyu");
    expect(parsed.scope).toBe("home");
    expect(parsed.feature).toBe("steam");
  });

  test("help does not require a host; trace does", () => {
    expect(parseTraceArgs(["--help"])).toEqual({ kind: "help" });
    expect(() => parseTraceArgs(["--feature", "zsh"])).toThrow("--host is required");
    expect(() => parseTraceArgs(["--host", "neko5", "--user", "user", "--why", "local.foo"])).toThrow("--why takes a NixOS option path");
  });

  test("selects the documented implementation edit target", () => {
    const parsed = traceArgs(["--host", "neko5", "--edit-implementation"]);
    expect(parsed.edit).toBe(true);
    expect(parsed.editTarget).toBe("implementation");
  });

  test("rejects missing values, bad scopes and unknown flags", () => {
    expect(() => parseTraceArgs(["--host", "--json"])).toThrow("--host requires a value");
    expect(() => parseTraceArgs(["--host", ""])).toThrow("--host requires a value");
    expect(() => parseTraceArgs(["--scope", "wrong"])).toThrow("--scope must be one of");
    expect(() => parseTraceArgs(["--unknown"])).toThrow(/^feature-trace: unknown argument$/);
  });
});
