# Build the lazy shims for Omarchy's default tools and the account dispatchers,
# both declared by /etc/mise/conf.d, without resolving versions over the network.
MISE_OFFLINE=true mise reshim --system
MISE_OFFLINE=true mise reshim

# Fork: OpenCode is built with Bun, whose stock build targets x86-64-v3 and dies
# with an illegal instruction on a CPU without AVX2. Upstream's own installer
# picks the baseline release in that case; mise's registry entry does not, so
# choose it here. The match ends in .tar because the release carries both a glibc
# and a musl baseline asset, and a bare 'baseline' matches the musl one.
if omarchy-hw-avx2; then
  omarchy-mise-install opencode
else
  omarchy-mise-install "ubi:anomalyco/opencode[matching=baseline.tar]" opencode
fi
