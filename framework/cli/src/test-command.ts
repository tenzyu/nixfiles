import { runOk } from "./process";

export async function unitTestsCommand(): Promise<void> {
  const suite = Bun.env.FRAMEWORK_TEST_SUITE;
  if (!suite) throw new Error("FRAMEWORK_TEST_SUITE is not set");

  const tmpdir = Bun.env.TMPDIR ?? "/tmp";
  const roots = `${tmpdir}/framework-test-gc-roots-${Date.now()}-${Math.random().toString(36).slice(2)}`;

  console.log("== framework nix-unit ==");
  const output = await runOk(["nix-unit", "--show-trace", "--gc-roots-dir", roots, suite]);
  if (output.trim()) console.log(output.trimEnd());
}
