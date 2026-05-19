{ pkgs ? import <nixpkgs> {} }:
(import
  (builtins.fetchTarball "https://github.com/edolstra/flake-compat/archive/v1.0.0.tar.gz")
  { src = ./.; })
