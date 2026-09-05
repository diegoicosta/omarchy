# Operating this fork

This is a fork of [omacom/omarchy](https://github.com/omacom/omarchy) carrying changes that are not upstream. Everything outside the changes below tracks upstream unchanged.

| Change | Branch |
|---|---|
| OpenCode baseline build | `opencode-conditional` |

- **Part 1** — what the change is and why
- **Part 2** — applying it to a running Omarchy install
- **Part 3** — keeping the fork current with upstream

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

### Why the package spec ends in `.tar`

The release publishes two baseline builds for linux x64:

```
opencode-linux-x64-baseline.tar.gz        glibc — what Arch needs
opencode-linux-x64-baseline-musl.tar.gz   musl
```

`matching=` is a substring filter, so a bare `matching=baseline` matches both and ubi may select the musl build. That binary names `/lib/ld-musl-x86_64.so.1` as its interpreter, which does not exist on Arch, and running it fails with `cannot execute: required file not found` — on a file that is plainly present. `matching=baseline.tar` selects only the glibc asset, since the musl one reads `baseline-musl.tar`.

### Why the third file matters

`~/.local/bin/opencode` is a small generated wrapper with the package name baked into it, and it is what actually executes when you type `opencode` or press the agent keybinding.

`omarchy-default-agent` never rewrites that wrapper — it only runs `mise use -g <package>`. So without the third change, selecting OpenCode in the Defaults menu re-registers the stock build while the wrapper still names another, leaving two packages disagreeing about which binary should run. Patching all three keeps the install path, the menu, and the wrapper on the same package.

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
git clone git@github.com:diegoicosta/omarchy.git ~/omarchy
cd ~/omarchy
git remote add upstream https://github.com/omacom/omarchy.git
git checkout opencode-conditional
omarchy dev link ~/omarchy
```

Reboot.

### 3. Confirm the link took

```bash
echo $OMARCHY_PATH
```

Must print `/home/<you>/omarchy`. If it prints `/usr/share/omarchy`, the reboot did not happen — reboot and check again before continuing.

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

# Part 3 — Procedure: keeping the fork current

Upstream keeps releasing. The fork carries one commit that has to be replayed on top of each new upstream state. Two machines are involved: the one where you edit (the Mac) and the Omarchy machine running the checkout (the iMac).

### On the machine where you edit

```bash
cd <your checkout>
git checkout opencode-conditional
git fetch upstream
git rebase upstream/quattro
git push --force-with-lease
```

If the rebase stops on a conflict, edit the file, then `git add <file>` and `git rebase --continue`. A conflict means upstream touched `bin/omarchy-default-agent` or `install/user/mise.sh` — read it rather than resolving blindly, since it may mean the change is no longer needed.

`--force-with-lease` is required: the rebase rewrites the commit, so an ordinary push is rejected.

### On the Omarchy machine

```bash
cd ~/omarchy
git fetch
git reset --hard origin/opencode-conditional
```

**Do not use `git pull` here.** The branch history was rewritten by the rebase, so a pull tries to merge the old commit with the new one and leaves you with a duplicate commit or a conflict. `reset --hard` matches the rewritten branch exactly.

`reset --hard` also discards anything uncommitted in `~/omarchy`. That is fine — the checkout is there to be read, not edited.

No reboot is needed for a routine update. Files change in place under `$OMARCHY_PATH`, and `bin/` commands take effect on next invocation. Reboot only if an upstream change touches the session environment.

### Notes

- Sync from **`upstream/quattro`**, never from your fork's `quattro` — that copy is not the source of anything, and does not need to be kept current.
- Keeping the change on a branch costs no extra maintenance over keeping it on `quattro`; it is the same single commit replayed either way. The branch is worth keeping only if you might open a pull request upstream.

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
