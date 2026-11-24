#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/setup-nix-benchmark.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
image=${BENCHMARK_IMAGE:-fedora:41}
samples=${1:-3}
cachix_revision=bb0495a1086c46893eee56f32fd192dfe4a15bb9
curl --fail --silent --show-error --location --max-time 30 \
  --output "$scratch/cachix.sh" \
  "https://raw.githubusercontent.com/cachix/install-nix-action/$cachix_revision/install-nix.sh"
chmod a+rx "$scratch"
chmod a+r "$scratch/cachix.sh"

for ((sample = 1; sample <= samples; sample++)); do
  order=(cachix candidate)
  if ((sample % 2 == 0)); then
    order=(candidate cachix)
  fi
  for installer in "${order[@]}"; do
    docker run --pull=never --rm -i --entrypoint /bin/bash \
      -v "$scratch/cachix.sh:/cachix.sh:ro" -v "$project/setup-nix.sh:/candidate.sh:ro" \
      "$image" -es -- "$installer" "$sample" <<'CONTAINER'
useradd -m runner
mkdir /nix
chown runner /nix
printf 'runner ALL=(root) NOPASSWD: ALL\n' >/etc/sudoers.d/runner
sudo -u runner -- /bin/bash -es -- "$@" <<'RUNNER'
set -euo pipefail
cd "$HOME"
export GITHUB_ENV="$HOME/github-env" GITHUB_PATH="$HOME/github-path" GITHUB_OUTPUT="$HOME/github-output"
export RUNNER_TEMP="$HOME" GITHUB_SERVER_URL=https://github.com
export INPUT_SET_AS_TRUSTED_USER=false INPUT_ENABLE_KVM=false INPUT_INSTALL_OPTIONS=--no-daemon
export SETUP_NIX_EXTRA_CONFIG='max-jobs = 2'
export SETUP_NIX_USE_G7C_CACHE=false
export INPUT_EXTRA_NIX_CONFIG=$'extra-experimental-features = nix-command flakes\n'"$SETUP_NIX_EXTRA_CONFIG"
TIMEFORMAT=$(printf '%s,%s,%%3R' "$1" "$2")
time bash "/$1.sh" >"$HOME/install.log" 2>&1 || { cat "$HOME/install.log" >&2; exit 1; }
runner_path=$PATH
export PATH="$(cat "$GITHUB_PATH"):$PATH"
test "$(nix --version)" = "nix (Nix) 2.36.0"
if [[ $1 == candidate ]]; then
  sed '1d;$d' "$GITHUB_ENV" >"$HOME/job-nix-config"
  export NIX_CONFIG="$(cat "$HOME/job-nix-config")"
  test "$(cat "$GITHUB_OUTPUT")" = $'version=2.36.0\nreused=false'
  : >"$GITHUB_OUTPUT"
  TIMEFORMAT=$(printf 'reuse,%s,%%3R' "$2")
  time PATH="$runner_path" bash /candidate.sh >"$HOME/reuse.log" 2>&1 || { cat "$HOME/reuse.log" >&2; exit 1; }
  test "$(cat "$GITHUB_OUTPUT")" = $'version=2.36.0\nreused=true'
fi
test "$(nix config show max-jobs)" = 2
test "$(nix eval --expr '1 + 1')" = 2
RUNNER
CONTAINER
  done
done
