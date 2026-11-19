#!/usr/bin/env bash
# Evaluate the real DAG entries and run the two pre-write steps against a fixture HOME.
set -euo pipefail

fixture=$(mktemp -d /tmp/nixfiles-hm-preflight.XXXXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
export ADR02_FIXTURE_HOME="$fixture/home"
export ADR02_FIXTURE_USER
ADR02_FIXTURE_USER=$(id -un)
mkdir -m 700 "$ADR02_FIXTURE_HOME"

runner=$(nix build --no-link --print-out-paths --no-write-lock-file --impure --expr '
let
  flake = builtins.getFlake (toString ./.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  home = (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      flake.modules.homeManager.home-migration
      ({config, ...}: {
        home = {
          username = builtins.getEnv "ADR02_FIXTURE_USER";
          homeDirectory = builtins.getEnv "ADR02_FIXTURE_HOME";
          stateVersion = "26.05";
          file."managed.txt".text = "generation content";
        };
        local.homeMigration.paths = [{
          owner = "fixture";
          source = "${config.home.homeDirectory}/.legacy";
          target = "${config.home.homeDirectory}/.new";
        }];
      })
    ];
  }).config;
  activation = home.home.activation;
  ordered = (home.lib.dag.topoSort activation).result;
  steps = builtins.filter (step: builtins.elem step.name [
    "checkHomeMigration" "checkLinkTargets" "writeBoundary"
  ]) ordered;
in assert map (step: step.name) steps ==
  ["checkHomeMigration" "checkLinkTargets" "writeBoundary"];
pkgs.writeShellScript "fixture-home-preflight" ("\n  set -eu\n"
  + "export HOME=${pkgs.lib.escapeShellArg home.home.homeDirectory}\n"
  + "export PATH=${pkgs.lib.makeBinPath [pkgs.bash pkgs.coreutils pkgs.findutils pkgs.diffutils]}\n"
  + "newGenPath=${home.home.activationPackage}\n"
  + activation.checkHomeMigration.data
  + activation.checkLinkTargets.data
  + ": > \"$HOME/reached-write-boundary\"\n")
')

mkdir "$ADR02_FIXTURE_HOME/.legacy"
legacy="$ADR02_FIXTURE_HOME/.legacy/key"
sentinel="$ADR02_FIXTURE_HOME/reached-write-boundary"
printf legacy > "$legacy"
chmod 600 "$legacy"
before=$(stat -c '%i:%a:%s' "$legacy")
"$runner" > "$fixture/pending.log" 2>&1
grep -F '[fixture] move' "$fixture/pending.log"
test -f "$sentinel"
test "$(stat -c '%i:%a:%s' "$legacy")" = "$before"
test "$(cat "$legacy")" = legacy
test ! -e "$ADR02_FIXTURE_HOME/.new"
rm "$sentinel"

printf collision > "$ADR02_FIXTURE_HOME/managed.txt"
if "$runner" > "$fixture/collision.log" 2>&1; then
  echo 'Native Home Manager check accepted a conflicting file' >&2
  exit 1
fi
grep -F 'would be clobbered' "$fixture/collision.log"
test ! -e "$sentinel"
test "$(cat "$ADR02_FIXTURE_HOME/managed.txt")" = collision
test "$(stat -c '%i:%a:%s' "$legacy")" = "$before"
