#!/usr/bin/env nu
# check-deps.nu
# Thin wrapper around nix flake check.
# The canonical deps check is: nix flake check

def main [] {
    print "Checking development environment via Nix..."
    let result = (^nix flake check o+e>| complete)
    if $result.exit_code != 0 {
        error make {msg: $"Environment check failed: ($result.stderr)"}
    }
    print $"(ansi green)All environment checks passed.(ansi reset)"
}
