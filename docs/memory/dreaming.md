# Maintain canonical knowledge

Read the current source, affected decision and relevant receipt. Distinguish declarations, evaluation, builds, tests, observed runtime and hypotheses. Update only the affected canonical page and roadmap; retain historical evidence via an exact Git commit or CI run link in [Archive](../archive/README.md). Do not rewrite old observations as current facts.

Use `git log -- <path>`, `git blame`, `rg`, native Nix option definitions and CI results for investigation. The former retrieval benchmark and provenance scanner are archived; they did not establish a reader-quality improvement. There is no separate provenance database to maintain.

Check local links with the pinned [Nix validation](../cookbook/ci-validation.md). A link check does not establish semantic correctness. Never infer authorization or host activation from documentation.
