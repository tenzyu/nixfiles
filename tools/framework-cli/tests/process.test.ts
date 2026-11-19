import { expect, test } from "bun:test";
import { runOk } from "../src/process";

test("passes arguments verbatim, including the empty string and shell syntax", async () => {
  const values = ["", " spaced path ", "$(echo not-a-command); *", "'\"\n"];
  const stdout = await runOk("fixture", [process.execPath, "-e", "console.log(JSON.stringify(process.argv.slice(1)))", "--", ...values]);
  expect(JSON.parse(stdout)).toEqual(values);
});

test("keeps the exit status without exposing argv, stdout or stderr", async () => {
  await expect(runOk("fixture", [process.execPath, "-e", `
    console.log('fixture stdout'); console.error('fixture stderr'); process.exit(42);
  `, "fixture argv"])).rejects.toMatchObject({ status: 42, message: "fixture failed (exit 42)" });
});

test("keeps the errno without exposing the executable path", async () => {
  await expect(runOk("fixture", [`${process.execPath}/not-an-executable`]))
    .rejects.toMatchObject({ status: "ENOTDIR", message: "fixture failed (ENOTDIR)" });
});

test("does not report a signal as success", async () => {
  await expect(runOk("fixture", [process.execPath, "-e", "process.kill(process.pid, 'SIGTERM')"]))
    .rejects.toMatchObject({ status: 143, message: "fixture failed (exit 143)" });
});

test("rejects a NUL argument rather than passing a truncated vector", async () => {
  await expect(runOk("fixture", [process.execPath, "-e", "process.exit(0)\0ignored"]))
    .rejects.toThrow(/^fixture failed \(invalid argv\)$/);
});
