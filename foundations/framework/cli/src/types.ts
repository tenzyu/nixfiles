declare global {
  const Bun: {
    argv: string[];
    env: Record<string, string | undefined>;
    spawn(args: string[], options?: Record<string, unknown>): {
      stdout: ReadableStream<Uint8Array> | null;
      stderr: ReadableStream<Uint8Array> | null;
      stdin?: { write(data: string): void; end(): void };
      exited: Promise<number>;
    };
    write(path: string, data: string): Promise<number>;
  };

  const process: {
    cwd(): string;
    exit(code?: number): never;
  };
}

export {};
