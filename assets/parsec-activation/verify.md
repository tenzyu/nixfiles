# Verify Parsec activation

Run `nix build -L --no-link .#checks.x86_64-linux.parsec-activation` to exercise
the evaluated Home Manager hooks with the pinned `run` function and the
packaged review command in isolated `HOME` directories. The fixtures check
`INTENT-01` dry-run, `BOUNDARY-01` symlink and parent
refusal, `PUBLISH-01` new files and concurrent collision, `PUBLISH-02` failures
before and after link, `OWNED-01` preservation of unreadable files, legacy
store links and simulated app saves, and `RECOVERY-01` repeat behavior.
A separate process creates app-owned
JSON just before the kernel link. The fixture checks that the winner's bytes
and mode survive and no `config.txt` is created. Legacy entries are tested
before and at publication. Review fixtures check diagnostics, exit status,
and unchanged bytes and metadata. The injected flush errors simulate
publication faults. Real-host Parsec acceptance is **NOT RUN**.

See the [settings review procedure](README.md).
