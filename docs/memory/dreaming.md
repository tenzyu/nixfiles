# Maintain canonical knowledge

Read the current source, the affected decision, and the relevant test or host record. Distinguish declarations, evaluation, builds, tests, runtime observations, and hypotheses. Update only the affected canonical page and roadmap. Retain historical evidence in the [archive](../archive/README.md) with a link to the exact Git commit or CI run. Do not rewrite old observations as current facts.

Use `git log -- <path>`, `git blame`, `rg`, native Nix option definitions and CI results for investigation. The archive retains the former retrieval benchmark and provenance scanner. They did not establish a reader-quality improvement. There is no separate provenance database to maintain.

Check local links with the pinned [Nix validation](../cookbook/ci-validation.md). A link check does not establish semantic correctness. Never infer authorization or host activation from documentation.
