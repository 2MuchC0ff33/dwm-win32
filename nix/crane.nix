{ pkgs, rustToolchain, crane, ... }:
(crane.mkLib pkgs).overrideToolchain rustToolchain
