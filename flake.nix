{
  description = "dwm-win32: dwm window manager for Windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      fenix,
      crane,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

        rustToolchain = fenix.packages.${system}.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };

        craneLib = import ./nix/crane.nix {
          inherit pkgs rustToolchain crane;
        };

        targets = import ./nix/targets.nix;
        callPackage = pkgs.callPackage;

        mkPkg =
          targetKey:
          let
            target = targets.targets.${targetKey};
            crossPkgs = import nixpkgs {
              inherit system;
              crossSystem = pkgs.lib.systems.examples.${target.pkgsCross};
              overlays = [ self.overlays.default ];
            };
            crossRustToolchain = fenix.packages.${system}.fromToolchainFile {
              file = ./rust-toolchain.toml;
              sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            };
            crossCraneLib = import ./nix/crane.nix {
              pkgs = crossPkgs;
              rustToolchain = crossRustToolchain;
              inherit crane;
            };
          in
          callPackage ./nix/package.nix {
            craneLib = crossCraneLib;
            pkgs = crossPkgs;
            inherit system;
            targetTriple = target.triple;
            targetName = targetKey;
          };

        targetNames = builtins.attrNames targets.targets;
        targetPkgs = builtins.listToAttrs (
          map (k: {
            name = k;
            value = mkPkg k;
          }) targetNames
        );

        package = callPackage ./nix/package.nix {
          inherit craneLib pkgs system;
          targetTriple = pkgs.stdenv.hostPlatform.config;
          targetName = system;
        };
      in
      {
        packages = targetPkgs // {
          default = package;
          all = pkgs.symlinkJoin {
            name = "dwm-win32-all";
            paths = builtins.attrValues targetPkgs;
          };
        };

        devShells.default = pkgs.mkShell {
          name = "dwm-win32-dev";
          buildInputs = with pkgs; [
            rustToolchain
            just
            zig
            asciidoctor
            pandoc
            vale
            nushell
            fd
            ripgrep
            bat
            delta
            zoxide
            bottom
            eza
            jujutsu
          ];
        };
      }
    )
    // {
      overlays.default = final: prev: { };
    };
}
