# Scheduled source identity notes

The schedule document persists home, watcher-lock and store-lock identities.
Linux btrfs assigns anonymous `st_dev` values at mount time: the reported reboot
changed `56:<inode>` to `54:<same-inode>`. Exact comparisons correctly refused,
but the device number was the wrong durable filesystem identifier.

New records use `fsid:<f_fsid word 0 as 8 hex digits><word 1 as 8 hex digits>:<inode>`.
Ruby's `File::Stat` has no fsid API. Ruby's bundled Fiddle calls libc `fstatfs`
on pinned descriptors, without subprocesses, root, pathname resolution or a new
runtime dependency. The structure follows Linux's 64-bit generic statfs ABI
(`include/uapi/asm-generic/statfs.h`); other architectures and non-Linux platforms refuse.
The supported deployment is x86_64/aarch64 Linux with normal persistent-filesystem
FSIDs; unusual filesystem/ABI configurations need separate verification.

## Unprivileged investigation (2026-11-10)

On this host `/proc/self/mountinfo` identifies `/home` as btrfs `@home`,
subvolid 257; `/sys/fs/btrfs` identifies UUID
`4cc31836-582f-41ce-8329-eaa279f1e370`, metadata UUID identical, `temp_fsid=0`.
`stat -f -c '%T %i' .` reports `btrfs cfeaf29421dea3bf`; the Ruby implementation
returns the same FSID. Reopening a scratch file in this worktree twice returned
`fsid:cfeaf29421dea3bf:1200230155` both times (`st_dev=54`). A copy in another
directory returned `fsid:cfeaf29421dea3bf:1200230156`. A scratch copy on
`/dev/shm` returned `fsid:a6813f3c277d21d7:144776` (`st_dev=33`). All scratch
files were removed. Production state was neither inspected nor changed.

The installed kernel headers and the matching Linux 7.2.15 `vmlinux` were
available locally, but the btrfs C source was not. Inspection with
`objdump -d --disassemble=btrfs_statfs /usr/src/linux-omarchy/vmlinux` shows the
UUID words XORed together, byte-swapped, then XORed with the subvolume root ID
halves before writing `f_fsid`. Independently applying that calculation to the
UUID above and root ID 257 gives `cfeaf29421dea3bf`. This is the calculation in
Linux `fs/btrfs/super.c`'s `btrfs_statfs`, not the anonymous mount device number.
The disassembly also contains a device-number XOR for **temporary** FSIDs;
that mode is not enabled here and is not a supported reboot-stability claim.

No reboot was performed. Stability follows from the normal btrfs calculation,
not an empirical reboot test; future kernel algorithm changes, changed UUIDs,
temporary FSIDs and nonpersistent filesystems may require explicit recovery.
A subvolume snapshot has a different root ID, even when inodes are preserved.
Ordinary copies have different inodes; another filesystem has another FSID.
Forging a filesystem UUID/root ID requires filesystem administration privileges,
not merely copying a file. As with `dev:ino`, inode reuse, privileged filesystem
clones or an actor able to rewrite private state are outside this ownership
check's guarantee. FSID is an ownership binding, not a cryptographic credential.

Only the schedule document and explicit migration audit save these identities.
Descriptor/path pinning, watcher readiness/status/pending frames and extension
bindings remain `dev:ino`; these checks live within one boot/runtime, and reload
forgets extension bindings rather than persisting them. The schedule document
still checks original ownership on fresh startup/reload.

Legacy same-device-and-inode matches can safely upgrade automatically. After a
legacy device mismatch there is no saved FSID to prove continuity: the separate
[human migration command](cli-reference.md#scheduled-supervisor-prompts) requires
independent original-source verification, exact old identities, matching inodes
and an explicit current FSID attestation, with durable old/new audit evidence.
It never runs as part of watcher startup or automatic recovery.
