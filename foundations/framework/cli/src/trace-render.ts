import { table } from "./table";

export type AnyRecord = Record<string, unknown>;

type Location = {
  source?: string | null;
  line?: number | null;
};

function loc(value: Location | null | undefined): string {
  if (value == null || value.source == null) return "-";
  return value.line == null ? value.source : `${value.source}:${value.line}`;
}

function firstActivation(record: AnyRecord): AnyRecord {
  const activations = Array.isArray(record.activations) ? record.activations as AnyRecord[] : [];
  return activations[0] ?? { kind: "-" };
}

function recordsForFeature(result: AnyRecord): AnyRecord[] {
  if (result.scope === "all") {
    const records: AnyRecord[] = [];
    if (result.system && typeof result.system === "object") records.push(result.system as AnyRecord);
    if (Array.isArray(result.home)) records.push(...result.home as AnyRecord[]);
    return records;
  }
  return [result];
}

export function renderHost(result: AnyRecord, host: string, scope: string): string {
  const chunks: string[] = [];

  if (scope !== "home") {
    const rows = ((result.system ?? []) as AnyRecord[]).map((record) => {
      const activation = firstActivation(record);
      return [record.name, record.status, activation.kind ?? "-", loc(activation)];
    });
    chunks.push(`SYSTEM FEATURES / ${host}`);
    chunks.push(table([
      { title: "FEATURE", width: 30 },
      { title: "STATUS", width: 8 },
      { title: "ACTIVATION", width: 14 },
      { title: "SOURCE", width: 80 },
    ], rows));
  }

  if (scope !== "system") {
    const home = (Array.isArray(result.home) ? result.home : []) as AnyRecord[];
    const groups = new Map<string, AnyRecord[]>();
    for (const record of home) {
      const user = String(record.user ?? "?");
      groups.set(user, [...(groups.get(user) ?? []), record]);
    }

    if (groups.size === 0) {
      chunks.push(`\nHOME FEATURES / (none enabled)@${host}`);
      chunks.push(table([
        { title: "FEATURE", width: 30 },
        { title: "STATUS", width: 8 },
        { title: "ACTIVATION", width: 14 },
        { title: "SOURCE", width: 80 },
      ], []));
    } else {
      for (const [user, records] of groups.entries()) {
        const rows = records.map((record) => {
          const activation = firstActivation(record);
          return [record.name, record.status, activation.kind ?? "-", loc(activation)];
        });
        chunks.push(`\nHOME FEATURES / ${user}@${host}`);
        chunks.push(table([
          { title: "FEATURE", width: 30 },
          { title: "STATUS", width: 8 },
          { title: "ACTIVATION", width: 14 },
          { title: "SOURCE", width: 80 },
        ], rows));
      }
    }
  }

  return chunks.join("\n");
}

export function renderFeature(result: AnyRecord): string {
  const chunks: string[] = [];
  for (const record of recordsForFeature(result)) {
    const userSuffix = record.user ? `/${record.user}` : "";
    chunks.push(`feature: ${record.name}  scope: ${record.scope}${userSuffix}  status: ${record.status}`);

    const activations = (Array.isArray(record.activations) ? record.activations : []) as AnyRecord[];
    chunks.push("\nACTIVATIONS");
    chunks.push(activations.length === 0 ? "  -" : table([
      { title: "KIND", width: 14 },
      { title: "OPTION", width: 54 },
      { title: "SOURCE", width: 80 },
      { title: "BY", width: 24 },
    ], activations.map((activation) => [activation.kind ?? "-", activation.option ?? "-", loc(activation), activation.by ?? ""])));

    const implementations = (Array.isArray(record.implementations) ? record.implementations : []) as AnyRecord[];
    chunks.push("\nIMPLEMENTATIONS");
    chunks.push(implementations.length === 0 ? "  -" : table([
      { title: "CLASS", width: 14 },
      { title: "MODULE", width: 54 },
      { title: "SOURCE", width: 80 },
    ], implementations.map((implementation) => [implementation.moduleClass ?? "-", implementation.optionPrefix ?? "-", loc(implementation)])));

    const effects = (Array.isArray(record.effects) ? record.effects : []) as AnyRecord[];
    chunks.push("\nEFFECTS");
    chunks.push(effects.length === 0 ? "  -" : table([
      { title: "KIND", width: 14 },
      { title: "VALUE", width: 12 },
      { title: "SOURCE", width: 80 },
    ], effects.map((effect) => [effect.kind ?? "-", effect.renderedValue ?? "-", loc(effect)])));

    chunks.push("");
  }
  return chunks.join("\n").trimEnd();
}

export function renderWhy(result: AnyRecord): string {
  const lines = [`option: ${result.path}`, `effective: ${result.effective}`, "", "DEFINITIONS"];
  const definitions = (Array.isArray(result.definitions) ? result.definitions : []) as AnyRecord[];
  if (definitions.length === 0) {
    lines.push("  -");
  } else {
    for (const definition of definitions) {
      lines.push(`  ${definition.kind ?? "-"}  ${definition.renderedValue ?? "-"}  ${loc(definition)}`);
    }
  }
  return lines.join("\n");
}
