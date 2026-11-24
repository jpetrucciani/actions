# GitHub Actions

Reusable GitHub Actions for setting up Nix and publishing its build outputs and flake sources.

| Action                                    | Purpose                                                                       |
| ----------------------------------------- | ----------------------------------------------------------------------------- |
| [`nix/setup`](nix/setup/)                 | Set up Nix with flakes and the signed `cache.g7c.us` substituter.             |
| [`nix/publish-cache`](nix/publish-cache/) | Publish a build closure or archive a flake to an explicitly configured cache. |

Reference each action by its directory and a commit SHA from this repository.

```yaml
- uses: jpetrucciani/actions/nix/setup@<commit-sha>
- run: nix build .#my-package
- uses: jpetrucciani/actions/nix/publish-cache@<commit-sha>
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  with:
    destination: s3://my-cache?region=us-east-1&compression=zstd
    paths: ./result
    signing-key: ${{ secrets.NIX_CACHE_SIGNING_KEY }}
```

The publisher uses the runner's AWS credential configuration. Its README covers the separate flake archive mode and the local file cache.

## Development

```sh
nix develop
nix fmt
nix run .#lint
nix run .#test
nix flake check
```

`lint` checks formatting, shell scripts, and workflow definitions. `test` checks setup configuration and signed cache publication using disposable local stores. `nix flake check` runs both. For untracked files, use a path flake reference such as `nix flake check path:.` or `nix run path:.#lint`.

[Check](.github/workflows/check.yml) exercises both composite actions and the flake checks on Ubuntu and macOS. The [installer benchmark](.github/workflows/benchmark.yml) is available as a manually dispatched workflow. Each action's README describes its local benchmarks.
