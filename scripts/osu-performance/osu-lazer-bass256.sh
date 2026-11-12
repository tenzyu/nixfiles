#!/usr/bin/env bash
# BASS device period experiment accepted by user for DT-custom and FUN mod.
# Explicit opt-in launcher. Does not modify PipeWire metadata or Nix config.
set -euo pipefail
if [[ -n ${OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD-} && ${OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD} != -256 ]]; then
  echo 'Refusing to override an existing BASS period env var.' >&2
  exit 2
fi
export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-256
exec osu-lazer "$@"
