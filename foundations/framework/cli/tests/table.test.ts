import { expect, test } from "bun:test";
import { clip, table } from "../src/table";

test("clip keeps short values", () => {
  expect(clip("alpha", 10)).toBe("alpha");
});

test("clip truncates long values", () => {
  expect(clip("abcdefghij", 6)).toBe("abc...");
});

test("table renders stable columns", () => {
  expect(table([{ title: "A", width: 4 }, { title: "B", width: 3 }], [["aa", "bb"]])).toBe("A     B\naa    bb");
});
