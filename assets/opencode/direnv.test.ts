import { afterEach, beforeEach, expect, test } from "bun:test"
import { execFile } from "node:child_process"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { promisify } from "node:util"
import plugin, { loadEnvironment } from "./direnv"

const exec = promisify(execFile)
const binary = "direnv"
let root: string
let environment: NodeJS.ProcessEnv

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "opencode-direnv-test-"))
  environment = { PATH: process.env.PATH, HOME: root, XDG_CONFIG_HOME: join(root, "config"), XDG_DATA_HOME: join(root, "data") }
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

test("packaged hook uses the substituted binary and changes only the event environment", async () => {
  const cwd = await project("path with spaces", "export NIXFILES_ENV_PROBE=packaged:$NIXFILES_EVENT_PROBE\nunset NIXFILES_EVENT_PROBE\n")
  const env = { ...environment, NIXFILES_EVENT_PROBE: "event", PATH: root }
  await plugin.setup({ shell: { async hook(name, handler) {
    expect(name).toBe("create.before")
    await handler({ cwd, env })
  } } })
  expect(env).toMatchObject({ NIXFILES_ENV_PROBE: "packaged:event", NIXFILES_EVENT_PROBE: undefined })
  expect(process.env.NIXFILES_ENV_PROBE).toBeUndefined()
})

async function fixture(status: string, exportScript: string) {
  const executable = join(root, "direnv fixture")
  await writeFile(executable, `#!${process.execPath}
    const args = process.argv.slice(2)
    if (args.join(" ") === "status --json") {
      process.stdout.write(${JSON.stringify(status)})
    } else if (args.join(" ") === "export json") {
      await Bun.write(${JSON.stringify(join(root, "exported"))}, "yes")
      ${exportScript}
    } else process.exit(99)
  `, { mode: 0o700 })
  return executable
}

test.each([
  "fixture invalid JSON",
  '{"state":[]}',
  '{"state":{}}',
  '{"state":{"foundRC":{"allowed":"0"}}}',
  '{"state":{"foundRC":{"allowed":2}}}',
])("refuses malformed or unapproved status before export: %s", async (status) => {
  const executable = await fixture(status, 'console.log("{}")')
  await expect(loadEnvironment(root, environment, executable)).rejects.toThrow(/^direnv (status|environment)/)
  expect(await Bun.file(join(root, "exported")).exists()).toBe(false)
})

const approved = '{"state":{"foundRC":{"allowed":0}}}'

test.each([
  "fixture invalid JSON",
  "[]",
  '{"FIRST":"valid","fixture-key":123}',
  '{"bad=name":"fixture-value"}',
  '{"KEY":"\\u0000"}',
])("rejects invalid export without echoing any entries: %s", async (output) => {
  const executable = await fixture(approved, `console.log(${JSON.stringify(output)})`)
  await expect(loadEnvironment(root, environment, executable)).rejects.toThrow(
    /^direnv export (returned invalid JSON|json did not return an environment object|returned an invalid environment entry)$/,
  )
})

test("unset and prototype-shaped keys remain own data entries", async () => {
  const executable = await fixture(approved, `console.log('{"__proto__":null,"KEEP":"value"}')`)
  const changes = await loadEnvironment(root, environment, executable)
  expect(Object.hasOwn(changes, "__proto__")).toBe(true)
  expect(Object.getPrototypeOf(changes)).toBe(Object.prototype)
  expect(changes.__proto__).toBeUndefined()
  expect(changes.KEEP).toBe("value")
})

test("keeps subprocess failure codes without including output or executable paths", async () => {
  const executable = await fixture(approved, `
    console.log('fixture stdout'); console.error('fixture stderr'); process.exit(42)
  `)
  await expect(loadEnvironment(root, environment, executable)).rejects.toMatchObject({
    code: 42, message: "direnv export failed (exit 42)",
  })
  await expect(loadEnvironment(root, environment, join(root, "absent executable"))).rejects.toMatchObject({
    code: "ENOENT", message: "direnv status failed (ENOENT)",
  })
})

test("does not accept export output above the 8 MiB buffer", async () => {
  const executable = await fixture(approved, `console.log(' '.repeat(8 * 1024 * 1024) + '{}')`)
  await expect(loadEnvironment(root, environment, executable)).rejects.toMatchObject({ code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER" })
})
