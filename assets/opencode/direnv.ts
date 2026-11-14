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

export async function loadEnvironment(
  cwd: string,
  environment: Environment,
  executable = "@direnv@",
): Promise<Environment> {
  const options = {
    cwd,
    env: environment,
    timeout: 120_000,
    maxBuffer: 8 * 1024 * 1024,
  }
  const status = await exec(executable, ["status", "--json"], options)
  const valueStatus: unknown = JSON.parse(status.stdout)
  if (typeof valueStatus !== "object" || valueStatus === null || !("state" in valueStatus)) {
    throw new Error("direnv status did not return state")
  }
  const state = valueStatus.state
  if (typeof state !== "object" || state === null || !("foundRC" in state)) {
    throw new Error("direnv status did not return foundRC")
  }
  const rc = state.foundRC
  if (rc !== null && (typeof rc !== "object" || !("allowed" in rc) || rc.allowed !== 0)) {
    throw new Error(`direnv environment is not approved in ${cwd}; inspect direnv status and direnv allow`)
  }
  const { stdout } = await exec(executable, ["export", "json"], options)
  if (!stdout.trim()) return {}
  const value: unknown = JSON.parse(stdout)
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("direnv export json did not return an environment object")
  }
  const changes: Environment = {}
  for (const [key, entry] of Object.entries(value)) {
    if (typeof entry !== "string" && entry !== null) {
      throw new Error(`direnv returned an invalid value for ${key}`)
    }
    changes[key] = entry === null ? undefined : entry
  }
  return changes
}

export default {
  id: "nixfiles.direnv",
  async setup(ctx: Context) {
    await ctx.shell.hook("create.before", async (event) => {
      const changes = await loadEnvironment(event.cwd, event.env)
      Object.assign(event.env, changes)
    })
  },
}
