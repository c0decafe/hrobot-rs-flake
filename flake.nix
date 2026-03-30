{
  description = "Standalone Nix flake for the upstream hrobot-rs project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hrobot-src = {
      url = "github:MathiasPius/hrobot-rs";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    flake-utils,
    rust-overlay,
    hrobot-src,
  }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        toolchain = pkgs.rust-bin.stable.latest.minimal.override {
          extensions = [
            "clippy"
            "rust-src"
            "rustfmt"
          ];
        };
        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;

        cargoToml = builtins.fromTOML (builtins.readFile "${hrobot-src}/Cargo.toml");
        pname = cargoToml.package.name;
        version = cargoToml.package.version;

        upstreamSrc = pkgs.runCommand "${pname}-upstream-src-${version}" { } ''
          cp -R ${hrobot-src} $out
          chmod -R u+w $out
          cp ${./Cargo.lock} $out/Cargo.lock
        '';

        patchedSrc = pkgs.applyPatches {
          name = "${pname}-patched-src-${version}";
          src = upstreamSrc;
          patches = [
            ./patches/upstream-modern-toolchain.patch
          ];
        };

        src = craneLib.cleanCargoSource patchedSrc;

        baseArgs = {
          inherit pname version src;
          strictDeps = true;
        };

        cargoArtifacts = craneLib.buildDepsOnly baseArgs;

        package = craneLib.buildPackage (
          baseArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
          }
        );

        fmt = craneLib.cargoFmt {
          inherit src;
        };

        taploCheck = craneLib.taploFmt {
          inherit src;
        };

        clippy = craneLib.cargoClippy (
          baseArgs
          // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets --all-features -- --deny warnings";
          }
        );

        docs = craneLib.cargoDoc (
          baseArgs
          // {
            inherit cargoArtifacts;
            cargoDocExtraArgs = "--no-deps";
          }
        );

        unitTests = craneLib.cargoTest (
          baseArgs
          // {
            inherit cargoArtifacts;
            doCheck = true;
            cargoTestExtraArgs = "--lib";
          }
        );

        checks = {
          inherit package fmt clippy docs unitTests;
          taplo = taploCheck;
        };

        checkoutPrelude = ''
          if [ -n "''${HROBOT_RS_DIR:-}" ]; then
            cd "$HROBOT_RS_DIR"
          fi

          if [ ! -f Cargo.toml ] || [ ! -f README.md ]; then
            echo "Run this command from an hrobot-rs checkout or set HROBOT_RS_DIR=/path/to/hrobot-rs." >&2
            exit 1
          fi
        '';

        updateReadme = pkgs.writeShellApplication {
          name = "hrobot-rs-update-readme";
          runtimeInputs = [
            toolchain
            pkgs.cargo-rdme
          ];
          text = ''
            set -euo pipefail
            ${checkoutPrelude}
            exec cargo rdme > README.md
          '';
        };

        liveApiTests = pkgs.writeShellApplication {
          name = "hrobot-rs-live-api-tests";
          runtimeInputs = [
            toolchain
          ];
          text = ''
            set -euo pipefail
            ${checkoutPrelude}
            : "''${HROBOT_USERNAME:?set HROBOT_USERNAME to run the live Robot API tests}"
            : "''${HROBOT_PASSWORD:?set HROBOT_PASSWORD to run the live Robot API tests}"
            exec cargo test --tests -- --test-threads=1
          '';
        };
      in
      {
        packages = {
          default = package;
          ${pname} = package;
          hrobot-rs-update-readme = updateReadme;
          hrobot-rs-live-api-tests = liveApiTests;
        };

        inherit checks;

        apps = {
          update-readme = {
            type = "app";
            program = "${updateReadme}/bin/hrobot-rs-update-readme";
            meta.description = "Regenerate README.md from crate documentation in an hrobot-rs checkout";
          };
          live-api-tests = {
            type = "app";
            program = "${liveApiTests}/bin/hrobot-rs-live-api-tests";
            meta.description = "Run the live Hetzner Robot integration tests from an hrobot-rs checkout";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            toolchain
            cargo-llvm-cov
            cargo-rdme
            nixfmt
            rust-analyzer
            taplo
          ];
          RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
        };

        formatter = pkgs.nixfmt;
      }
    );
}
