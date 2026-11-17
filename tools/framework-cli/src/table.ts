export type Column = {
  title: string;
  width: number;
};

export function clip(value: unknown, width: number): string {
  const text = String(value ?? "-");
  if (text.length <= width) return text;
  if (width <= 3) return text.slice(0, width);
  return `${text.slice(0, width - 3)}...`;
}

export function row(columns: Column[], values: unknown[]): string {
  return columns
    .map((column, index) => clip(values[index] ?? "", column.width).padEnd(column.width, " "))
    .join("  ")
    .trimEnd();
}

export function table(columns: Column[], rows: unknown[][]): string {
  return [
    row(columns, columns.map((column) => column.title)),
    ...rows.map((values) => row(columns, values)),
  ].join("\n");
}
