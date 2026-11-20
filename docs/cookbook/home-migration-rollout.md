# Switch without moving HOME data

Use this procedure when a NixOS update changes Home Manager activation or HOME routes. Keep applications on their verified routes for the first switch. Plan any data migration separately using the [Home migration runbook](../../assets/home-layout/README.md). A NixOS rollback does not undo a HOME data move.

## Check the candidate on each host

Run these commands on the target as the affected HOME owner. Set `candidate` to the flake reference for the exact commit under review. `nh os switch --dry` can build and show the system diff, but it does not establish that the live HOME passes admission.

```sh
host=$(hostname -s)
owner=$(id -un)
generation=$(nix build --no-link --no-write-lock-file --print-out-paths \
  "$candidate#nixosConfigurations.$host.config.home-manager.users.$owner.home.activationPackage") &&
env -i HOME="$HOME" USER="$owner" LC_ALL=C HOME_MANAGER_BACKUP_EXT=hm-backup \
  "$generation/home-layout-pre-switch" "$generation" \
  --incumbent "/run/current-system/etc/home-migration/$owner" --sessions-active
```

This read-only probe uses the repo's `hm-backup` setting and assumes sessions are active. Leave the incumbent path as shown even if the marker does not exist. If the probe refuses, stop. The real `nh os switch` still runs the native pre-switch checks with the live session state and candidate configuration.

## Resolve the refusals seen on #70

- On `neko7`, `Unexpected entry in migration journal directory` refers to an older npm cache migration. Both recorded moves have matching completion records. The old `.npm` path is absent, and the current npm cache and retained conflict copy are present. The records do not contain inode evidence. Verify the live npm route and preserve the journal and retained cache in a verified backup before deciding how to archive the old run or support the old format. Do not delete or rename the journal to make the check pass. Confirm that no migration remains unfinished before changing where the runner looks for history.
- On `neko5`, `Activation writes unknown` names four Home Manager `onChange` hooks for Kitty, Mako, and Waybar. The generated hooks request reloads or send signals. Verify the receiving applications' write effects, then account for them in the candidate or move the reloads out of activation. Do not assume a signal has no write effects or weaken the check for other hooks.

If the check says `inventory and declare the verified incumbent route`, use the candidate's `home-layout-migrate inventory` and compare it with the running setup. A file at the intended path does not establish that the live app uses it. Verify the active shell, launcher, or service, then set `local.homeMigration.adoptedRoutes.<group>` to `"legacy"` or `"intended"` as observed. Do not move files to resolve missing adoption evidence.

Rerun the probe on both hosts with the corrected candidate. A pass on one host does not cover the other host's routes, journals, or activation hooks.

## Switch one host at a time

1. Confirm that the candidate keeps verified routes in use. If a group still uses its old route, configure a holding generation as described in the runbook. Do not run `home-layout-migrate apply` as part of the switch.
2. After review and both pre-switch probes pass, confirm that the merged revision has the tested configuration. Set `candidate` to its pinned flake reference. Record the current system path with `readlink -f /run/current-system` and confirm console access and the rollback plan.
3. Run `nh os switch --hostname "$host" "$candidate"` on the first host. Keep native checks enabled. Stop if any check or activation fails.
4. Verify `/run/current-system` points to the expected generation. Check the affected Home Manager unit and confirm the relevant apps still read, save, and reopen data on their incumbent routes. Record the host, revision, generation, and outcome before switching the second host.
