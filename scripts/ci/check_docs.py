#!/usr/bin/env python3
"""Offline Markdown/OKF v0.2 subset validation. Reject unsupported YAML syntax."""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit, unquote

LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)")
FIELD = re.compile(r"^([a-z][a-z0-9_-]*):(?:\s*(.*))?$")
SOURCE = re.compile(r"^  - ([a-z_]+):\s*(.+)$")
PROPERTY = re.compile(r"^    ([a-z_]+):\s*(.+)$")
PIN = re.compile(r"^https://github\.com/tenzyu/nixfiles/blob/([a-f0-9]{40})/(.+)$")
SHA = re.compile(r"^[a-f0-9]{40}$")

def parse_meta(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("missing frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError("unterminated frontmatter") from exc
    data, item = {}, None
    for line in lines[1:end]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = FIELD.fullmatch(line)
        if m:
            key, value = m.groups()
            if key in data:
                raise ValueError("duplicate key: " + key)
            if key == "sources":
                if value:
                    raise ValueError("sources must be a block list")
                data[key] = []
            else:
                if not value:
                    raise ValueError("empty field: " + key)
                data[key] = value.strip().strip('"').strip("'")
            item = None
            continue
        m = SOURCE.fullmatch(line)
        if m and "sources" in data:
            item = {m[1]: m[2].strip().strip('"')}
            data["sources"].append(item)
            continue
        m = PROPERTY.fullmatch(line)
        if m and item is not None:
            if m[1] in item:
                raise ValueError("duplicate source key: " + m[1])
            item[m[1]] = m[2].strip().strip('"')
            continue
        raise ValueError("unsupported YAML form: " + line)
    return data

def prose(content):
    result, fence = [], None
    for line in content.splitlines():
        m = re.match(r"^\s*(" + chr(96) + r"{3,}|~{3,})", line)
        if m:
            if fence is None:
                fence = m[1][0]
            elif fence == m[1][0]:
                fence = None
            continue
        if fence is None:
            result.append(line)
    return "\n".join(result)

def slugs(content):
    found, counts = set(), {}
    for line in prose(content).splitlines():
        m = re.match(r"^ {0,3}#{1,6}\s+(.+)$", line)
        if not m:
            continue
        title = re.sub(r"\s+#+\s*$", "", m[1])
        title = re.sub(r"<[^>]*>", "", title).replace(chr(96), "")
        title = title.replace("*", "").replace("_", "")
        key = re.sub(r"[^\w -]", "", title.casefold().strip()).replace(" ", "-")
        n = counts.get(key, 0)
        counts[key] = n + 1
        found.add(key if not n else key + "-" + str(n))
    return found

def all_docs(root):
    skip = {".git", ".direnv", "node_modules", ".venv", "result"}
    return sorted(p for p in root.rglob("*.md") if p.is_file()
                  and not skip.intersection(p.relative_to(root).parts))

def git_object(root, sha, name):
    return subprocess.run(["git", "cat-file", "-e", sha + ":" + name], cwd=root,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          check=False).returncode == 0

def check(root, fragments=True):
    errors, paths = [], all_docs(root)
    count, concepts = 0, 0
    wiki = root / "docs/memory"
    for path in paths:
        rel = path.relative_to(root).as_posix()
        raw = path.read_text(encoding="utf-8")
        if wiki in path.parents:
            if path.name == "index.md":
                try:
                    meta = parse_meta(path)
                    if path == wiki / "index.md" and meta != {"okf_version": "0.2"}:
                        errors.append(rel + ": root index may only have okf_version 0.2")
                except ValueError as exc:
                    errors.append(rel + ": " + str(exc))
            elif path.name == "log.md":
                for line in prose(raw).splitlines():
                    if line.startswith("## ") and not re.fullmatch(r"## \d{4}-\d{2}-\d{2}", line):
                        errors.append(rel + ": non-ISO log date: " + line)
            else:
                concepts += 1
                try:
                    meta = parse_meta(path)
                except ValueError as exc:
                    errors.append(rel + ": " + str(exc))
                    meta = {}
                if not meta.get("type"):
                    errors.append(rel + ": missing required OKF type")
                if meta.get("status", "stable") not in ("draft", "stable", "deprecated"):
                    errors.append(rel + ": invalid OKF status")
                rev = meta.get("source_revision")
                if rev and not SHA.fullmatch(rev):
                    errors.append(rel + ": invalid source_revision")
                for item in meta.get("sources", []):
                    url = item.get("resource")
                    if not url:
                        errors.append(rel + ": missing sources resource")
                        continue
                    m = PIN.fullmatch(url)
                    if m:
                        if rev and m[1] != rev:
                            errors.append(rel + ": mixed provenance revisions")
                        if not git_object(root, m[1], m[2]):
                            errors.append(rel + ": missing pinned Git object " + m[1] + ":" + m[2])
                    elif not urlsplit(url).scheme and not (path.parent / url).exists():
                        errors.append(rel + ": missing source path " + url)
        for match in LINK.finditer(prose(raw)):
            url = unquote(match[1])
            if url.startswith("?"):
                continue
            if url.startswith("#"):
                dest, fragment = path, url[1:]
            else:
                parsed = urlsplit(url)
                if parsed.scheme or parsed.netloc:
                    continue
                dest = (root / parsed.path.lstrip("/")) if parsed.path.startswith("/") else path.parent / parsed.path
                fragment = parsed.fragment
            count += 1
            if not dest.exists():
                errors.append(rel + ": broken link " + url)
            elif fragments and fragment and dest.is_file() and dest.suffix == ".md":
                if fragment.casefold() not in slugs(dest.read_text(encoding="utf-8")):
                    errors.append(rel + ": broken fragment " + url)
    if wiki.exists():
        index = (wiki / "index.md").read_text(encoding="utf-8")
        for path in wiki.rglob("*.md"):
            if path.name not in ("index.md", "log.md") and "(" + path.name + ")" not in index:
                errors.append("docs/memory/index.md: unindexed concept " + path.name)
    return errors, (len(paths), count, concepts)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--no-fragments", action="store_true")
    args = parser.parse_args()
    errors, counts = check(args.root.resolve(), not args.no_fragments)
    for error in errors:
        print("ERROR:", error, file=sys.stderr)
    print("docs: %d Markdown; %d links; %d OKF concepts; %d errors" %
          (*counts, len(errors)))
    return int(bool(errors))

if __name__ == "__main__":
    sys.exit(main())
