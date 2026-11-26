# Why the Minecraft job guard is required

The pinned Nixpkgs packages systemd 260.5. In that release the manager
enqueues a job and then replies with its object path. The synchronous
client subscribes before dispatch and waits for the corresponding
`JobRemoved`. Disconnect closes the client's bus and may fail its wait.
Service jobs are outside the job GC used for units like devices, even if
the bus tracker loses its last client. `ListJobs` is a snapshot of the
current queue. [Nixpkgs package](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/pkgs/os-specific/linux/systemd/default.nix#L202-L211),
[manager enqueue and reply](https://github.com/systemd/systemd/blob/v260.5/src/core/dbus-unit.c#L1985-L2010),
[systemctl dispatch and wait](https://github.com/systemd/systemd/blob/v260.5/src/systemctl/systemctl-start-unit.c#L388-L430),
[disconnect handling](https://github.com/systemd/systemd/blob/v260.5/src/shared/bus-wait-for-jobs.c#L48-L78),
[job GC eligibility](https://github.com/systemd/systemd/blob/v260.5/src/core/job.c#L1465-L1476),
[manager job API](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1288-L1294),
[current job queue](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1425-L1439).

`--no-block` returns at admission. `--job-mode=fail` applies to conflicting
queued work and provides no exclusion during archive creation. Canceling a
job can leave a unit transition in progress. Freezing stops scheduling the
unit's processes, so it does not produce a clean application stop and is
automatically undone before a unit job executes. A unit path condition
is tested at start and `RefuseManualStart=` still allows activation by
dependencies. A transient coordinator would still need to exclude concurrent managed operations
and coordinate the host and guest managers. The
fixed flock and the same-boot guard retain those admission semantics with
the existing native lifecycle owners. [systemctl options](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L2215-L2249),
[blocking semantics](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L2424-L2433),
[cancellation](https://github.com/systemd/systemd/blob/v260.5/man/org.freedesktop.systemd1.xml#L1638-L1649),
[freeze](https://github.com/systemd/systemd/blob/v260.5/man/systemctl.xml#L651-L663),
[manual start policy](https://github.com/systemd/systemd/blob/v260.5/man/systemd.unit.xml#L1011-L1025),
[path conditions](https://github.com/systemd/systemd/blob/v260.5/man/systemd.unit.xml#L1744-L1754),
[transient units](https://github.com/systemd/systemd/blob/v260.5/man/systemd-run.xml#L69-L81),
[pinned container transport](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/pkgs/by-name/ni/nixos-container/nixos-container.pl#L383-L389),
[nsenter child exit handling](https://github.com/util-linux/util-linux/blob/v2.42.4/sys-utils/nsenter.c#L563-L579).

See the [diagnosis and recovery procedure](README.md#diagnose-and-recover).
