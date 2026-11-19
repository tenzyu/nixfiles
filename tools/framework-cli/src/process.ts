type Argv = readonly [string, ...string[]];

export class ProcessFailure extends Error {
  constructor(operation: string, readonly status: number | string) {
    super(`${operation} failed (${typeof status === "number" ? `exit ${status}` : status})`);
  }
}

function processFailure(operation: string, error: unknown): ProcessFailure {
  // Native errors can contain argv, paths and captured output. Keep only the code.
  const code = error instanceof Error && "code" in error ? error.code : undefined;
  return new ProcessFailure(operation, typeof code === "string" && /^[A-Z][A-Z0-9_]*$/.test(code)
    ? code
    : "process I/O error");
}

export function spawnArgv(
  operation: string,
  argv: Argv,
  options: Parameters<typeof Bun.spawn>[1],
): ReturnType<typeof Bun.spawn> {
  if (!argv[0] || Array.from(argv).some((arg) => typeof arg !== "string" || arg.includes("\0"))) {
    throw new ProcessFailure(operation, "invalid argv");
  }
  try {
    return Bun.spawn([...argv], options);
  } catch (error) {
    throw processFailure(operation, error);
  }
}

async function streamText(stream: ReadableStream<Uint8Array> | null): Promise<string> {
  if (stream == null) return "";
  return await new Response(stream).text();
}

async function capture(operation: string, argv: Argv, env?: typeof Bun.env) {
  const proc = spawnArgv(operation, argv, {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
    env,
  });

  try {
    const [stdout, stderr, code] = await Promise.all([
      streamText(proc.stdout),
      streamText(proc.stderr),
      proc.exited,
    ]);
    return { code, stdout, stderr };
  } catch (error) {
    throw processFailure(operation, error);
  }
}

export async function runOk(operation: string, argv: Argv): Promise<string> {
  const result = await capture(operation, argv);
  if (result.code !== 0) throw new ProcessFailure(operation, result.code);
  return result.stdout;
}

export async function repository(): Promise<{ root: string; flakeRef: string }> {
  const operation = "git repository lookup";
  const git = await capture(operation, ["git", "rev-parse", "--show-toplevel"], { ...Bun.env, LC_ALL: "C" });
  if (git.code !== 0 && !(git.code === 128 && git.stderr.startsWith("fatal: not a git repository ("))) {
    throw new ProcessFailure(operation, git.code);
  }
  const root = git.code === 0 ? git.stdout.replace(/\n$/, "") : process.cwd();
  const encoded = root.split("/").map(encodeURIComponent).join("/");
  const flakeRef = git.code === 0 ? `git+file://${encoded}` : `path:${encoded}`;
  return { root, flakeRef };
}
