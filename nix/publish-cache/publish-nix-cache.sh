#!/usr/bin/env bash
set -euo pipefail

destination=${NIX_CACHE_DESTINATION:?Set NIX_CACHE_DESTINATION to a writable binary cache URL}
case "$destination" in
s3://?* | file:///*) ;;
*)
  echo 'destination must be an s3:// or file:/// binary cache URL' >&2
  exit 2
  ;;
esac

mode=${NIX_CACHE_MODE:-copy}
case "$mode" in
copy)
  paths=()
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    case "$path" in
    /* | ./* | ../*) paths+=("$path") ;;
    *) paths+=("./$path") ;;
    esac
  done <<<"${NIX_CACHE_PATHS:-}"
  if ((${#paths[@]} == 0)); then
    echo 'copy mode requires at least one path' >&2
    exit 2
  fi
  ;;
archive)
  if [[ -n ${NIX_CACHE_PATHS:-} ]]; then
    echo 'paths is only valid in copy mode' >&2
    exit 2
  fi
  ;;
*)
  echo 'mode must be copy or archive' >&2
  exit 2
  ;;
esac

if [[ -n ${NIX_CACHE_SIGNING_KEY:-} ]]; then
  case "$destination" in
  *\?secret-key=* | *\&secret-key=* | *\?secret-keys=* | *\&secret-keys=*)
    echo 'Configure the signing key through either the action input or the destination URL' >&2
    exit 2
    ;;
  esac
  # Nix expects a key file. Pass its path via the URL and keep the key out of arguments.
  umask 077
  key_dir=$(mktemp -d /tmp/nix-cache-signing.XXXXXXXX)
  trap 'rm -rf -- "$key_dir"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '%s\n' "$NIX_CACHE_SIGNING_KEY" >"$key_dir/key"
  case "$destination" in
  *\?*) destination+="&secret-key=$key_dir/key" ;;
  *) destination+="?secret-key=$key_dir/key" ;;
  esac
fi
unset NIX_CACHE_SIGNING_KEY

TIMEFORMAT="Nix cache $mode took %3R seconds"
case "$mode" in
copy)
  time nix --extra-experimental-features nix-command copy --refresh --to "$destination" -- "${paths[@]}"
  ;;
archive)
  time nix --extra-experimental-features 'nix-command flakes' flake archive \
    --no-update-lock-file --no-write-lock-file --to "$destination" -- "${NIX_CACHE_FLAKE:-.}"
  ;;
esac
