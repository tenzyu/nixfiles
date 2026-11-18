import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { TraceResult } from "../src/trace";

const dir = mkdtempSync(join(tmpdir(), "framework-trace-"));
const log = join(dir, "editor.log");

function executable(name: string, source: string): string {
  const path = join(dir, name);
  writeFileSync(path, `#!${process.execPath}\n${source}\n`, { mode: 0o755 });
  return path;
}

executable("git", 'console.log("/fixture checkout")');
executable("nix", `
  const args = process.argv;
  if (args[args.indexOf("flakeRef") + 1] !== "git+file:///fixture%20checkout") process.exit(8);
  if (process.env.TRACE_FAIL) {
    console.error("fixture Nix evaluation failed");
    process.exit(7);
  }
  console.log(process.env.TRACE_JSON);
`);
executable("fzf", "process.exit(130)");
const editor = executable("editor", `
  import { writeFileSync } from "node:fs";
  writeFileSync(process.env.EDITOR_LOG, JSON.stringify(process.argv.slice(2)));
`);

afterAll(() => rmSync(dir, { recursive: true, force: true }));

const hint = {
  source: "modules/host.nix",
  line: 23,
  kind: "user-seed",
  origin: "text-scan",
};
const home: TraceResult = {
  type: "host",
  host: "fixture",
  system: [],
  home: [{
    name: "zsh",
    scope: "home",
    user: "alice",
    status: "enabled",
    kind: "user-seed",
    activations: [hint],
    source_hints: [hint],
    implementations: [{
      source: "modules/zsh.nix",
      line: null,
      kind: "feature-module",
      origin: "module-registry-scan",
    }],
    effects: [],
  }],
};
const why: TraceResult = {
  type: "why",
  path: "services.openssh.enable",
  effective: "true",
  definitions: [{
    source: "modules/ssh.nix",
    line: null,
    kind: "direct",
    origin: "definitionsWithLocations",
    value: true,
    renderedValue: "true",
  }],
};

function trace(args: string[], result: TraceResult = home, failure = false) {
  const invocation = Bun.spawnSync([
    process.execPath, join(import.meta.dir, "../src/main.ts"), "trace", "--host", "fixture", ...args,
  ], {
    env: {
      ...process.env,
      PATH: `${dir}:${process.env.PATH}`,
      FEATURE_TRACE_LIB: "/fixture/feature-trace.nix",
      TRACE_JSON: JSON.stringify(result),
      TRACE_FAIL: failure ? "1" : "",
      VISUAL: editor,
      EDITOR_LOG: log,
    },
  });
  return {
    status: invocation.exitCode,
    stdout: invocation.stdout.toString(),
    stderr: invocation.stderr.toString(),
  };
}

test("JSON preserves the evaluator's response even when edit is requested", () => {
  const result = trace(["--why", why.path, "--json", "--edit"], why);
  expect(result.status).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual(why);
});

test("human-readable output shows feature hints and the effective why value", () => {
  const host = trace(["--feature", "zsh", "--scope", "home", "--user", "alice"]);
  expect(host.status).toBe(0);
  expect(host.stdout).toContain("HOME FEATURES / alice@fixture");
  expect(host.stdout).toContain("modules/host.nix:23 (source hint)");

  const option = trace(["--why", why.path], why);
  expect(option.status).toBe(0);
  expect(option.stdout).toContain("Effective value for services.openssh.enable: true");
  expect(option.stdout).toContain("modules/ssh.nix");
});

test("home activation edit passes the source line to the editor", () => {
  const result = trace(["--feature", "zsh", "--scope", "home", "--user", "alice", "--edit-activation"]);
  expect(result.status).toBe(0);
  expect(JSON.parse(readFileSync(log, "utf8"))).toEqual(["+23", "/fixture checkout/modules/host.nix"]);
});

test("fzf cancellation exits with the CLI diagnostic", () => {
  const result = trace(["--edit"]);
  expect(result.status).toBe(1);
  expect(result.stderr).toContain("feature-trace: edit cancelled");
});

test("Nix evaluation failure surfaces stderr and prevents rendering", () => {
  const result = trace(["--json"], home, true);
  expect(result.status).toBe(1);
  expect(result.stdout).toBe("");
  expect(result.stderr).toContain("fixture Nix evaluation failed");
});
