import { repository, runOk } from "./process";
import { editTrace } from "./trace-edit";
import { renderTrace } from "./trace-render";

type Scope = "system" | "home" | "all";
export type EditTarget = "" | "activation" | "implementation";

type TraceArgs = {
  host: string;
  user: string;
  scope: Scope;
  feature: string;
  why: string;
  json: boolean;
  edit: boolean;
  editTarget: EditTarget;
};

export type Location = {
  source: string;
  line: number | null;
};

type TraceSource = Location & {
  kind: string;
  origin: string;
  option?: string;
  optionPrefix?: string;
};

type Definition = TraceSource & {
  renderedValue: string;
  value: unknown;
  winning_priority: number | null;
};

export type Feature = {
  name: string;
  scope: Exclude<Scope, "all">;
  user: string | null;
  status: "enabled" | "disabled";
  kind: string;
  winning_priority: number | null;
  activations: TraceSource[];
  source_hints: TraceSource[];
  implementations: TraceSource[];
  effects: Definition[];
};

export type TraceResult =
  | { type: "host"; host: string; system: Feature[]; home: Feature[] }
  | { type: "why"; path: string; effective: string; definitions: Definition[]; winning_priority: number | null };

export async function traceCommand(argv: string[]): Promise<void> {
  const parsed = parseTraceArgs(argv);
  if (parsed.kind === "help") {
    console.log(usage());
    return;
  }
  const { args } = parsed;

  const { root, flakeRef } = await repository();
  const result = await evalTrace(args, root, flakeRef);
  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  console.log(renderTrace(result));
  if (args.edit) await editTrace(result, root, args.editTarget);
}

export function parseTraceArgs(argv: readonly string[]): { kind: "help" } | { kind: "trace"; args: TraceArgs } {
  const args: TraceArgs = {
    host: "",
    user: "",
    scope: "all",
    feature: "",
    why: "",
    json: false,
    edit: false,
    editTarget: "",
  };

  let i = 0;

  const readValue = (flag: string): string => {
    const value = argv[i + 1];
    if (!value || value === "-h" || value.startsWith("--") || value.includes("\0")) {
      throw new Error(`feature-trace: ${flag} requires a value`);
    }
    i += 1;
    return value;
  };

  while (i < argv.length) {
    const arg = argv[i];

    switch (arg) {
      case "--help":
      case "-h":
        return { kind: "help" };

      case "--host":
        args.host = readValue(arg);
        break;

      case "--user":
        args.user = readValue(arg);
        break;

      case "--scope": {
        const value = readValue(arg);
        if (value !== "system" && value !== "home" && value !== "all") {
          throw new Error(
            "feature-trace: --scope must be one of system, home, all",
          );
        }
        args.scope = value;
        break;
      }

      case "--feature":
        args.feature = readValue(arg);
        break;

      case "--why":
        args.why = readValue(arg);
        break;

      case "--json":
        args.json = true;
        break;

      case "--edit":
        args.edit = true;
        break;

      case "--edit-activation":
        args.edit = true;
        args.editTarget = "activation";
        break;

      case "--edit-implementation":
        args.edit = true;
        args.editTarget = "implementation";
        break;

      default:
        throw new Error("feature-trace: unknown argument");
    }

    i += 1;
  }

  if (args.host === "") throw new Error("feature-trace: --host is required");
  if (args.why && args.user) {
    throw new Error("feature-trace: --why takes a NixOS option path. Use --user with a feature trace.");
  }
  return { kind: "trace", args };
}

function usage(): string {
  return [
    "Usage:",
    "  feature-trace --host HOST [--scope system|home|all] [--user USER] [--feature FEATURE]",
    "  feature-trace --host HOST --why OPTION_PATH",
    "  feature-trace --host HOST --edit [--feature FEATURE] [--edit-activation|--edit-implementation]",
    "",
    "Examples:",
    "  feature-trace --host neko5",
    "  feature-trace --host neko5 --feature zsh",
    "  feature-trace --host neko5 --edit",
    "  feature-trace --host neko5 --edit --feature zsh --edit-implementation",
  ].join("\n");
}

async function evalTrace(args: TraceArgs, repo: string, flakeRef: string): Promise<TraceResult> {
  const traceModulePath = Bun.env.FEATURE_TRACE_LIB;
  if (!traceModulePath) throw new Error("FEATURE_TRACE_LIB is not set");

  const stdout = await runOk("feature-trace Nix evaluation", [
    "nix", "eval", "--json", "--impure",
    "--expr", `
      { repo, flakeRef, traceModulePath, argsJSON }:
      let
        flake = builtins.getFlake flakeRef;
        core = import (builtins.toPath traceModulePath) {
          lib = flake.inputs.nixpkgs.lib;
        };
        args = builtins.fromJSON argsJSON;
        base = { inherit repo flake; inherit (args) host; };
      in {
        trace = if args.why != "" then
          core.traceWhy (base // { option = args.why; })
        else
          core.traceHost (base // {
            inherit (args) scope;
            user = if args.user != "" then args.user else null;
            feature = if args.feature != "" then args.feature else null;
          });
      }
    `,
    "--argstr", "repo", repo,
    "--argstr", "flakeRef", flakeRef,
    "--argstr", "traceModulePath", traceModulePath,
    "--argstr", "argsJSON", JSON.stringify(args),
    "trace",
  ]);
  try {
    return JSON.parse(stdout) as TraceResult;
  } catch {
    throw new Error("feature-trace: Nix returned invalid JSON");
  }
}
