import "./types";
import { frameworkTestCommand, invariantsCommand } from "./invariants";
import { unitTestsCommand } from "./test-command";
import { traceCommand } from "./trace";

function usage(): string {
  return `Usage: framework-cli <command> [args]\n\nCommands:\n  test          Run framework nix-unit tests and framework invariants\n  unit          Run framework nix-unit tests only\n  invariants    Run framework invariant checks only\n  trace         Trace feature activation/implementation/effects`;
}

async function main(): Promise<void> {
  const [command, ...args] = Bun.argv.slice(2);

  switch (command) {
    case "test":
      await frameworkTestCommand();
      break;
    case "unit":
      await unitTestsCommand();
      break;
    case "invariants":
      await invariantsCommand();
      break;
    case "trace":
      await traceCommand(args);
      break;
    case "-h":
    case "--help":
    case undefined:
      console.log(usage());
      break;
    default:
      throw new Error(`unknown command: ${command}\n${usage()}`);
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
