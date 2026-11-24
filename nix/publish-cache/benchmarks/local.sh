#!/usr/bin/env bash
set -euo pipefail

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
samples=${1:-5}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/publish-nix-cache-benchmark.XXXXXXXX")
trap 'chmod -R u+w "$scratch"; rm -rf -- "$scratch"' EXIT
cd "$scratch"

# Keep all Nix writes in the temporary stores and cache directories.
export NIX_REMOTE="$scratch/store" NIX_CONF_DIR="$scratch/config" XDG_CACHE_HOME="$scratch/xdg-cache"
export NIX_CONFIG=$'experimental-features = nix-command flakes\nbuild-users-group =\nsubstituters ='
mkdir -p "$NIX_CONF_DIR" flake input
if ((samples == 0)); then
  printf 'cache output\n' >payload
else
  dd if=/dev/urandom of=payload bs=1M count=8 2>/dev/null
fi
printf 'cache input\n' >input/content
cat >flake/flake.nix <<EOF
{
  inputs.fixture = { url = "path:$scratch/input"; flake = false; };
  outputs = { self, fixture }: { };
}
EOF
nix flake lock "path:$scratch/flake"
archive_paths=$(nix flake archive --json --dry-run "path:$scratch/flake")

first=$(nix store add payload)
second=$(nix store add input/content)
ln -s "$second" 'result link'
export NIX_CACHE_PATHS="$first"$'\nresult link'
NIX_CACHE_SIGNING_KEY=$(nix key generate-secret --key-name benchmark)
export NIX_CACHE_SIGNING_KEY
public_key=$(nix key convert-secret-to-public <<<"$NIX_CACHE_SIGNING_KEY")

expect_failure() {
  if bash "$project/publish-nix-cache.sh"; then
    echo 'Expected the action to fail with these inputs' >&2
    exit 1
  fi
}

export NIX_CACHE_DESTINATION="file://$scratch/signed?compression=zstd"
NIX_CACHE_PATHS='' expect_failure
bash "$project/publish-nix-cache.sh"
nix store verify --store "$NIX_CACHE_DESTINATION" --trusted-public-keys "$public_key" --sigs-needed 1 "$first" "$second"

export NIX_CACHE_MODE=archive NIX_CACHE_FLAKE="path:$scratch/flake"
expect_failure
NIX_CACHE_PATHS='' bash "$project/publish-nix-cache.sh"
readarray -t sources < <(jq -er '.path, .inputs.fixture.path' <<<"$archive_paths")
test "${#sources[@]}" -eq 2
nix store verify --store "$NIX_CACHE_DESTINATION" --trusted-public-keys "$public_key" --sigs-needed 1 "${sources[@]}"
nix path-info --store "$NIX_CACHE_DESTINATION" --json --json-format 1 "$first" "$second" "${sources[@]}" |
  jq -e 'all(.[]; any(.signatures[]?; startswith("benchmark:")))' >/dev/null

if ((samples == 0)); then
  exit 0
fi

unset NIX_CACHE_SIGNING_KEY NIX_CACHE_MODE
printf '\nimplementation,compression,sample,state,seconds\n'
for compression in xz zstd; do
  for ((sample = 1; sample <= samples; sample++)); do
    for implementation in native action; do
      export NIX_CACHE_DESTINATION="file://$scratch/$compression-$sample-$implementation?compression=$compression"
      for state in cold warm; do
        TIMEFORMAT="$implementation,$compression,$sample,$state,%3R"
        if [[ $implementation == native ]]; then
          time nix copy --refresh --to "$NIX_CACHE_DESTINATION" "$first" "$second" >/dev/null 2>operation.log
        else
          time bash "$project/publish-nix-cache.sh" >/dev/null 2>operation.log
        fi || {
          cat operation.log >&2
          exit 1
        }
      done
    done
  done
done
