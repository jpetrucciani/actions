# Setup Nix

A composite GitHub Action that prepares Nix, enables flakes, and configures the signed `cache.g7c.us` substituter. It reuses Nix from the runner's PATH or a standard profile. On a fresh runner it downloads a platform-specific, SHA-256-pinned Nix 2.36.0 release and runs the installer bundled in that archive.

Fresh installs support x86_64 and ARM64 Linux and Apple Silicon macOS. The action installs a daemon on macOS and systemd-based Linux, and uses a single-user installation on other Linux systems. The OS installer needs permission to prepare `/nix`.

## Usage

```yaml
- uses: jpetrucciani/actions/nix/setup@<commit-sha>
- run: nix flake check --no-write-lock-file
```

- `use-g7c-cache` defaults to `true`. Set it to `false` to skip adding `cache.g7c.us` and its public key. Nix's regular cache remains available.
- `extra-nix-config` supplies job settings, including additional substituters and keys. A fresh daemon installation writes these to its system configuration, and an inherited `NIX_CONFIG` can override them in the client. A reused daemon keeps its existing trust policy.
- `github-token` defaults to the workflow token for GitHub fetches. Set an empty string to skip authentication.
- `trust-runner` defaults to `false`. On a fresh daemon installation, `true` gives the runner account root-equivalent authority through Nix.
- `version` and `reused` report the Nix version and whether it was already installed.

## Local benchmark

From the repository root, run `bash nix/setup/benchmarks/install.sh 5` with Docker and the `fedora:41` image available locally. Each cold sample starts in a fresh container with a single-user store. The script alternates the order of the candidate and Cachix v32.0.0, verifies the Nix version and job configuration, and checks reuse from a standard profile without Nix on PATH. Both installers use the same cache settings. The timings exclude container startup.

| Linux x86_64, five samples |  Median |         Range |
| -------------------------- | ------: | ------------: |
| Cachix cold install        | 2.629 s | 2.623–2.938 s |
| Setup Nix cold install     | 2.447 s | 2.359–2.834 s |
| Setup Nix profile reuse    | 0.051 s | 0.050–0.065 s |

The cold install gain was 0.182 seconds at the median, and the ranges overlap. The [hosted benchmark workflow](../../.github/workflows/benchmark.yml) compares the daemon installs on Ubuntu and macOS.
