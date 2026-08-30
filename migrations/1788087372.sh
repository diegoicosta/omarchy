echo "Install Kilo Code via mise wrapper and wire it into Omarchy"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install npm:@kilocode/cli kilo
fi

# The shipped config reaches new users through /etc/skel, which an existing
# install has already been seeded from. Copy only what is missing, so a machine
# that already runs Kilo keeps the config it has.
had_tui_config=0
[[ -f $HOME/.config/kilo/tui.jsonc ]] && had_tui_config=1

mkdir -p "$HOME/.config/kilo"
for config in kilo.jsonc tui.jsonc; do
  [[ -e $HOME/.config/kilo/$config ]] && continue
  [[ -f $OMARCHY_PATH/config/kilo/$config ]] || continue
  cp "$OMARCHY_PATH/config/kilo/$config" "$HOME/.config/kilo/$config"
done

# Kilo already reads ~/.agents/skills, which omarchy-provision-user fills, so
# this is about its own skills directory: the one /reload and Kilo's own skill
# listing look at first.
skills_source="$OMARCHY_PATH/default/agents/skills"
if [[ -d $skills_source ]]; then
  mkdir -p "$HOME/.kilo/skills"
  for skill in "$skills_source"/*/; do
    [[ -d $skill ]] || continue
    name=${skill%/}
    ln -sfn "$name" "$HOME/.kilo/skills/${name##*/}"
  done
fi

# Install the generated theme either way, but only select it for someone who
# was not already running Kilo with a theme of their own choosing.
if (( had_tui_config )); then
  omarchy-theme-set-kilo || true
else
  omarchy-theme-set-kilo --activate || true
fi
