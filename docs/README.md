---
type: Guide
title: "README.md"
description: "Documentation compatibility entrypoint"
status: stable
source_revision: 22191670806242933bc156e4a5e0cd9ad3ea14f1
sources:
  - id: source-1
    resource: https://github.com/tenzyu/nixfiles/blob/22191670806242933bc156e4a5e0cd9ad3ea14f1/flake.nix
    title: "flake.nix"
---

# Documentation index

`flake.nix`, `modules/`, and `scripts/` define this system configuration. Git state does not establish which operating-system generation is running.

SplitCast implementation, package definitions, patches, tests, research, evidence and development memory now belong to the independent SplitCast repository. This repository consumes its flake input and retains only integration settings. See [consumer setup](splitcast-consumer.md).

The earlier source material remains recoverable from source commit `3c8857353581424e5cca517d7ccf0db8de7514d4`. The independent repository's import manifest records original Git blob and content identities and labels normalized publication copies. No historical pass implies current deployment acceptance.

The separately supplied game-optimization wiki remains separate evidence. Moving SplitCast does not replace that wiki or establish new game-performance measurements.

## Current index

The agent-readable knowledge bundle lives in [OKF index](index.md). The roadmap is [separate](../ROADMAP.md). This file remains as an older documentation entrypoint.
