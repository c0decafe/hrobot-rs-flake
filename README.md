# hrobot-rs-flake

Standalone Nix flake for packaging and working with the upstream [`MathiasPius/hrobot-rs`](https://github.com/MathiasPius/hrobot-rs) repository.

This repository is intentionally **not** a fork of the upstream source tree. Instead it pins the upstream git revision as a non-flake input, carries a reproducible `Cargo.lock`, and applies a small compatibility patch set so the pinned upstream revision passes the flake checks with the pinned Rust toolchain.

## What this flake provides

- `packages.default` / `packages.hrobot`: build the upstream `hrobot` crate
- `packages.hrobot-rs-update-readme`: safe helper for `cargo rdme`
- `packages.hrobot-rs-live-api-tests`: helper for the live Robot API integration tests
- `devShells.default`: Rust toolchain, `cargo-rdme`, `cargo-llvm-cov`, `taplo`, `rust-analyzer`, and `nixfmt`
- `checks`: package build, fmt, Taplo, Clippy, docs, and `cargo test --lib`

## Usage

```bash
# Build the pinned upstream crate
nix build github:c0decafe/hrobot-rs-flake

# Enter the development shell
nix develop github:c0decafe/hrobot-rs-flake

# Run the upstream checks at the pinned revision
nix flake check github:c0decafe/hrobot-rs-flake
```

## Working in an upstream checkout

The helper commands are meant to be run from a checkout of the original repository.

```bash
cd ~/workspaces/hrobot-rs

# Regenerate README.md from crate docs
nix run github:c0decafe/hrobot-rs-flake#update-readme

# Run the live API tests (requires credentials)
export HROBOT_USERNAME='#ws+...'
export HROBOT_PASSWORD='...'
nix run github:c0decafe/hrobot-rs-flake#live-api-tests
```

## Maintenance

When upstream moves forward:

1. update the `hrobot-src` input in `flake.lock`
2. regenerate `Cargo.lock` against that upstream revision
3. refresh `patches/upstream-modern-toolchain.patch` if upstream changed in overlapping areas
4. rerun `nix flake check`
