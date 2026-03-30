# hrobot-rs-flake

Standalone Nix flake for packaging and working with the upstream [`MathiasPius/hrobot-rs`](https://github.com/MathiasPius/hrobot-rs) repository.

This repository is intentionally **not** a fork of the upstream source tree. Instead it pins the upstream git revision as a non-flake input, carries a reproducible `Cargo.lock`, and applies a small compatibility patch set so the pinned upstream revision passes the flake checks with the pinned Rust toolchain.

## What this flake provides

- `packages.default` / `packages.hrobot-helper`: install the `hrobot` helper CLI
- `packages.hrobot` / `packages.hrobot-crate`: build the pinned upstream `hrobot` crate
- `devShells.default`: Rust toolchain, `cargo-rdme`, `cargo-llvm-cov`, `taplo`, `rust-analyzer`, and `nixfmt`
- `checks`: package build, fmt, Taplo, Clippy, docs, and `cargo test --lib`

## Usage

```bash
# Install the helper CLI into your user profile
nix profile install github:c0decafe/hrobot-rs-flake

# Build the pinned upstream crate explicitly
nix build github:c0decafe/hrobot-rs-flake#hrobot

# Run the helper CLI
nix run github:c0decafe/hrobot-rs-flake -- help

# List ready/running servers
HROBOT_USERNAME=... HROBOT_PASSWORD=... \
  nix run github:c0decafe/hrobot-rs-flake -- servers

# Enter the development shell
nix develop github:c0decafe/hrobot-rs-flake

# Run the upstream checks at the pinned revision
nix flake check github:c0decafe/hrobot-rs-flake
```

## Working in an upstream checkout

The helper commands are meant to be run from a checkout of the original repository. You can either `cd` into a checkout first, or set `HROBOT_RS_DIR` and run them from anywhere.

```bash
git clone https://github.com/MathiasPius/hrobot-rs.git ~/src/hrobot-rs

# Regenerate README.md from crate docs
HROBOT_RS_DIR=~/src/hrobot-rs \
  nix run github:c0decafe/hrobot-rs-flake#hrobot -- update-readme

# Run the live API tests (requires credentials)
export HROBOT_USERNAME='#ws+...'
export HROBOT_PASSWORD='...'
HROBOT_RS_DIR=~/src/hrobot-rs \
  nix run github:c0decafe/hrobot-rs-flake#hrobot -- live-api-tests
```

For Robot API calls, `hrobot` reads credentials from either:

- `HROBOT_USERNAME` and `HROBOT_PASSWORD`
- `HROBOT_USERNAME_FILE` and `HROBOT_PASSWORD_FILE`

The `servers` subcommand lists ready/running servers by default. Use `--all` to include non-ready servers and `--json` for machine-readable output.

## Home Manager integration

```nix
{
  inputs.hrobot-rs-flake.url = "github:c0decafe/hrobot-rs-flake";

  home.packages = [
    inputs.hrobot-rs-flake.packages.${pkgs.system}.hrobot-helper
  ];
}
```

## Maintenance

When upstream moves forward:

1. update the `hrobot-src` input in `flake.lock`
2. regenerate `Cargo.lock` against that upstream revision
3. refresh `patches/upstream-modern-toolchain.patch` if upstream changed in overlapping areas
4. rerun `nix flake check`
