type AnyRecord = Record<string, unknown>;

type Scope = "system" | "home" | "all";
type EditTarget = "" | "activation" | "implementation";

type TraceArgs = {
  host: string;
  user: string;
  scope: Scope;
  feature: string;
  why: string;
  json: boolean;
  edit: boolean;
  editTarget: EditTarget;
};

type Candidate = {
  target: "activation" | "implementation" | "effect" | "source";
  scope: string;
  feature: string;
  kind: string;
  option: string;
  source: string;
  line?: number;
};

type CandidateLocation = {
  source: string;
  line: number;
};

const candidateColumns = [
  { title: "#", width: 5 },
  { title: "TARGET", width: 14 },
  { title: "SCOPE", width: 14 },
  { title: "FEATURE", width: 31 },
  { title: "KIND", width: 16 },
  { title: "OPTION/MODULE", width: 58 },
  { title: "SOURCE", width: 80 },
] as const;

export async function traceCommand(argv: string[]): Promise<void> {
  const args = parseTraceArgs(argv);

  if (args.host === "") {
    throw new Error("feature-trace: --host is required");
  }

  const repo = await repoRoot();
  const result = await evalTrace(args, repo);

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  console.log(renderTrace(result, args));

  if (!args.edit) {
    return;
  }

  const candidates = collectCandidates(result, args);

  if (candidates.length === 0) {
    throw new Error("feature-trace: no source file to edit");
  }

  if (candidates.length === 1) {
    await editCandidate(repo, candidates[0]);
    return;
  }

  const candidate = await pickCandidateWithFzf(candidates);
  if (!candidate) {
    throw new Error("feature-trace: edit cancelled");
  }

  await editCandidate(repo, candidate);
}

function parseTraceArgs(argv: string[]): TraceArgs {
  const args: TraceArgs = {
    host: "",
    user: "",
    scope: "all",
    feature: "",
    why: "",
    json: false,
    edit: false,
    editTarget: "",
  };

  let i = 0;

  const readValue = (flag: string): string => {
    const value = argv[i + 1];
    if (value == null || value.startsWith("--")) {
      throw new Error(`feature-trace: ${flag} requires a value`);
    }
    i += 1;
    return value;
  };

  while (i < argv.length) {
    const arg = argv[i];

    switch (arg) {
      case "--help":
      case "-h":
        console.log(usage());
        process.exit(0);
        break;

      case "--host":
        args.host = readValue(arg);
        break;

      case "--user":
        args.user = readValue(arg);
        break;

      case "--scope": {
        const value = readValue(arg);
        if (value !== "system" && value !== "home" && value !== "all") {
          throw new Error(
            `feature-trace: --scope must be one of system, home, all (got: ${value})`,
          );
        }
        args.scope = value;
        break;
      }

      case "--feature":
        args.feature = readValue(arg);
        break;

      case "--why":
        args.why = readValue(arg);
        break;

      case "--json":
        args.json = true;
        break;

      case "--edit":
        args.edit = true;
        break;

      case "--edit-activation":
        args.edit = true;
        args.editTarget = "activation";
        break;

      case "--edit-implementation":
        args.edit = true;
        args.editTarget = "implementation";
        break;

      default:
        throw new Error(`feature-trace: unknown argument: ${arg}`);
    }

    i += 1;
  }

  return args;
}

function usage(): string {
  return [
    "Usage:",
    "  feature-trace --host HOST [--scope system|home|all] [--user USER] [--feature FEATURE]",
    "  feature-trace --host HOST --why OPTION_PATH",
    "  feature-trace --host HOST --edit [--feature FEATURE] [--edit-activation|--edit-implementation]",
    "",
    "Examples:",
    "  feature-trace --host neko5",
    "  feature-trace --host neko5 --feature zsh",
    "  feature-trace --host neko5 --edit",
    "  feature-trace --host neko5 --edit --feature zsh --edit-implementation",
  ].join("\n");
}

async function repoRoot(): Promise<string> {
  const git = Bun.spawn(["git", "rev-parse", "--show-toplevel"], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const stdout = (await new Response(git.stdout).text()).trim();
  const exitCode = await git.exited;

  if (exitCode === 0 && stdout !== "") {
    return stdout;
  }

  return process.cwd();
}

async function evalTrace(args: TraceArgs, repo: string): Promise<AnyRecord> {
  const frameworkRoot = Bun.env.FRAMEWORK_ROOT;
  if (!frameworkRoot) {
    throw new Error("FRAMEWORK_ROOT is not set");
  }

  const nixArgs = JSON.stringify(args);

  const expr = `
    let
      repo = ${JSON.stringify(repo)};
      flake = builtins.getFlake "path:${repo}";
      core = import (${JSON.stringify(frameworkRoot)} + "/modules/10-framework/tools/feature-trace.nix") {
        lib = flake.inputs.nixpkgs.lib;
      };
      args = builtins.fromJSON ${JSON.stringify(nixArgs)};
      base = { inherit repo flake; host = args.host; };
      withUser = if args.user != "" then base // { user = args.user; } else base;
      fullArgs = withUser // { scope = args.scope; };
    in
      if args.why != "" then
        core.traceWhy (base // { option = args.why; } // (if args.user != "" then { user = args.user; } else {}))
      else
        core.traceHost fullArgs
  `;

  const proc = Bun.spawn(
    ["nix", "eval", "--json", "--impure", "--expr", expr],
    {
      stdout: "pipe",
      stderr: "pipe",
    },
  );

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    throw new Error(stderr.trim() || `nix eval failed with status ${exitCode}`);
  }

  return JSON.parse(stdout) as AnyRecord;
}

function renderTrace(result: AnyRecord, args: TraceArgs): string {
  if (args.why !== "") {
    return renderWhy(result);
  }

  const lines: string[] = [];

  const systemRows = collectFeatureRows(result, "system");
  if (systemRows.length > 0) {
    lines.push(`SYSTEM FEATURES / ${args.host}`);
    lines.push(
      table(
        [
          { title: "FEATURE", width: 31 },
          { title: "STATUS", width: 9 },
          { title: "ACTIVATION", width: 15 },
          { title: "SOURCE", width: 80 },
        ],
        systemRows.map((row) => [
          row.feature,
          row.status,
          row.activation,
          row.source,
        ]),
      ),
    );
  }

  const homeGroups = collectHomeFeatureGroups(result);
  for (const group of homeGroups) {
    if (lines.length > 0) {
      lines.push("");
    }

    lines.push(`HOME FEATURES / ${group.user}@${args.host}`);
    lines.push(
      table(
        [
          { title: "FEATURE", width: 31 },
          { title: "STATUS", width: 9 },
          { title: "ACTIVATION", width: 15 },
          { title: "SOURCE", width: 80 },
        ],
        group.rows.map((row) => [
          row.feature,
          row.status,
          row.activation,
          row.source,
        ]),
      ),
    );
  }

  if (lines.length === 0) {
    return JSON.stringify(result, null, 2);
  }

  return lines.join("\n");
}

function renderWhy(result: AnyRecord): string {
  const definitions = arrayFromUnknown(result.definitions);

  if (definitions.length === 0) {
    return JSON.stringify(result, null, 2);
  }

  return table(
    [
      { title: "OPTION", width: 50 },
      { title: "FILE", width: 80 },
      { title: "VALUE", width: 60 },
    ],
    definitions.map((definition) => {
      const row = asRecord(definition);
      return [
        stringFromUnknown(row.option ?? row.name),
        stringFromUnknown(row.file ?? row.source),
        stableString(row.value),
      ];
    }),
  );
}

type FeatureRow = {
  feature: string;
  status: string;
  activation: string;
  source: string;
};

type HomeFeatureGroup = {
  user: string;
  rows: FeatureRow[];
};

function collectFeatureRows(
  result: AnyRecord,
  scope: "system" | "home",
): FeatureRow[] {
  const directKeys =
    scope === "system"
      ? ["systemFeatures", "system", "features"]
      : ["homeFeatures", "home"];

  for (const key of directKeys) {
    const value = result[key];
    const rows = featureRowsFromUnknown(value);
    if (rows.length > 0) {
      return rows;
    }
  }

  return [];
}

function collectHomeFeatureGroups(result: AnyRecord): HomeFeatureGroup[] {
  const value =
    result.homeFeatures ?? result.home ?? result.users ?? result.homeUsers;

  if (Array.isArray(value)) {
    const rows = featureRowsFromUnknown(value);
    if (rows.length > 0) {
      return [{ user: "unknown", rows }];
    }

    return value.flatMap((entry) => {
      const record = asRecord(entry);
      const user = stringFromUnknown(record.user ?? record.name);
      const nestedRows = featureRowsFromUnknown(
        record.features ?? record.rows ?? record.items,
      );

      return nestedRows.length > 0
        ? [{ user: user || "unknown", rows: nestedRows }]
        : [];
    });
  }

  const record = asRecord(value);
  const groups: HomeFeatureGroup[] = [];

  for (const [user, raw] of Object.entries(record)) {
    const rows = featureRowsFromUnknown(raw);
    if (rows.length > 0) {
      groups.push({ user, rows });
    }
  }

  return groups;
}

function featureRowsFromUnknown(value: unknown): FeatureRow[] {
  if (Array.isArray(value)) {
    return value.flatMap((entry) => {
      const record = asRecord(entry);
      const feature = stringFromUnknown(record.feature ?? record.name);

      if (feature === "") {
        return [];
      }

      return [
        {
          feature,
          status: stringFromUnknown(record.status ?? "enabled"),
          activation: stringFromUnknown(record.activation ?? record.kind ?? ""),
          source: sourceString(record),
        },
      ];
    });
  }

  const record = asRecord(value);

  return Object.entries(record).flatMap(([feature, raw]) => {
    const row = asRecord(raw);

    if (Object.keys(row).length === 0 && typeof raw !== "string") {
      return [];
    }

    return [
      {
        feature: stringFromUnknown(row.feature ?? feature),
        status: stringFromUnknown(row.status ?? "enabled"),
        activation: stringFromUnknown(row.activation ?? row.kind ?? ""),
        source: sourceString(row),
      },
    ];
  });
}

function collectCandidates(result: AnyRecord, args: TraceArgs): Candidate[] {
  const explicit = arrayFromUnknown(result.candidates ?? result.editCandidates);
  const explicitCandidates = explicit.flatMap(candidateFromUnknown);

  const candidates =
    explicitCandidates.length > 0
      ? explicitCandidates
      : collectCandidatesByWalking(result);

  const filtered = candidates.filter((candidate) => {
    if (args.feature !== "" && candidate.feature !== args.feature) {
      return false;
    }

    if (args.editTarget !== "" && candidate.target !== args.editTarget) {
      return false;
    }

    if (args.scope === "system" && !candidate.scope.startsWith("system")) {
      return false;
    }

    if (args.scope === "home" && !candidate.scope.startsWith("home")) {
      return false;
    }

    if (
      args.user !== "" &&
      candidate.scope.startsWith("home/") &&
      candidate.scope !== `home/${args.user}`
    ) {
      return false;
    }

    return candidate.source !== "";
  });

  return dedupeCandidates(filtered).sort(compareCandidates);
}

function candidateFromUnknown(value: unknown): Candidate[] {
  const record = asRecord(value);
  const source = sourceString(record);

  if (source === "") {
    return [];
  }

  return [
    {
      target: candidateTarget(record),
      scope: stringFromUnknown(record.scope),
      feature: stringFromUnknown(record.feature ?? record.name),
      kind: stringFromUnknown(
        record.kind ?? record.activation ?? record.moduleClass,
      ),
      option: stringFromUnknown(
        record.option ?? record.optionPath ?? record.module ?? record.path,
      ),
      source,
      line: numberFromUnknown(record.line),
    },
  ];
}

function collectCandidatesByWalking(root: unknown): Candidate[] {
  const candidates: Candidate[] = [];

  const walk = (
    value: unknown,
    path: string[],
    context: Partial<Candidate>,
  ): void => {
    if (Array.isArray(value)) {
      for (const item of value) {
        walk(item, path, context);
      }
      return;
    }

    const record = asRecord(value);
    if (Object.keys(record).length === 0) {
      return;
    }

    const nextContext: Partial<Candidate> = {
      ...context,
      target: context.target ?? targetFromPath(path),
      scope:
        stringFromUnknown(record.scope) || context.scope || scopeFromPath(path),
      feature:
        stringFromUnknown(record.feature ?? record.name) ||
        context.feature ||
        featureFromPath(path),
      kind:
        stringFromUnknown(
          record.kind ?? record.activation ?? record.moduleClass,
        ) ||
        context.kind ||
        kindFromPath(path),
      option:
        stringFromUnknown(
          record.option ?? record.optionPath ?? record.module ?? record.path,
        ) ||
        context.option ||
        "",
    };

    const source = sourceString(record);
    if (source !== "") {
      candidates.push({
        target: nextContext.target ?? "source",
        scope: nextContext.scope ?? "",
        feature: nextContext.feature ?? "",
        kind: nextContext.kind ?? "",
        option: nextContext.option ?? "",
        source,
        line: numberFromUnknown(record.line),
      });
    }

    for (const [key, child] of Object.entries(record)) {
      if (
        key === "source" ||
        key === "file" ||
        key === "location" ||
        key === "line"
      ) {
        continue;
      }

      walk(child, [...path, key], nextContext);
    }
  };

  walk(root, [], {});

  return candidates;
}

function candidateTarget(record: AnyRecord): Candidate["target"] {
  const value = stringFromUnknown(record.target);
  if (
    value === "activation" ||
    value === "implementation" ||
    value === "effect" ||
    value === "source"
  ) {
    return value;
  }

  return "source";
}

function targetFromPath(path: string[]): Candidate["target"] {
  const joined = path.join(".");

  if (joined.includes("activation")) {
    return "activation";
  }

  if (joined.includes("implementation")) {
    return "implementation";
  }

  if (joined.includes("effect")) {
    return "effect";
  }

  return "source";
}

function scopeFromPath(path: string[]): string {
  if (path.includes("system") || path.includes("systemFeatures")) {
    return "system";
  }

  const homeIndex = path.findIndex(
    (part) =>
      part === "home" ||
      part === "homeFeatures" ||
      part === "homeUsers" ||
      part === "users",
  );

  if (homeIndex >= 0) {
    const maybeUser = path[homeIndex + 1];

    if (maybeUser && !["features", "rows", "items"].includes(maybeUser)) {
      return `home/${maybeUser}`;
    }

    return "home";
  }

  return "";
}

function featureFromPath(path: string[]): string {
  const ignored = new Set([
    "system",
    "systemFeatures",
    "home",
    "homeFeatures",
    "homeUsers",
    "users",
    "features",
    "activations",
    "activation",
    "implementations",
    "implementation",
    "effects",
    "effect",
    "rows",
    "items",
  ]);

  for (let i = path.length - 1; i >= 0; i -= 1) {
    const part = path[i];
    if (part && !ignored.has(part) && !/^[0-9]+$/.test(part)) {
      return part;
    }
  }

  return "";
}

function kindFromPath(path: string[]): string {
  if (path.includes("homeManager")) {
    return "homeManager";
  }

  if (path.includes("nixos")) {
    return "nixos";
  }

  if (path.includes("activation")) {
    return "activation";
  }

  if (path.includes("implementation")) {
    return "implementation";
  }

  return "";
}

function dedupeCandidates(candidates: Candidate[]): Candidate[] {
  const seen = new Set<string>();
  const output: Candidate[] = [];

  for (const candidate of candidates) {
    const location = candidateLocation(candidate);
    const key = [
      candidate.target,
      candidate.scope,
      candidate.feature,
      candidate.kind,
      candidate.option,
      location.source,
      location.line,
    ].join("\u0000");

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    output.push(candidate);
  }

  return output;
}

function compareCandidates(a: Candidate, b: Candidate): number {
  return (
    targetRank(a.target) - targetRank(b.target) ||
    a.scope.localeCompare(b.scope) ||
    a.feature.localeCompare(b.feature) ||
    a.kind.localeCompare(b.kind) ||
    sourceLabel(a).localeCompare(sourceLabel(b))
  );
}

function targetRank(target: Candidate["target"]): number {
  switch (target) {
    case "activation":
      return 0;
    case "implementation":
      return 1;
    case "effect":
      return 2;
    case "source":
      return 3;
  }
}

async function pickCandidateWithFzf(
  candidates: Candidate[],
): Promise<Candidate | null> {
  const rows =
    candidates
      .map((candidate, index) => candidateDisplayLine(candidate, index))
      .join("\n") + "\n";

  const fzf = Bun.spawn(
    [
      "fzf",
      `--header=${candidateDisplayHeader()}`,
      "--prompt=feature-trace> ",
      "--layout=reverse",
      "--height=90%",
      "--border",
      "--info=inline",
    ],
    {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "inherit",
    },
  );

  if (!fzf.stdin) {
    throw new Error("feature-trace: failed to open fzf stdin");
  }

  fzf.stdin.write(rows);
  fzf.stdin.end();

  const selected = (await new Response(fzf.stdout).text()).trimEnd();
  const exitCode = await fzf.exited;

  if (exitCode !== 0 || selected === "") {
    return null;
  }

  const rawIndex = selected.trimStart().split(/\s+/, 1)[0];
  const index = Number(rawIndex);

  if (!Number.isInteger(index) || index < 1 || index > candidates.length) {
    throw new Error(`feature-trace: invalid fzf selection: ${selected}`);
  }

  return candidates[index - 1] ?? null;
}

function candidateDisplayHeader(): string {
  return candidateColumns
    .map((column) => padRight(column.title, column.width))
    .join("  ")
    .trimEnd();
}

function candidateDisplayLine(candidate: Candidate, index: number): string {
  return [
    String(index + 1),
    candidate.target,
    candidate.scope,
    candidate.feature,
    candidate.kind,
    candidate.option,
    sourceLabel(candidate),
  ]
    .map((value, columnIndex) =>
      padRight(
        truncate(value, candidateColumns[columnIndex]?.width ?? 20),
        candidateColumns[columnIndex]?.width ?? 20,
      ),
    )
    .join("  ")
    .trimEnd();
}

async function editCandidate(
  repo: string,
  candidate: Candidate,
): Promise<void> {
  const location = candidateLocation(candidate);
  const file = location.source.startsWith("/")
    ? location.source
    : `${repo}/${location.source}`;

  const editor = Bun.env.VISUAL ?? Bun.env.EDITOR ?? "vi";

  const editorProcess = Bun.spawn(
    ["sh", "-lc", 'exec $EDITOR_CMD "+$LINE" "$FILE"'],
    {
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
      env: {
        ...Bun.env,
        EDITOR_CMD: editor,
        FILE: file,
        LINE: String(location.line),
      },
    },
  );

  const exitCode = await editorProcess.exited;
  if (exitCode !== 0) {
    throw new Error(`feature-trace: editor exited with status ${exitCode}`);
  }
}

function sourceLabel(candidate: Candidate): string {
  const location = candidateLocation(candidate);
  return `${location.source}:${location.line}`;
}

function candidateLocation(candidate: Candidate): CandidateLocation {
  const raw = candidate.source;
  const explicitLine =
    typeof candidate.line === "number" && Number.isInteger(candidate.line)
      ? candidate.line
      : null;

  const match = raw.match(/^(.*):([0-9]+)$/);
  if (match) {
    return {
      source: match[1] ?? raw,
      line: explicitLine ?? Number(match[2]),
    };
  }

  return {
    source: raw,
    line: explicitLine ?? 1,
  };
}

function sourceString(record: AnyRecord): string {
  const source = stringFromUnknown(
    record.source ?? record.file ?? record.location,
  );

  if (source !== "") {
    return source;
  }

  const definitions = arrayFromUnknown(record.definitions);
  if (definitions.length === 1) {
    const definition = asRecord(definitions[0]);
    return stringFromUnknown(
      definition.source ?? definition.file ?? definition.location,
    );
  }

  return "";
}

function table(
  columns: Array<{ title: string; width: number }>,
  rows: string[][],
): string {
  const header = columns
    .map((column) => padRight(column.title, column.width))
    .join("  ")
    .trimEnd();

  const body = rows
    .map((row) =>
      columns
        .map((column, index) =>
          padRight(truncate(row[index] ?? "", column.width), column.width),
        )
        .join("  ")
        .trimEnd(),
    )
    .join("\n");

  return body === "" ? header : `${header}\n${body}`;
}

function padRight(value: string, width: number): string {
  const text = value.length > width ? truncate(value, width) : value;
  return text + " ".repeat(Math.max(0, width - text.length));
}

function truncate(value: string, width: number): string {
  if (value.length <= width) {
    return value;
  }

  if (width <= 1) {
    return value.slice(0, width);
  }

  return `${value.slice(0, width - 1)}…`;
}

function asRecord(value: unknown): AnyRecord {
  if (value != null && typeof value === "object" && !Array.isArray(value)) {
    return value as AnyRecord;
  }

  return {};
}

function arrayFromUnknown(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringFromUnknown(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  return "";
}

function numberFromUnknown(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isInteger(value)) {
    return value;
  }

  if (typeof value === "string" && /^[0-9]+$/.test(value)) {
    return Number(value);
  }

  return undefined;
}

function stableString(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (value == null) {
    return "";
  }

  return JSON.stringify(value);
}
