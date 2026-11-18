import { row, table } from "./table";
import { sourceLabel } from "./trace-render";
import type { EditTarget, Location, TraceResult } from "./trace";

type Target = "activation" | "implementation" | "effect" | "source";

type Candidate = Location & {
  target: Target;
  scope: string;
  feature: string;
  kind: string;
  option: string;
};

const targetRank = { activation: 0, implementation: 1, effect: 2, source: 3 };
const columns = [
  { title: "#", width: 5 },
  { title: "TARGET", width: 14 },
  { title: "SCOPE", width: 14 },
  { title: "FEATURE", width: 31 },
  { title: "KIND", width: 16 },
  { title: "OPTION/MODULE", width: 58 },
  { title: "SOURCE", width: 80 },
];

function candidatesFor(result: TraceResult, editTarget: EditTarget): Candidate[] {
  if (result.type === "why") {
    return editTarget ? [] : result.definitions.map((definition) => ({
      ...definition,
      target: "source",
      scope: "",
      feature: "",
      option: result.path,
    }));
  }

  const candidates = [...result.system, ...result.home].flatMap((feature) => {
    const scope = feature.user == null ? feature.scope : `home/${feature.user}`;
    const groups = {
      activation: feature.activations,
      implementation: feature.implementations,
      effect: feature.effects,
      source: feature.source_hints.filter((hint) => !feature.activations.some((activation) =>
        activation.source === hint.source && activation.line === hint.line
      )),
    };

    return (Object.keys(groups) as Target[]).flatMap((target) =>
      groups[target].map((location): Candidate => ({
        target,
        scope,
        feature: feature.name,
        kind: location.origin === "text-scan" ? "source hint" : location.kind,
        option: location.option ?? location.optionPrefix ?? "",
        source: location.source,
        line: location.line,
      })),
    );
  });

  const seen = new Set<string>();
  return candidates.filter((candidate) => {
    if (editTarget && candidate.target !== editTarget) return false;
    const key = JSON.stringify(candidate);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((a, b) =>
    targetRank[a.target] - targetRank[b.target] ||
    a.scope.localeCompare(b.scope) ||
    a.feature.localeCompare(b.feature) ||
    a.kind.localeCompare(b.kind) ||
    sourceLabel(a).localeCompare(sourceLabel(b)),
  );
}

async function pickCandidate(candidates: Candidate[]): Promise<Candidate> {
  const rows = candidates.map((candidate, index) => [
    index + 1,
    candidate.target,
    candidate.scope,
    candidate.feature,
    candidate.kind,
    candidate.option,
    sourceLabel(candidate),
  ]);
  const fzf = Bun.spawn([
    "fzf", `--header=${table(columns, [])}`, "--prompt=feature-trace> ",
    "--layout=reverse", "--height=90%", "--border", "--info=inline",
  ], { stdin: "pipe", stdout: "pipe", stderr: "inherit" });
  if (!fzf.stdin) throw new Error("feature-trace: failed to open fzf stdin");

  fzf.stdin.write(rows.map((values) => row(columns, values)).join("\n") + "\n");
  fzf.stdin.end();
  const selected = (await new Response(fzf.stdout).text()).trim();
  if (await fzf.exited !== 0 || selected === "") {
    throw new Error("feature-trace: edit cancelled");
  }

  const index = Number(selected.split(/\s+/, 1)[0]);
  if (!Number.isInteger(index) || index < 1 || index > candidates.length) {
    throw new Error(`feature-trace: invalid fzf selection: ${selected}`);
  }
  return candidates[index - 1];
}

export async function editTrace(result: TraceResult, repo: string, target: EditTarget): Promise<void> {
  const candidates = candidatesFor(result, target);
  if (candidates.length === 0) throw new Error("feature-trace: no source file to edit");
  const { source, line } = candidates.length === 1 ? candidates[0] : await pickCandidate(candidates);
  const file = source.startsWith("/") ? source : `${repo}/${source}`;

  const editor = Bun.spawn(["sh", "-lc", 'exec $EDITOR_CMD "+$LINE" "$FILE"'], {
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
    env: {
      ...Bun.env,
      EDITOR_CMD: Bun.env.VISUAL ?? Bun.env.EDITOR ?? "vi",
      FILE: file,
      LINE: String(line ?? 1),
    },
  });
  const status = await editor.exited;
  if (status !== 0) throw new Error(`feature-trace: editor exited with status ${status}`);
}
