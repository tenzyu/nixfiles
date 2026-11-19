import { execFile } from "node:child_process"
import { promisify } from "node:util"

const exec = promisify(execFile)
type Environment = Record<string, string | undefined>
type ShellEvent = { cwd: string; env: Environment }
type Context = {
  shell: {
    hook(name: "create.before", handler: (event: ShellEvent) => Promise<void>): Promise<unknown>
  }
}

function parseJSON(output: string, operation: string): unknown {
  try {
    return JSON.parse(output)
  } catch {
    throw new Error(`direnv ${operation} returned invalid JSON`)
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function requireApproval(output: string): void {
  const value = parseJSON(output, "status")
  if (!isObject(value) || !isObject(value.state) || !Object.hasOwn(value.state, "foundRC")) {
    throw new Error("direnv status did not return state.foundRC")
  }
  const rc = value.state.foundRC
  if (rc !== null && (!isObject(rc) || !Object.hasOwn(rc, "allowed") || rc.allowed !== 0)) {
    throw new Error("direnv environment is not approved; inspect direnv status and direnv allow")
  }
}

function parseExport(output: string): Environment {
  if (!output.trim()) return {}
  const value = parseJSON(output, "export")
  if (!isObject(value)) throw new Error("direnv export json did not return an environment object")

  const changes: [string, string | undefined][] = []
  for (const [key, entry] of Object.entries(value)) {
    if (!key || /[=\0]/.test(key) || (entry !== null && (typeof entry !== "string" || entry.includes("\0")))) {
      throw new Error("direnv export returned an invalid environment entry")
    }
    changes.push([key, entry === null ? undefined : entry])
  }
  return Object.fromEntries(changes)
}

class DirenvFailure extends Error {
  constructor(operation: string, readonly code: number | string | undefined, readonly signal: string | undefined) {
    const reason = signal ?? (typeof code === "number" ? `exit ${code}` : code ?? "process I/O error")
    super(`direnv ${operation} failed (${reason})`)
  }
}

export async function loadEnvironment(
  cwd: string,
  environment: Environment,
  executable = "@direnv@",
): Promise<Environment> {
  const options = {
    cwd,
    env: environment,
    shell: false,
    timeout: 120_000,
    maxBuffer: 8 * 1024 * 1024,
  }
  async function run(operation: "status" | "export"): Promise<string> {
    try {
      return (await exec(executable, [operation, operation === "status" ? "--json" : "json"], options)).stdout
    } catch (error) {
      // execFile errors retain argv, stdout and stderr. Do not attach the raw cause.
      const code = error instanceof Error && "code" in error ? error.code : undefined
      const signal = error instanceof Error && "signal" in error ? error.signal : undefined
      throw new DirenvFailure(operation,
        typeof code === "number" || (typeof code === "string" && /^[A-Z][A-Z0-9_]*$/.test(code)) ? code : undefined,
        typeof signal === "string" && /^SIG[A-Z0-9]+$/.test(signal) ? signal : undefined,
      )
    }
  }

  requireApproval(await run("status"))
  return parseExport(await run("export"))
}

export default {
  id: "nixfiles.direnv",
  async setup(ctx: Context) {
    await ctx.shell.hook("create.before", async (event) => {
      const changes = await loadEnvironment(event.cwd, event.env)
      for (const [name, value] of Object.entries(changes)) {
        // A JSON key is data, even when it names Object.prototype's setter.
        if (name === "__proto__") {
          Object.defineProperty(event.env, name, { value, writable: true, enumerable: true, configurable: true })
        } else {
          event.env[name] = value
        }
      }
    })
  },
}
