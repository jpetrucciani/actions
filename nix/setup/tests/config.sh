#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/setup-nix-test.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

export NIX_CONF_DIR="$scratch/config" NIX_REMOTE="$scratch/store" XDG_CACHE_HOME="$scratch/xdg-cache"
export NIX_USER_CONF_FILES="$scratch/config/nix.conf"
export GITHUB_ENV="$scratch/env" GITHUB_PATH="$scratch/path" GITHUB_OUTPUT="$scratch/output"
export NIX_CONFIG=$'build-users-group =\nsubstituters = https://cache.nixos.org/'
export SETUP_NIX_EXTRA_CONFIG='max-jobs = 2'
mkdir -p "$NIX_CONF_DIR"
unset SETUP_NIX_USE_G7C_CACHE SETUP_NIX_GITHUB_TOKEN

read_config() {
  NIX_CONFIG="$(sed '1d;$d' "$GITHUB_ENV")" nix config show --json
}

bash "$action_dir/setup-nix.sh"
read_config |
  jq -e '
    (.substituters.value | index("https://cache.g7c.us") != null and index("https://cache.nixos.org/") != null)
    and (.["trusted-public-keys"].value | any(startswith("cache.g7c.us:")))
    and (.["max-jobs"].value | tonumber == 2)
  ' >/dev/null

: >"$GITHUB_ENV"
SETUP_NIX_USE_G7C_CACHE=false bash "$action_dir/setup-nix.sh"
read_config |
  jq -e '
    (.substituters.value | index("https://cache.g7c.us") == null)
    and (.["trusted-public-keys"].value | all(startswith("cache.g7c.us:") | not))
  ' >/dev/null
