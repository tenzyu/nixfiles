import { expect, test } from "bun:test";
import { parseTraceArgs } from "../src/trace";

test("parseTraceArgs parses feature selector", () => {
  expect(parseTraceArgs(["--host", "neko5", "--feature", "zsh"]).feature).toBe("zsh");
});

test("parseTraceArgs retains an absent host for traceCommand validation", () => {
  expect(parseTraceArgs(["--feature", "zsh"]).host).toBe("");
});

test("parseTraceArgs parses the documented implementation edit target", () => {
  const parsed = parseTraceArgs(["--host", "neko5", "--edit-implementation"]);
  expect(parsed.edit).toBe(true);
  expect(parsed.editTarget).toBe("implementation");
});
