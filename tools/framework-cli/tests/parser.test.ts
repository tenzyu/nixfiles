import { expect, test } from "bun:test";
import { parseTraceArgs } from "../src/trace";

test("parseTraceArgs parses feature selector", () => {
  expect(parseTraceArgs(["--host", "neko5", "--feature", "zsh"]).feature).toBe("zsh");
});

test("parseTraceArgs rejects missing host", () => {
  expect(() => parseTraceArgs(["--feature", "zsh"])).toThrow("--host is required");
});

test("parseTraceArgs parses edit target", () => {
  const parsed = parseTraceArgs(["--host", "neko5", "--edit-config"]);
  expect(parsed.edit).toBe(true);
  expect(parsed.editTarget).toBe("implementation");
});
