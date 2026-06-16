export type RunResult = {
  code: number;
  stdout: string;
  stderr: string;
};

async function streamText(stream: ReadableStream<Uint8Array> | null): Promise<string> {
  if (stream == null) return "";
  return await new Response(stream).text();
}

export async function run(args: string[], options: Record<string, unknown> = {}): Promise<RunResult> {
  const proc = Bun.spawn(args, {
    stdout: "pipe",
    stderr: "pipe",
    ...options,
  });

  const [stdout, stderr, code] = await Promise.all([
    streamText(proc.stdout),
    streamText(proc.stderr),
    proc.exited,
  ]);

  return { code, stdout, stderr };
}

export async function runOk(args: string[], options: Record<string, unknown> = {}): Promise<string> {
  const result = await run(args, options);
  if (result.code !== 0) {
    const command = args.map((arg) => JSON.stringify(arg)).join(" ");
    throw new Error(`command failed (${result.code}): ${command}\n${result.stderr || result.stdout}`);
  }
  return result.stdout;
}
