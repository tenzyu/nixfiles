# Run SplitCast development on neko7

`scripts/splitcast/remote-dev.sh` makes a separate snapshot on neko7 and runs a bounded build or test command there. It leaves both hosts' existing Git worktrees and branches untouched. It transfers the current SplitCast files and the three host and desktop configuration files. It does not transfer `.local`, other untracked files, credentials, or unrelated modifications. Inspect the script if a change outside that list is needed for a build.

Run these commands from the nixfiles checkout:

```sh
bash scripts/splitcast/remote-dev.sh snapshot
bash scripts/splitcast/remote-dev.sh build
bash scripts/splitcast/remote-dev.sh test
```

Each run prints its unique directory under `~/.cache` on neko7. Snapshots are retained for inspection. They are not automatically synchronized after creation. Remove one manually only after checking that it is no longer needed. Set `SPLITCAST_BUILD_HOST` to an existing verified SSH alias to select a different host.

The build asks Nix for one job and two cores. Nix daemon builds run outside the SSH user's systemd scope, so this is not a hard CPU or memory limit. The test command uses a user scope with a two-core CPU quota and a 3 GiB memory high limit. It supplies FFmpeg, MediaMTX, websocket-client, and the locked RNNoise plugin. Tests requiring a graphical session or local capture hardware can still skip. Read the test output before claiming coverage.

On 2026-11-02, a snapshot at `/home/tenzyu/.cache/splitcast-dev.R3dfXxvK/repo` built `splitcast` and the patched OBS on neko7. The build output is `/nix/store/illklarxvfspw633npgq25z3vvnncyyg-splitcast-0.1.0`. `nix log /nix/store/jrbma5c750j0c5lv7md06ms9if84zivk-obs-studio-splitcast-32.1.2 --offline` retrieves the OBS build log on neko7. A subsequent run of this script built `/nix/store/v7yddxmsqx02aiz4qnanw2mz4lgr7903-splitcast-0.1.0`. Its test action ran 45 tests, with five skips for unavailable browser, graphical, and capture integrations. It exercised real synthetic RTMP and RTSP transport and the RNNoise plugin on neko7.

This SSH workflow executes Nix and tests on neko7. It does not configure Nix distributed builds from neko5. A test of `--builders 'ssh://neko7 x86_64-linux - 1 1 - -' --max-jobs 0` failed because neko5's Nix daemon could not verify neko7's host key. The ordinary user's verified SSH connection succeeded. Do not disable SSH host-key checking. A dedicated daemon-accessible identity and a pinned verified host key require an administrator-approved setup, followed by a forced uncached remote derivation test.

Later on 2026-11-02, the running neko5 configuration listed `ssh-ng://nixbuilder@neko7`. A minimal uncached derivation built through that machine with local jobs and substitutes disabled. The command and result are in [the E2E results](E2E_RESULTS.md). The `nixbuilder` account is listed as a Nix trusted user in the upstream configuration, which grants substantial control over the Nix store. The probe does not establish that this trust boundary is suitable for every workload.

If neko7 is unavailable, continue editing locally and wait to run builds until it returns. An explicitly chosen local `nix build` remains available, but can load neko5. No host activation is required to use this SSH workflow.
