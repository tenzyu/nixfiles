"""RTK must preserve Biome and project lint scripts, not substitute ESLint."""

import subprocess


for command in [
    "biome --version",
    "npx biome check .",
    "bunx biome check .",
    "bun x biome check .",
    "pnpm exec biome check .",
    "pnpm dlx biome check .",
    "npm exec biome check .",
    "yarn biome check .",
    "/nix/store/example/bin/biome check .",
    "npm run lint",
    "pnpm lint",
    "pnpm run lint",
    "yarn lint",
    "bun lint",
    "bun run lint",
]:
    result = subprocess.run(["rtk", "rewrite", command], capture_output=True, text=True)
    assert result.returncode == 1 and not result.stdout, (command, result)

result = subprocess.run(["rtk", "rewrite", "git status && biome check ."], capture_output=True, text=True)
assert result.returncode in (0, 3), result
assert result.stdout.strip() == "rtk git status && biome check .", result
print("Biome commands remain native; git status still uses RTK.")
