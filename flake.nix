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

        hrobotHelper = pkgs.writeShellApplication {
          name = "hrobot";
          runtimeInputs = [
            toolchain
            pkgs.cargo-rdme
            pkgs.curl
            pkgs.python3
          ];
          text = ''
            set -euo pipefail

            usage() {
              printf '%s\n' \
                'Usage: hrobot <command>' \
                "" \
                'Commands:' \
                '  update-readme    Regenerate README.md from crate documentation' \
                '  live-api-tests   Run the live Hetzner Robot integration tests' \
                '  servers          List ready/running servers from the Robot API' \
                '  help             Show this help text'
            }

            load_secret() {
              local value_var="$1"
              local file_var="$2"
              local value="''${!value_var:-}"
              local file_path="''${!file_var:-}"

              if [ -n "$value" ]; then
                printf '%s' "$value"
                return 0
              fi

              if [ -n "$file_path" ]; then
                if [ ! -f "$file_path" ]; then
                  echo "$file_var points to a missing file: $file_path" >&2
                  exit 1
                fi
                local file_value
                file_value="$(<"$file_path")"
                if [ -z "$file_value" ]; then
                  echo "$file_var points to an empty file: $file_path" >&2
                  exit 1
                fi
                printf '%s' "$file_value"
                return 0
              fi

              return 1
            }

            require_robot_auth() {
              ROBOT_USERNAME="$(load_secret HROBOT_USERNAME HROBOT_USERNAME_FILE || true)"
              ROBOT_PASSWORD="$(load_secret HROBOT_PASSWORD HROBOT_PASSWORD_FILE || true)"

              if [ -z "$ROBOT_USERNAME" ] || [ -z "$ROBOT_PASSWORD" ]; then
                echo "Set HROBOT_USERNAME/HROBOT_PASSWORD or HROBOT_USERNAME_FILE/HROBOT_PASSWORD_FILE." >&2
                exit 1
              fi
            }

            command="''${1:-help}"
            shift || true

            case "$command" in
              update-readme)
                if [ "$#" -ne 0 ]; then
                  echo "update-readme does not accept extra arguments." >&2
                  usage >&2
                  exit 1
                fi
                ${checkoutPrelude}
                exec cargo rdme > README.md
                ;;
              live-api-tests)
                if [ "$#" -ne 0 ]; then
                  echo "live-api-tests does not accept extra arguments." >&2
                  usage >&2
                  exit 1
                fi
                ${checkoutPrelude}
                : "''${HROBOT_USERNAME:?set HROBOT_USERNAME to run the live Robot API tests}"
                : "''${HROBOT_PASSWORD:?set HROBOT_PASSWORD to run the live Robot API tests}"
                exec cargo test --tests -- --test-threads=1
                ;;
              servers|list-running-servers)
                show_all=0
                as_json=0
                while [ "$#" -gt 0 ]; do
                  case "$1" in
                    --all)
                      show_all=1
                      ;;
                    --json)
                      as_json=1
                      ;;
                    -h|--help)
                      printf '%s\n' \
                        'Usage: hrobot servers [--all] [--json]' \
                        "" \
                        'By default this lists ready/running servers only.' \
                        "" \
                        'Options:' \
                        '  --all   Include non-ready servers too' \
                        '  --json  Emit JSON instead of a table'
                      exit 0
                      ;;
                    *)
                      echo "Unknown option for servers: $1" >&2
                      exit 1
                      ;;
                  esac
                  shift
                done

                require_robot_auth

                curl --fail --silent --show-error \
                  --user "$ROBOT_USERNAME:$ROBOT_PASSWORD" \
                  "https://robot-ws.your-server.de/server" \
                  | python3 -c '
import json
import sys

show_all = sys.argv[1] == "1"
as_json = sys.argv[2] == "1"

payload = json.load(sys.stdin)
servers = [item["server"] for item in payload]

if not show_all:
    servers = [
        server
        for server in servers
        if server.get("status") == "ready" and not server.get("cancelled", False)
    ]

servers.sort(key=lambda server: (server.get("server_name", ""), server.get("server_number", 0)))

if as_json:
    json.dump(servers, sys.stdout, indent=2)
    sys.stdout.write("\\n")
    raise SystemExit(0)

if not servers:
    print("No matching servers found.")
    raise SystemExit(0)

headers = ("id", "name", "status", "product", "dc", "ipv4")
rows = [
    (
        str(server.get("server_number", "")),
        server.get("server_name", ""),
        server.get("status", ""),
        server.get("product", ""),
        server.get("dc", ""),
        server.get("server_ip", "") or "",
    )
    for server in servers
]

widths = [
    max(len(header), *(len(row[idx]) for row in rows))
    for idx, header in enumerate(headers)
]

def emit(row):
    print("  ".join(value.ljust(widths[idx]) for idx, value in enumerate(row)))

emit(headers)
emit(tuple("-" * width for width in widths))
for row in rows:
    emit(row)
' "$show_all" "$as_json"
                ;;
              help|-h|--help)
                usage
                ;;
              *)
                echo "Unknown command: $command" >&2
                usage >&2
                exit 1
                ;;
            esac
          '';
        };
      in
      {
        packages = {
          default = hrobotHelper;
          ${pname} = package;
          hrobot-crate = package;
          hrobot-helper = hrobotHelper;
        };

        inherit checks;

        apps = {
          default = {
            type = "app";
            program = "${hrobotHelper}/bin/hrobot";
            meta.description = "Helper CLI for working with an hrobot-rs checkout";
          };
          hrobot = {
            type = "app";
            program = "${hrobotHelper}/bin/hrobot";
            meta.description = "Helper CLI for working with an hrobot-rs checkout";
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
