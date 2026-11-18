import { repository, runOk } from "./process";

function checkEq(name: string, expected: string, actual: string): void {
  if (actual !== expected) {
    throw new Error(`FAIL ${name}: expected ${expected}, got ${actual}`);
  }
  console.log(`OK   ${name}: ${actual}`);
}

export async function invariantsCommand(): Promise<void> {
  const { flakeRef } = await repository();

  console.log("== framework invariants ==");

  const types = JSON.parse(await runOk([
    "nix",
    "eval",
    "--json",
    "--impure",
    "--expr",
    `
      { flakeRef }: let
        inherit ((builtins.getFlake flakeRef).debug.options.configurations) nixos homeManager;
        localOptions = kind: name:
          (((kind.type.getSubOptions [name]).module.type.getSubOptions []).local);
        system = localOptions nixos "neko7";
        user = system.users.type.getSubOptions ["tenzyu"];
        standalone = localOptions homeManager "standalone";
      in {
        types = [
          nixos.type.name
          homeManager.type.name
          system.features.ssh.enable.type.name
          user.features.steam.enable.type.name
          standalone.features.steam.enable.type.name
        ];
      }
    `,
    "--argstr", "flakeRef", flakeRef, "types",
  ])) as string[];
  [
    ["debug.options.configurations.nixos.type.name", "attrsOf"],
    ["debug.options.configurations.homeManager.type.name", "attrsOf"],
    ["configurations.nixos.neko7.module.local.features.ssh.enable.type.name", "nullOr"],
    ["local.users.tenzyu.features.steam.enable.type.name", "nullOr"],
    ["configurations.homeManager.<name>.module.local.features.steam.enable.type.name", "nullOr"],
  ].forEach(([name, expected], index) => checkEq(name, expected, types[index]));
}

export async function frameworkTestCommand(): Promise<void> {
  const { unitTestsCommand } = await import("./test-command");
  await unitTestsCommand();
  console.log("");
  await invariantsCommand();
  const { root, flakeRef } = await repository();
  const failures = await runOk([
    "nix",
    "eval",
    "--impure",
    "--json",
    "--file",
    `${root}/modules/_internal/configurations/tests/configurations.nix`,
    "--argstr",
    "flakeRef",
    flakeRef,
    "failures",
  ]);
  if (JSON.parse(failures).length) {
    throw new Error(`configuration adapter tests failed: ${failures}`);
  }
  console.log("OK   configuration adapter integration tests");
  console.log("\nframework-test: ok");
}
