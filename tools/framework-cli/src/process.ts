export type RunResult = {
  code: number;
  stdout: string;
  stderr: string;
};

async function streamText(stream: ReadableStream<Uint8Array> | null): Promise<string> {
  if (stream == null) return "";
  return await new Response(stream).text();
}

export async function run(args: string[]): Promise<RunResult> {
  const proc = Bun.spawn(args, {
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stdout, stderr, code] = await Promise.all([
    streamText(proc.stdout),
    streamText(proc.stderr),
    proc.exited,
  ]);

  return { code, stdout, stderr };
}

export async function runOk(args: string[]): Promise<string> {
  const result = await run(args);
  if (result.code !== 0) {
    const command = args.map((arg) => JSON.stringify(arg)).join(" ");
    throw new Error(`command failed (${result.code}): ${command}\n${result.stderr || result.stdout}`);
  }
  return result.stdout;
}

export async function repository(): Promise<{ root: string; flakeRef: string }> {
  const git = await run(["git", "rev-parse", "--show-toplevel"]).catch(() => null);
  const root = git?.code === 0 ? git.stdout.trimEnd() : process.cwd();
  const encoded = root.split("/").map(encodeURIComponent).join("/");
  const flakeRef = git?.code === 0 ? `git+file://${encoded}` : `path:${encoded}`;
  return { root, flakeRef };
}
