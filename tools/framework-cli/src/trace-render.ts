import { table } from "./table";
import type { Feature, Location, TraceResult } from "./trace";

const featureColumns = [
  { title: "FEATURE", width: 31 },
  { title: "STATUS", width: 9 },
  { title: "PRIORITY", width: 9 },
  { title: "ACTIVATION", width: 15 },
  { title: "SOURCE", width: 80 },
];

export function sourceLabel({ source, line }: Location): string {
  return line == null ? source : `${source}:${line}`;
}

function featureTable(features: Feature[]): string {
  return table(featureColumns, features.map((feature) => {
    const activation = feature.activations[0];
    const source = activation ? sourceLabel(activation) : "";
    const hint = activation?.origin === "text-scan" ? " (source hint)" : "";
    return [feature.name, feature.status, feature.winning_priority ?? "-", feature.kind, source + hint];
  }));
}

export function renderTrace(result: TraceResult): string {
  if (result.type === "why") {
    if (result.definitions.length === 0) return JSON.stringify(result, null, 2);
    return [
      `Effective value for ${result.path}: ${result.effective} (winning priority: ${result.winning_priority ?? "unknown"})`,
      table([
        { title: "OPTION", width: 50 },
        { title: "FILE", width: 80 },
        { title: "VALUE", width: 60 },
      ], result.definitions.map((definition) => [
        result.path,
        sourceLabel(definition),
        definition.renderedValue,
      ])),
    ].join("\n");
  }

  const sections: string[] = [];
  if (result.system.length > 0) {
    sections.push(`SYSTEM FEATURES / ${result.host}\n${featureTable(result.system)}`);
  }

  const home = new Map<string, Feature[]>();
  for (const feature of result.home) {
    const user = feature.user ?? "unknown";
    const features = home.get(user) ?? [];
    features.push(feature);
    home.set(user, features);
  }
  for (const [user, features] of home) {
    sections.push(`HOME FEATURES / ${user}@${result.host}\n${featureTable(features)}`);
  }

  return sections.length ? sections.join("\n\n") : JSON.stringify(result, null, 2);
}
