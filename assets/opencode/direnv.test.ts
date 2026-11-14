import { afterEach, beforeEach, expect, test } from "bun:test"
import { execFile } from "node:child_process"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { promisify } from "node:util"
import { loadEnvironment } from "./direnv"

const exec = promisify(execFile)
const binary = process.env.DIRENV_BIN ?? "direnv"
let root: string
let environment: NodeJS.ProcessEnv

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "opencode-direnv-test-"))
  environment = { ...process.env, HOME: root, XDG_CONFIG_HOME: join(root, "config"), XDG_DATA_HOME: join(root, "data") }
  for (const key of Object.keys(environment)) {
    if (key.startsWith("DIRENV_")) delete environment[key]
  }
})

afterEach(async () => { await rm(root, { recursive: true, force: true }) })

async function project(name: string, content: string) {
  const directory = join(root, name)
  await mkdir(directory)
  await writeFile(join(directory, ".envrc"), content)
  await exec(binary, ["allow", directory], { env: environment })
  return directory
}

test("concurrent repositories get independent environments without changing the server", async () => {
  const a = await project("a", "export NIXFILES_ENV_PROBE=a\nunset NIXFILES_UNSET_PROBE\n")
  const b = await project("b", "export NIXFILES_ENV_PROBE=b\n")
  const base = { ...environment, NIXFILES_UNSET_PROBE: "remove-me" }
  const [first, second] = await Promise.all([loadEnvironment(a, base, binary), loadEnvironment(b, base, binary)])
  expect(first.NIXFILES_ENV_PROBE).toBe("a")
  expect(second.NIXFILES_ENV_PROBE).toBe("b")
  expect(Object.hasOwn(first, "NIXFILES_UNSET_PROBE")).toBe(true)
  expect(first.NIXFILES_UNSET_PROBE).toBeUndefined()
  expect(base.NIXFILES_UNSET_PROBE).toBe("remove-me")
  expect(process.env.NIXFILES_ENV_PROBE).toBeUndefined()
  const outside = await loadEnvironment(root, environment, binary)
  expect(outside.NIXFILES_ENV_PROBE).toBeUndefined()
})

test("subdirectories use the parent envrc and approved edits take effect", async () => {
  const a = await project("a", "export NIXFILES_ENV_PROBE=before\n")
  const nested = join(a, "nested")
  await mkdir(nested)
  expect((await loadEnvironment(nested, environment, binary)).NIXFILES_ENV_PROBE).toBe("before")
  await writeFile(join(a, ".envrc"), "export NIXFILES_ENV_PROBE=after\n")
  await expect(loadEnvironment(nested, environment, binary)).rejects.toThrow()
  await exec(binary, ["allow", a], { env: environment })
  expect((await loadEnvironment(nested, environment, binary)).NIXFILES_ENV_PROBE).toBe("after")
})

test("unapproved or broken envrc cannot silently run with the wrong environment", async () => {
  const a = await project("a", "export NIXFILES_ENV_PROBE=ok\n")
  await exec(binary, ["deny", a], { env: environment })
  await expect(loadEnvironment(a, environment, binary)).rejects.toThrow()
  await writeFile(join(a, ".envrc"), "exit 42\n")
  await exec(binary, ["allow", a], { env: environment })
  await expect(loadEnvironment(a, environment, binary)).rejects.toThrow()
})
