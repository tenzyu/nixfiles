# SplitCast Nix modules

The `splitcast` and `splitcast-rs-core` package attributes refer to the Rust candidate. The `splitcast` command is an alias for `splitcast-rs-core`. The patched loopback-only OBS package remains available as `splitcast-obs`.

Home Manager merges role settings into the Rust example and generates TOML. Settings contain paths to credentials, not the credentials themselves. The service is manual and has no `WantedBy` target. With `rustCandidate = false`, its launcher exits with a migration-gated error without starting capture or production. Setting it to true selects the experimental Rust agent and requires separate operator approval after parity and competitive non-regression are established. The CLI package being installed does not approve service cutover.

The capture host remains disabled. No activation, public port opening, or streaming is implied by evaluating these modules. Only the SplitCast user service receives its resource limits; the game does not.
