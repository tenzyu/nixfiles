# SplitCast migration verification

The pre-migration Python package baseline ran 55 tests with 10 skipped. The script baseline ran 18 tests. The pre-migration differential compared 46 configurations with zero mismatches after its explicit stricter out-of-range URL port rule. The frozen corpus records the original Python acceptance and that intentional exception separately.

These results do not establish feature parity, deployed service status, game-path safety, or permission to cut over. Validate the current Rust package and host configuration checks before use. The service remains gated unless `rustCandidate` is explicitly approved and enabled.
