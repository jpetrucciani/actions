# Publish Nix Cache

A composite GitHub Action that uses the runner's Nix to publish build outputs or a flake's locked sources. It accepts writable `s3://` and `file:///` Nix binary cache URLs. Each call logs its native Nix operation and elapsed time.

## Usage

Run `copy` for each platform that produced outputs. Pass the result links or store paths from the build, one per line.

```yaml
- uses: jpetrucciani/actions/nix/publish-cache@<commit-sha>
  with:
    destination: s3://my-cache?region=us-east-1&compression=zstd
    paths: |
      ./result
      ./other-output
    signing-key: ${{ secrets.NIX_CACHE_SIGNING_KEY }}
```

Run `archive` once per checkout in a job with the same source revision and lock file. It can run alongside the platform builds.

```yaml
- uses: jpetrucciani/actions/nix/publish-cache@<commit-sha>
  with:
    destination: s3://my-cache?region=us-east-1&compression=zstd
    mode: archive
    flake: '.'
    signing-key: ${{ secrets.NIX_CACHE_SIGNING_KEY }}
```

For S3, use a build of Nix with AWS support and provide credentials through the AWS credential chain. Restrict publish jobs to trusted refs or environments. The optional `signing-key` is the raw Nix signing key. The action writes it to a private temporary file for the duration of the operation. The read URL and public key go in the consumer's Nix configuration.

## Local benchmark

From the repository root, run `bash nix/publish-cache/benchmarks/local.sh 5` with Nix 2.34 or newer and `jq`. It creates disposable local stores, generates a test key, and uses the action scripts to publish and verify signed output paths and flake sources. It also checks that invalid mode and path combinations fail. Pass `0` to run the tests without timing samples.

| Nix 2.34.9, local file cache, five samples | Native Nix |  Action |
| ------------------------------------------ | ---------: | ------: |
| xz, cold destination                       |    3.386 s | 3.201 s |
| xz, warm destination                       |    0.029 s | 0.027 s |
| zstd, cold destination                     |    0.048 s | 0.051 s |
| zstd, warm destination                     |    0.024 s | 0.028 s |

These are medians for an 8 MiB incompressible payload and a small second path. With zstd the action added about 3–4 ms over the native command. The xz runs varied more than the difference between the two implementations. The benchmark excludes S3 requests and the time saved by running one flake archive across a multi-platform build.
