---
type: Guide
title: "Documentation entrypoint"
description: "Compatibility link to the source-grounded Wiki"
status: stable
source_revision: 438aa02b426db0a5962dd0102f0cbb04a5191c06
sources:
  - id: flake
    resource: https://github.com/tenzyu/nixfiles/blob/438aa02b426db0a5962dd0102f0cbb04a5191c06/flake.nix
    title: "Flake entrypoint"
---

# Documentation

Start with [the repository README](../README.md) for the host matrix, structure, safe validation and change workflow, then use the [Wiki index](index.md) to locate a specific architecture explanation, decision or runbook.

The implementation source, tests and recorded host observations have distinct authority. **Do not** infer the running system from a flake input or an enabled service option.

SplitCast product code lives in [its own repository](https://github.com/tenzyu/splitcast); nixfiles owns the pinned consumer integration. Historical extraction notes remain in Git history, not in this navigation entrypoint.
