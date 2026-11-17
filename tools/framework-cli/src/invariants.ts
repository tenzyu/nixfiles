import { runOk } from "./process";

async function repoRoot(): Promise<string> {
  const result = await runOk(["git", "rev-parse", "--show-toplevel"]).catch(() => "");
  return result.trim() || process.cwd();
}

async function nixEvalRaw(args: string[]): Promise<string> {
  return (await runOk(["nix", "eval", "--raw", ...args])).trim();
}

function checkEq(name: string, expected: string, actual: string): void {
  if (actual !== expected) {
    throw new Error(`FAIL ${name}: expected ${expected}, got ${actual}`);
  }
  console.log(`OK   ${name}: ${actual}`);
}

export async function invariantsCommand(): Promise<void> {
  const repo = await repoRoot();
  const flakeRef = `path:${repo}`;

  console.log("== framework invariants ==");

  checkEq(
    "debug.options.configurations.nixos.type.name",
    "attrsOf",
    await nixEvalRaw([`${flakeRef}#debug.options.configurations.nixos.type.name`]),
  );

  checkEq(
    "debug.options.configurations.homeManager.type.name",
    "attrsOf",
    await nixEvalRaw([`${flakeRef}#debug.options.configurations.homeManager.type.name`]),
  );

  const seedEnableType = await nixEvalRaw([
    "--impure",
    "--expr",
    `
      let
        flake = builtins.getFlake "path:${repo}";
        nixosOptions = flake.debug.options.configurations.nixos;
        neko5ModuleOpts = nixosOptions.type.getSubOptions [ "neko5" ];
        localOpts = neko5ModuleOpts.module.type.getSubOptions [];
        tenzyuFeatureOpts = localOpts.local.users.type.getSubOptions [ "tenzyu" ];
      in
        tenzyuFeatureOpts.features.steam.enable.type.name
    `,
  ]);

  checkEq(
    "local.users.tenzyu.features.steam.enable.type.name",
    "nullOr",
    seedEnableType,
  );
}

export async function frameworkTestCommand(): Promise<void> {
  const { unitTestsCommand } = await import("./test-command");
  await unitTestsCommand();
  console.log("");
  await invariantsCommand();
  console.log("\nframework-test: ok");
}
