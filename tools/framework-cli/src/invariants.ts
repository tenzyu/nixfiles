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

  const seedEnableTypes = JSON.parse(await runOk([
    "nix",
    "eval",
    "--json",
    "--impure",
    "--expr",
    `
      let
        flake = builtins.getFlake "path:${repo}";
        nixosOptions = flake.debug.options.configurations.nixos;
        neko7ModuleOpts = nixosOptions.type.getSubOptions [ "neko7" ];
        localOpts = neko7ModuleOpts.module.type.getSubOptions [];
        tenzyuFeatureOpts = localOpts.local.users.type.getSubOptions [ "tenzyu" ];
        homeModuleOpts = flake.debug.options.configurations.homeManager.type.getSubOptions [ "standalone" ];
        homeOpts = homeModuleOpts.module.type.getSubOptions [];
      in {
        system = localOpts.local.features.ssh.enable.type.name;
        user = tenzyuFeatureOpts.features.steam.enable.type.name;
        standalone = homeOpts.local.features.steam.enable.type.name;
      }
    `,
  ]));
  checkEq(
    "configurations.nixos.neko7.module.local.features.ssh.enable.type.name",
    "nullOr",
    seedEnableTypes.system,
  );
  checkEq(
    "local.users.tenzyu.features.steam.enable.type.name",
    "nullOr",
    seedEnableTypes.user,
  );
  checkEq(
    "configurations.homeManager.<name>.module.local.features.steam.enable.type.name",
    "nullOr",
    seedEnableTypes.standalone,
  );
}

export async function frameworkTestCommand(): Promise<void> {
  const { unitTestsCommand } = await import("./test-command");
  await unitTestsCommand();
  console.log("");
  await invariantsCommand();
  const repo = await repoRoot();
  const failures = await runOk([
    "nix",
    "eval",
    "--impure",
    "--json",
    "--file",
    `${repo}/modules/_internal/configurations/tests/configurations.nix`,
    "--argstr",
    "flakeRef",
    `path:${repo}`,
    "failures",
  ]);
  if (JSON.parse(failures).length) {
    throw new Error(`configuration adapter tests failed: ${failures}`);
  }
  console.log("OK   configuration adapter integration tests");
  console.log("\nframework-test: ok");
}
