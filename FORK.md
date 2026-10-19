# Operating this fork

This is a fork of [omacom/omarchy](https://github.com/omacom/omarchy) carrying changes that are not upstream. Everything outside the changes below tracks upstream unchanged.

| Change | Branch |
|---|---|
| OpenCode baseline build | `opencode-conditional` |

- **Part 1** — what the change is and why
- **Part 2** — applying it to a running Omarchy install
- **Part 3** — keeping the fork on stable releases

---

# Part 1 — Explanation

## OpenCode on CPUs without AVX2

### The problem

OpenCode is built with Bun, whose stock build targets `x86-64-v3` and therefore requires AVX2. Any CPU older than Haswell (2013) — Sandy Bridge and Ivy Bridge, including the 2011 iMac12 — lacks it, and the binary dies with an illegal instruction.

The failure is easy to misread. Installed through npm, the wrapper exits **0 with no output**, so the symptom is "`opencode` does nothing" rather than a crash.

Upstream publishes `opencode-linux-x64-baseline` for exactly this case, and its own installer selects it. Omarchy does not: `install/user/mise.sh` hardcodes the package name, mise's registry entry resolves to the stock build, and nothing in Omarchy looks at the CPU. The result is that Omarchy ships OpenCode as a supported default agent that cannot run at all on pre-2013 x86 hardware.

### What this change does

| File | Change |
|---|---|
| `bin/omarchy-hw-avx2` | New. CPU capability check, same shape as the other 27 `omarchy-hw-*` commands |
| `install/user/mise.sh` | Installs the baseline release when AVX2 is absent |
| `bin/omarchy-default-agent` | Same condition, so _Setup > Defaults > Agent_ registers the same package the launcher stub wraps |
| `bin/omarchy-update` | Refuses to update when the checkout is not on the stable release being installed (see Part 3) |

### Why the package spec ends in `.tar`

The release publishes two baseline builds for linux x64:

```
opencode-linux-x64-baseline.tar.gz        glibc — what Arch needs
opencode-linux-x64-baseline-musl.tar.gz   musl
```

`matching=` is a substring filter, so a bare `matching=baseline` matches both and ubi may select the musl build. That binary names `/lib/ld-musl-x86_64.so.1` as its interpreter, which does not exist on Arch, and running it fails with `cannot execute: required file not found` — on a file that is plainly present. `matching=baseline.tar` selects only the glibc asset, since the musl one reads `baseline-musl.tar`.

### Why the third file matters

`~/.local/bin/opencode` is a small generated wrapper with the package name baked into it, and it is what actually executes when you type `opencode` or press the agent keybinding.

`omarchy-default-agent` never rewrites that wrapper — it only runs `mise use -g <package>`. So without the third change, selecting OpenCode in the Defaults menu re-registers the stock build while the wrapper still names another, leaving two packages disagreeing about which binary should run. Patching these keeps the install path, the menu, and the wrapper on the same package.

### Status

Verified on a 2011 iMac12 (Sandy Bridge, no AVX2) running Omarchy: `opencode` reports its version and runs. Step 5 in Part 2 is the same check on any other machine.

---

# Part 2 — Procedure: applying it to a running Omarchy install

Run everything on the Omarchy machine, as your normal user.

### 1. Confirm the machine needs it

```bash
grep -c avx2 /proc/cpuinfo
```

`0` — continue. Anything else — stop, this change is not for this machine.

### 2. Point Omarchy at the fork

```bash
git clone git@github.com:diegoicosta/omarchy.git ~/develop/omarchy
cd ~/develop/omarchy
git remote add upstream https://github.com/omacom/omarchy.git
git checkout opencode-conditional
omarchy dev link ~/develop/omarchy
```

Reboot.

### 3. Confirm the link took

```bash
echo $OMARCHY_PATH
```

Must print the checkout path from step 2 — `/home/diego/develop/omarchy`. If it still prints `/usr/share/omarchy`, the reboot did not happen; reboot and check again before continuing.

### 4. Regenerate the OpenCode launcher

```bash
mise rm -g opencode
omarchy-mise-install "ubi:anomalyco/opencode[matching=baseline.tar]" opencode
```

`mise rm` errors harmlessly if the entry is not registered.

### 5. Verify

```bash
opencode --version
```

- Prints a version — done, continue to step 6.
- Prints nothing, or exits immediately with no output — see Troubleshooting.

### 6. Select it

```bash
omarchy default agent opencode
```

---

# Part 3 — Keeping the fork on stable releases

The fork runs as the live Omarchy (`OMARCHY_PATH` points at the checkout), so the checkout must be the same release the packages come from. It therefore tracks **stable release tags**, never `quattro`.

## The normal path: one action

Bar → maintenance icon → **Update Omarchy**.

That runs `omarchy-maintenance update`, which:

1. reads the stable Omarchy release on offer (e.g. `4.6.0`; the installed one if none is offered);
2. replays the fork's commit(s) onto tag `v4.6.0`, keeping a `backup/*` branch;
3. pushes `opencode-conditional` with `--force-with-lease`;
4. runs `omarchy update`: snapshot, packages, shell restart, migrations.

With no new release on offer, steps 1–3 are skipped and it is a normal package update. A sync conflict stops before step 4; the machine keeps running the release that works.

The tool is user-owned (`~/.local/bin/omarchy-maintenance`) and is not part of this repository. Copy it when rebuilding a machine.

## The guard

`bin/omarchy-update` refuses to run when the linked checkout is not based on the stable release the update will install. That covers every entry point — bar, Omarchy menu, terminal, scripts — not just the maintenance bar. It exists because newer code with older packages (and the reverse) is what breaks updates: missing packages for migrations, or a shell newer than the installed quickshell.

It relies on the fork staying a **single commit on top of the release tag**. If that ever changes, update the guard in the same commit.

## Manual equivalent

```bash
~/.local/bin/omarchy-maintenance sync     # replay onto the stable tag and push
omarchy update
```

Or by hand, replacing `v4.6.0` with the release being installed:

```bash
cd ~/develop/omarchy
git fetch --no-tags upstream refs/tags/v4.6.0:refs/tags/v4.6.0
git branch backup/opencode-conditional-$(date +%Y%m%d-%H%M%S) HEAD
git switch -C sync/stable v4.6.0
git cherry-pick <the fork commit>
git branch -f opencode-conditional HEAD && git switch opencode-conditional
git branch -D sync/stable
git push --force-with-lease origin opencode-conditional
```

A conflict means upstream touched one of the files the fork changes (see Part 1); read it rather than resolving blindly, since the change may no longer be needed.

## Do not

- Do not rebase onto `upstream/quattro`. That is development code, newer than the stable packages.
- Do not update from another entry point without syncing first: the guard refuses, which is the intended safety net.

No reboot is needed for a routine update. Reboot only when the update says so.

---

# Undoing

```bash
omarchy dev unlink
```

Reboot, then:

```bash
omarchy-mise-install opencode
```

That returns you to the packaged Omarchy and the stock OpenCode build.

# Troubleshooting

**Step 5 fails with `cannot execute: required file not found`.** ubi selected the musl asset. The path in the error exists — it is the ELF interpreter that is missing. Confirm the spec reads `matching=baseline.tar`, then force a clean re-download, because mise keys the install directory on backend and repo rather than on the options and will otherwise keep the musl binary:

```bash
mise rm -g "ubi:anomalyco/opencode" 2>/dev/null
rm -rf ~/.local/share/mise/installs/ubi-anomalyco-opencode
omarchy-mise-install "ubi:anomalyco/opencode[matching=baseline.tar]" opencode
```

**Step 5 prints nothing at all.** The release asset names may have changed. Check them on the [releases page](https://github.com/anomalyco/opencode/releases), adjust the `matching=` value so it selects exactly one linux x64 glibc baseline asset, and re-run step 4.

**`opencode` works, but selecting it in the Defaults menu breaks it.** Part 2 step 3 failed — `$OMARCHY_PATH` is still the packaged path, so the unpatched `omarchy-default-agent` is running.

**`omarchy-hw-avx2: command not found`.** Part 2 step 2 or 3 did not complete; the command only exists in the fork.

**`omarchy update` refuses with "This checkout is not on the stable release being installed".** A new stable release is offered and the fork has not been replayed onto its tag yet. Run `omarchy-maintenance update` (or `omarchy-maintenance sync`) first: it moves the checkout to the release the update will install, then updates.
